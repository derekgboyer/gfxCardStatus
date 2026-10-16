//
//  GSPowerSourceController.m
//  gfxCardStatus
//

#import "GSPowerSourceController.h"
#import "GSGPU.h"
#import "GSMux.h"
#import "GSNotifier.h"
#import "GSPreferences.h"
#import "GSProcess.h"

#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

NSString * const GSPowerSourceStateDidChangeNotification = @"GSPowerSourceStateDidChangeNotification";

// Long enough to collapse the extra IOKit readings that show up while a
// cable is plugged or unplugged, short enough that the switch still feels
// tied to the event.
static const NSTimeInterval kPowerSourceDebounceInterval = 0.35;

static void *GSPowerMasterContext = &GSPowerMasterContext;
static void *GSPowerBatteryContext = &GSPowerBatteryContext;
static void *GSPowerACContext = &GSPowerACContext;

static void _powerSourceCallback(void *context);

@interface GSPowerSourceController ()
- (void)_handlePowerSourceCallback;
- (void)_evaluatePowerSource;
- (void)_applyForCurrentSource;
- (NSString *)_keyPathForPreferenceKey:(NSString *)key;
@end

@implementation GSPowerSourceController {
    GSPowerTracker _tracker;
    GSPowerSource _currentSource;
    BOOL _started;
    BOOL _applying;
    CFRunLoopSourceRef _runLoopSource;
    NSTimer *_debounceTimer;
    GSPowerSource _lastBlockedSource;
    NSString *_lastBlockedSignature;
    BOOL _observingPreferences;
}

+ (GSPowerSourceController *)sharedController
{
    static GSPowerSourceController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[GSPowerSourceController alloc] init];
    });
    return controller;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _currentSource = GSPowerSourceUnknown;
        _lastBlockedSource = GSPowerSourceUnknown;
    }
    return self;
}

- (void)dealloc
{
    [self _stopMonitoring];
}

- (GSPowerSource)currentSource
{
    return _currentSource;
}

- (BOOL)isManualOverrideActive
{
    return _tracker.manualOverride ? YES : NO;
}

- (BOOL)isFeatureAvailable
{
    return [[GSMux defaultMux] isOpen] && ![GSGPU isLegacyMachine];
}

- (void)startMonitoringWithManualOverride:(BOOL)manualOverride
{
    if (_started)
        return;
    _started = YES;
    _tracker.manualOverride = manualOverride ? 1 : 0;
    _currentSource = [self _readPowerSource];

    [self _startObservingPreferences];

    // The run loop source is only useful on the main thread, which is where
    // applicationDidFinishLaunching: calls this.
    _runLoopSource = IOPSNotificationCreateRunLoopSource(_powerSourceCallback, (__bridge void *)self);
    if (_runLoopSource) {
        // Common modes cover menu tracking, so a plug or unplug is noticed
        // even while the status menu is open.
        CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
        GSLogDebug(@"Registered for power source notifications.");
    } else {
        GSLogError(@"IOPSNotificationCreateRunLoopSource failed. The current source will be applied once, and later cable changes will be missed.");
    }

    // Apply the launch rule immediately. Later cable events are debounced.
    [self _evaluatePowerSource];
}

- (void)noteManualModeChange
{
    if (!self.featureAvailable)
        return;
    if (![[GSPreferences sharedInstance] shouldUsePowerSourceBasedSwitching])
        return;

    if (_tracker.manualOverride)
        return;

    _tracker.manualOverride = 1;
    // The hold replaces a pending automatic switch for this source.
    _lastBlockedSignature = nil;
    GSLogInfo(@"Manual GPU choice will hold until the power source changes.");
    [self _postStateChange];
}

#pragma mark - Power source

static void _powerSourceCallback(void *context)
{
    GSPowerSourceController *controller = (__bridge GSPowerSourceController *)context;
    [controller _handlePowerSourceCallback];
}

- (void)_handlePowerSourceCallback
{
    // IOKit invokes this on the run loop the source was added to (main).
    // Hop anyway so a future caller cannot apply rules off the main thread.
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _handlePowerSourceCallback];
        });
        return;
    }

    _currentSource = [self _readPowerSource];
    [self _postStateChange];

    [_debounceTimer invalidate];
    _debounceTimer = [NSTimer timerWithTimeInterval:kPowerSourceDebounceInterval
                                             target:self
                                           selector:@selector(_evaluatePowerSource)
                                           userInfo:nil
                                            repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:_debounceTimer forMode:NSRunLoopCommonModes];
}

- (GSPowerSource)_readPowerSource
{
    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (!blob)
        return GSPowerSourceUnknown;

    CFStringRef type = IOPSGetProvidingPowerSourceType(blob);
    GSPowerSource source = GSPowerSourceUnknown;
    if (type && CFGetTypeID(type) == CFStringGetTypeID()) {
        if (CFEqual(type, CFSTR(kIOPSBatteryPowerValue)))
            source = GSPowerSourceBattery;
        else if (CFEqual(type, CFSTR(kIOPSACPowerValue)))
            source = GSPowerSourceACAdapter;
    }
    CFRelease(blob);
    return source;
}

- (void)_evaluatePowerSource
{
    _debounceTimer = nil;
    // setMode: blocks the main thread, so this is only a guard against a
    // callback that was already queued. Ask for another pass instead of
    // dropping the reading.
    if (_applying) {
        [self _handlePowerSourceCallback];
        return;
    }

    GSPowerSource source = [self _readPowerSource];
    _currentSource = source;

    int shouldApply = 0;
    GSPowerSource previous = _tracker.lastSettledSource;
    int wasSettled = _tracker.hasSettled;
    GSPowerNoteSource(&_tracker, source, &shouldApply);
    if (wasSettled && _tracker.hasSettled && previous != _tracker.lastSettledSource)
        _lastBlockedSignature = nil;

    if (shouldApply)
        [self _applyForCurrentSource];
    [self _postStateChange];
}

- (void)_applyForCurrentSource
{
    if (_applying || !self.featureAvailable)
        return;

    GSPreferences *prefs = [GSPreferences sharedInstance];
    id<GSMuxProtocol> mux = [GSMux defaultMux];
    if (![mux isOpen])
        return;

    GSPowerContext ctx = {0};
    ctx.featureEnabled = [prefs shouldUsePowerSourceBasedSwitching] ? 1 : 0;
    ctx.manualOverride = _tracker.manualOverride;
    ctx.source = _currentSource;
    ctx.batteryMode = [prefs modeForBattery];
    ctx.acMode = [prefs modeForACAdapter];
    ctx.currentlyDynamic = [mux isUsingDynamicSwitching] ? 1 : 0;
    ctx.currentlyIntegrated = [mux isUsingIntegratedGPU] ? 1 : 0;

    NSArray *tasks = nil;
    if (ctx.featureEnabled && !ctx.manualOverride
        && (ctx.source == GSPowerSourceBattery || ctx.source == GSPowerSourceACAdapter)) {
        GSPowerSourceBasedSwitchingMode desired = (ctx.source == GSPowerSourceBattery) ? ctx.batteryMode : ctx.acMode;
        // The process walk is only needed when Integrated Only might run.
        if (desired == GSPowerSourceBasedSwitchingModeIntegrated) {
            tasks = [GSProcess getTaskList];
            ctx.hasDiscreteDependencies = tasks.count > 0 ? 1 : 0;
        }
    }

    GSPowerAction action = GSPowerDecide(&ctx);
    if (action == GSPowerActionNone)
        return;

    if (action == GSPowerActionBlockedByDependencies) {
        [self _noteBlockedTasks:tasks];
        return;
    }

    GSSwitcherMode mode;
    if (action == GSPowerActionSwitchIntegrated)
        mode = GSSwitcherModeForceIntegrated;
    else if (action == GSPowerActionSwitchDiscrete)
        mode = GSSwitcherModeForceDiscrete;
    else if (action == GSPowerActionSwitchDynamic)
        mode = GSSwitcherModeDynamicSwitching;
    else
        return;

    GSLogInfo(@"Applying power-source rule. source=%d mode=%d", (int)_currentSource, (int)mode);
    _applying = YES;
    BOOL switched = [mux setMode:mode];
    _applying = NO;
    if (!switched)
        GSLogError(@"Power-source rule could not switch the GPU.");
    else
        _lastBlockedSignature = nil;
}

- (void)_noteBlockedTasks:(NSArray *)tasks
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *dict in tasks) {
        NSString *name = dict[kTaskItemName];
        if (name.length)
            [names addObject:name];
    }
    NSString *signature = [names componentsJoinedByString:@"\n"];
    if (_lastBlockedSource == _currentSource && [signature isEqualToString:_lastBlockedSignature])
        return;

    _lastBlockedSource = _currentSource;
    _lastBlockedSignature = [signature copy];
    GSLogInfo(@"Power-source rule skipped Integrated Only because of: %@", names);
    [[GSNotifier sharedInstance] showPowerRuleBlockedNotification:names];
}

- (void)_postStateChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:GSPowerSourceStateDidChangeNotification
                                                        object:self];
}

- (void)_stopMonitoring
{
    [_debounceTimer invalidate];
    _debounceTimer = nil;
    [self _stopObservingPreferences];
    if (_runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
        CFRelease(_runLoopSource);
        _runLoopSource = NULL;
    }
}

#pragma mark - Preferences

- (NSString *)_keyPathForPreferenceKey:(NSString *)key
{
    return [@"prefsDict." stringByAppendingString:key];
}

- (void)_startObservingPreferences
{
    if (_observingPreferences)
        return;
    GSPreferences *prefs = [GSPreferences sharedInstance];
    [prefs addObserver:self
            forKeyPath:[self _keyPathForPreferenceKey:GSShouldUsePowerSourceBasedSwitchingKey]
               options:0
               context:GSPowerMasterContext];
    [prefs addObserver:self
            forKeyPath:[self _keyPathForPreferenceKey:GSPowerSourceBasedSwitchingBatteryModeKey]
               options:0
               context:GSPowerBatteryContext];
    [prefs addObserver:self
            forKeyPath:[self _keyPathForPreferenceKey:GSPowerSourceBasedSwitchingACModeKey]
               options:0
               context:GSPowerACContext];
    _observingPreferences = YES;
}

- (void)_stopObservingPreferences
{
    if (!_observingPreferences)
        return;
    GSPreferences *prefs = [GSPreferences sharedInstance];
    [prefs removeObserver:self forKeyPath:[self _keyPathForPreferenceKey:GSShouldUsePowerSourceBasedSwitchingKey] context:GSPowerMasterContext];
    [prefs removeObserver:self forKeyPath:[self _keyPathForPreferenceKey:GSPowerSourceBasedSwitchingBatteryModeKey] context:GSPowerBatteryContext];
    [prefs removeObserver:self forKeyPath:[self _keyPathForPreferenceKey:GSPowerSourceBasedSwitchingACModeKey] context:GSPowerACContext];
    _observingPreferences = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != GSPowerMasterContext && context != GSPowerBatteryContext && context != GSPowerACContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    // Bindings update the in-memory dictionary immediately and only flush it
    // when the preferences window closes. Persist now so a cable change
    // before that close still sees the edited rule after a relaunch.
    [[GSPreferences sharedInstance] savePreferences];
    [self _applyPreferenceChangeForContext:context];
    [self _postStateChange];
}

- (void)_applyPreferenceChangeForContext:(void *)context
{
    if (!self.featureAvailable)
        return;

    GSPreferences *prefs = [GSPreferences sharedInstance];
    BOOL enabled = [prefs shouldUsePowerSourceBasedSwitching];
    if (!enabled) {
        if (context == GSPowerMasterContext)
            _tracker.manualOverride = 0;
        return;
    }

    BOOL affectsCurrentSource = (context == GSPowerMasterContext);
    if (context == GSPowerBatteryContext)
        affectsCurrentSource = (_currentSource == GSPowerSourceBattery);
    else if (context == GSPowerACContext)
        affectsCurrentSource = (_currentSource == GSPowerSourceACAdapter);

    if (!affectsCurrentSource)
        return;

    // Editing the live rule, or turning the feature on, ends a manual hold.
    _tracker.manualOverride = 0;
    _lastBlockedSignature = nil;
    [self _applyForCurrentSource];
}

@end
