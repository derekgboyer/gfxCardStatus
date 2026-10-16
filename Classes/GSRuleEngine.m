//
//  GSRuleEngine.m
//  gfxCardStatus
//

#import "GSRuleEngine.h"
#import "GSNotifier.h"
#import "GSPowerSourceController.h"
#import "GSPreferences.h"
#import "GSProcess.h"

#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#import <Carbon/Carbon.h>
#pragma clang diagnostic pop

#include <stdlib.h>

NSString * const GSRuleEngineStateDidChangeNotification = @"GSRuleEngineStateDidChangeNotification";

static const NSTimeInterval kHistorySuppressionInterval = 2.0;
static const NSUInteger kHistoryLimit = 80;
static const NSUInteger kHistoryMenuLimit = 12;
static EventHotKeyRef sHotKeyRefs[3];
static BOOL sHotKeyHandlerInstalled = NO;

static UInt32 GSCarbonModifiers(NSEventModifierFlags flags)
{
    UInt32 modifiers = 0;
    if (flags & NSEventModifierFlagCommand)
        modifiers |= cmdKey;
    if (flags & NSEventModifierFlagShift)
        modifiers |= shiftKey;
    if (flags & NSEventModifierFlagOption)
        modifiers |= optionKey;
    if (flags & NSEventModifierFlagControl)
        modifiers |= controlKey;
    return modifiers;
}

static OSStatus GSHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData)
{
    (void)nextHandler;
    (void)userData;
    EventHotKeyID hotKeyID;
    OSStatus err;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    err = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID);
#pragma clang diagnostic pop
    if (err != noErr)
        return err;

    UInt32 hotKeyNumber = hotKeyID.id;
    dispatch_async(dispatch_get_main_queue(), ^{
        GSSwitcherMode mode = GSSwitcherModeDynamicSwitching;
        if (hotKeyNumber == 1)
            mode = GSSwitcherModeForceIntegrated;
        else if (hotKeyNumber == 2)
            mode = GSSwitcherModeForceDiscrete;
        else if (hotKeyNumber != 3)
            return;
        [[GSRuleEngine sharedEngine] userRequestedMode:mode source:Str(@"KeyboardShortcut")];
    });
    return noErr;
}

@interface GSRuleEngine ()
- (void)_timerFired:(NSTimer *)timer;
- (void)_evaluateEvent:(GSRuleEvent)event;
- (void)_fillContext:(GSRulesContext *)context event:(GSRuleEvent)event;
- (BOOL)_externalDisplayConnected;
- (int)_batteryPercentKnown:(BOOL *)known;
- (void)_appendHistoryWithAction:(GSPowerAction)action reason:(GSRuleReason)reason mode:(int)mode detail:(NSString *)detail;
- (NSArray *)_historyEntries;
- (NSString *)_supportDirectory;
- (void)_armHistorySuppression;
- (BOOL)_historySuppressed;
- (void)_checkDiscreteAlert;
- (BOOL)_expirePauseIfNeeded;
- (BOOL)_timerShouldReevaluate;
- (BOOL)_hasNonPowerAutomaticRule;
- (void)_loadProfileNamed:(NSString *)name;
- (NSArray<NSString *> *)_namesFromTasks:(NSArray *)tasks;
- (NSString *)_modeName:(int)mode;
- (NSString *)_reasonName:(GSRuleReason)reason;
- (NSString *)_statusText;
- (void)_writeStatusFile;
@end

@implementation GSRuleEngine {
    BOOL _applying;
    BOOL _applyAgain;
    BOOL _didConsumeLaunch;
    BOOL _statusRequested;
    NSInteger _suppressPreferences;
    NSTimer *_timer;
    NSDate *_suppressHistoryUntil;
    NSDate *_discreteSince;
    BOOL _discreteAlertSent;
    NSString *_lastBlockedSignature;
    NSString *_perAppDetail;
    NSString *_scheduleDetail;
    NSString *_powerDetail;
    NSInteger _thresholdPercent;
    NSString *_profileNote;
}

+ (GSRuleEngine *)sharedEngine
{
    static GSRuleEngine *engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[GSRuleEngine alloc] init];
    });
    return engine;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    NSNotificationCenter *workspaceNotes = [NSWorkspace sharedWorkspace].notificationCenter;
    [workspaceNotes addObserver:self selector:@selector(_runningAppsChanged:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [workspaceNotes addObserver:self selector:@selector(_runningAppsChanged:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
    [workspaceNotes addObserver:self selector:@selector(_didWake:) name:NSWorkspaceDidWakeNotification object:nil];

    NSNotificationCenter *notes = [NSNotificationCenter defaultCenter];
    [notes addObserver:self selector:@selector(_screenParametersChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [notes addObserver:self selector:@selector(_clockChanged:) name:NSSystemClockDidChangeNotification object:nil];

    _timer = [NSTimer timerWithTimeInterval:30 target:self selector:@selector(_timerFired:) userInfo:nil repeats:YES];
    _timer.tolerance = 5;
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];

    [self reloadHotKeys];
    return self;
}

- (BOOL)isSuppressingPreferenceApplication
{
    return _suppressPreferences > 0;
}

- (BOOL)isPaused
{
    return [self pausedUntil] != nil;
}

- (NSDate *)pausedUntil
{
    NSTimeInterval until = [[GSPreferences sharedInstance] doubleForKey:GSPausedUntilKey];
    if (until <= [NSDate date].timeIntervalSince1970)
        return nil;
    return [NSDate dateWithTimeIntervalSince1970:until];
}

- (BOOL)shouldHandleLaunch
{
    if (![[GSPowerSourceController sharedController] isFeatureAvailable])
        return NO;
    GSPreferences *prefs = [GSPreferences sharedInstance];
    if ([prefs shouldUsePowerSourceBasedSwitching])
        return YES;
    if ([prefs boolForKey:GSPerAppRulesEnabledKey])
        return YES;
    if ([prefs boolForKey:GSDisplayRuleEnabledKey])
        return YES;
    if ([prefs boolForKey:GSBatteryThresholdEnabledKey])
        return YES;
    if ([prefs boolForKey:GSSchedulesEnabledKey])
        return YES;
    if ([prefs boolForKey:GSLaunchDefaultEnabledKey])
        return YES;
    return NO;
}

- (BOOL)anyAutomaticRuleEnabled
{
    if (![[GSPowerSourceController sharedController] isFeatureAvailable])
        return NO;
    if ([self shouldHandleLaunch])
        return YES;
    return [[GSPreferences sharedInstance] boolForKey:GSWakeRuleEnabledKey];
}

- (BOOL)_hasNonPowerAutomaticRule
{
    GSPreferences *prefs = [GSPreferences sharedInstance];
    return [prefs boolForKey:GSPerAppRulesEnabledKey]
        || [prefs boolForKey:GSDisplayRuleEnabledKey]
        || [prefs boolForKey:GSBatteryThresholdEnabledKey]
        || [prefs boolForKey:GSSchedulesEnabledKey];
}

- (BOOL)_timerShouldReevaluate
{
    return [self _hasNonPowerAutomaticRule];
}

- (void)consumeLaunchArguments:(NSArray<NSString *> *)arguments
{
    for (NSUInteger index = 0; index < arguments.count; index++) {
        NSString *argument = arguments[index];
        if ([argument isEqualToString:@"--pause"]) {
            [[GSPreferences sharedInstance] setDouble:[NSDate date].timeIntervalSince1970 + (60 * 60) forKey:GSPausedUntilKey];
        } else if ([argument isEqualToString:@"--resume"]) {
            [[GSPreferences sharedInstance] setDouble:0 forKey:GSPausedUntilKey];
            [[GSPowerSourceController sharedController] clearManualOverride];
        } else if ([argument isEqualToString:@"--profile"] && index + 1 < arguments.count) {
            NSString *name = arguments[++index];
            if (![name hasPrefix:@"--"])
                [self _loadProfileNamed:name];
        } else if ([argument isEqualToString:@"--status"]) {
            _statusRequested = YES;
        }
    }
}

- (BOOL)takeStatusRequest
{
    if (!_statusRequested)
        return NO;
    _statusRequested = NO;
    return YES;
}

- (void)_loadProfileNamed:(NSString *)name
{
    GSPreferences *prefs = [GSPreferences sharedInstance];
    NSDictionary *settings = [prefs settingsForProfileNamed:name];
    if (!settings) {
        GSLogError(@"No GPU profile named \"%@\".", name);
        return;
    }
    _suppressPreferences++;
    [prefs captureActiveProfile];
    [prefs setActiveProfileName:name];
    [prefs applyRuleSettings:settings];
    _suppressPreferences--;
    [prefs savePreferences];
    [[GSPowerSourceController sharedController] clearManualOverride];
    [prefs setDouble:0 forKey:GSPausedUntilKey];
    GSLogInfo(@"Loaded GPU profile \"%@\" for launch.", name);
}

#pragma mark - Evaluation

- (void)applyForEvent:(GSRuleEvent)event
{
    GSPowerSourceController *power = [GSPowerSourceController sharedController];
    if (!power.isMonitoring || !power.isFeatureAvailable) {
        _profileNote = nil;
        return;
    }

    if (event == GSRuleEventLaunch) {
        if (_didConsumeLaunch)
            event = GSRuleEventContinuous;
        _didConsumeLaunch = YES;
    }

    if (_applying) {
        _applyAgain = YES;
        return;
    }

    _applying = YES;
    [self _evaluateEvent:event];
    _applying = NO;

    if (_applyAgain) {
        _applyAgain = NO;
        [self applyForEvent:GSRuleEventContinuous];
    }
}

- (void)_evaluateEvent:(GSRuleEvent)event
{
    GSRulesContext context;
    memset(&context, 0, sizeof(context));
    [self _fillContext:&context event:event];

    NSArray *tasks = nil;
    GSRulesDecision decision = GSRulesDecide(&context);
    if (decision.action == GSPowerActionSwitchIntegrated) {
        tasks = [GSProcess getTaskList];
        if (tasks.count > 0) {
            context.hasDiscreteDependencies = 1;
            decision = GSRulesDecide(&context);
        }
    }

    if (decision.action != GSPowerActionBlockedByDependencies)
        _lastBlockedSignature = nil;

    if (decision.action == GSPowerActionNone) {
        _profileNote = nil;
        GSLogDebug(@"Rules left the GPU alone (reason %d).", (int)decision.reason);
        return;
    }

    NSString *detail = [self _detailForDecision:decision tasks:tasks];
    if (decision.action == GSPowerActionBlockedByDependencies) {
        NSString *signature = [NSString stringWithFormat:@"%d\n%@", (int)decision.reason, detail ?: @""];
        if (![signature isEqualToString:_lastBlockedSignature]) {
            _lastBlockedSignature = signature;
            GSLogInfo(@"Integrated Only blocked by dependencies (%@).", detail);
            [self _appendHistoryWithAction:decision.action reason:decision.reason mode:GSPowerSourceBasedSwitchingModeIntegrated detail:detail];
            [[GSNotifier sharedInstance] showRuleBlockedNotificationForRule:[self _reasonName:decision.reason]
                                                                  taskNames:[self _namesFromTasks:tasks]];
        }
        _profileNote = nil;
        return;
    }

    GSSwitcherMode mode = GSSwitcherModeDynamicSwitching;
    int policyMode = GSPowerSourceBasedSwitchingModeDynamic;
    if (decision.action == GSPowerActionSwitchIntegrated) {
        mode = GSSwitcherModeForceIntegrated;
        policyMode = GSPowerSourceBasedSwitchingModeIntegrated;
    } else if (decision.action == GSPowerActionSwitchDiscrete) {
        mode = GSSwitcherModeForceDiscrete;
        policyMode = GSPowerSourceBasedSwitchingModeDiscrete;
    }

    GSLogInfo(@"Applying rule %d, mux mode %d.", (int)decision.reason, (int)mode);
    BOOL switched = [[GSMux defaultMux] setMode:mode];
    _profileNote = nil;
    if (!switched) {
        GSLogError(@"Rule could not switch the GPU.");
        return;
    }

    [self _armHistorySuppression];
    [self _appendHistoryWithAction:decision.action reason:decision.reason mode:policyMode detail:detail];
    [self _checkDiscreteAlert];
    [self _writeStatusFile];
    [self notifyStateChanged];
}

- (NSString *)_detailForDecision:(GSRulesDecision)decision tasks:(NSArray *)tasks
{
    NSString *detail = @"";
    if (decision.reason == GSRuleReasonPerApp)
        detail = _perAppDetail ?: @"";
    else if (decision.reason == GSRuleReasonDisplay)
        detail = Str(@"ExternalDisplay");
    else if (decision.reason == GSRuleReasonBatteryThreshold)
        detail = [NSString stringWithFormat:@"%ld%%", (long)_thresholdPercent];
    else if (decision.reason == GSRuleReasonSchedule)
        detail = _scheduleDetail ?: @"";
    else if (decision.reason == GSRuleReasonPowerSource)
        detail = _powerDetail ?: @"";
    else if (decision.reason == GSRuleReasonLaunch)
        detail = Str(@"LaunchDefault");
    else if (decision.reason == GSRuleReasonWake)
        detail = Str(@"WakeRule");

    if (_profileNote.length) {
        if (detail.length)
            detail = [NSString stringWithFormat:@"%@, %@", detail, _profileNote];
        else
            detail = _profileNote;
    }
    if (decision.action == GSPowerActionBlockedByDependencies) {
        NSString *names = [[self _namesFromTasks:tasks] componentsJoinedByString:@", "];
        if (names.length && detail.length)
            detail = [NSString stringWithFormat:@"%@ — %@", detail, names];
        else if (names.length)
            detail = names;
    }
    return detail;
}

- (void)_fillContext:(GSRulesContext *)context event:(GSRuleEvent)event
{
    GSPreferences *prefs = [GSPreferences sharedInstance];
    GSPowerSourceController *power = [GSPowerSourceController sharedController];
    id<GSMuxProtocol> mux = [GSMux defaultMux];

    context->paused = self.paused ? 1 : 0;
    context->manualOverride = power.manualOverrideActive ? 1 : 0;
    context->currentlyDynamic = mux.isUsingDynamicSwitching ? 1 : 0;
    context->currentlyIntegrated = mux.isUsingIntegratedGPU ? 1 : 0;

    _perAppDetail = nil;
    _scheduleDetail = nil;
    _powerDetail = nil;

    if ([prefs boolForKey:GSPerAppRulesEnabledKey]) {
        context->perAppEnabled = 1;
        NSMutableSet *running = [NSMutableSet set];
        for (NSRunningApplication *app in [NSWorkspace sharedWorkspace].runningApplications) {
            if (app.bundleIdentifier.length)
                [running addObject:app.bundleIdentifier];
        }
        NSMutableArray *discreteNames = [NSMutableArray array];
        NSMutableArray *integratedNames = [NSMutableArray array];
        for (id entry in [prefs arrayForKey:GSPerAppRulesKey]) {
            if (![entry isKindOfClass:[NSDictionary class]])
                continue;
            NSString *bundleID = entry[@"bundleID"];
            if (![bundleID isKindOfClass:[NSString class]] || ![running containsObject:bundleID])
                continue;
            NSString *appName = entry[@"name"];
            if (![appName isKindOfClass:[NSString class]] || appName.length == 0)
                appName = bundleID;
            int mode = [entry[@"mode"] intValue];
            if (mode == GSPowerSourceBasedSwitchingModeDiscrete) {
                context->perAppWantsDiscrete = 1;
                [discreteNames addObject:appName];
            } else if (mode == GSPowerSourceBasedSwitchingModeIntegrated) {
                context->perAppWantsIntegrated = 1;
                [integratedNames addObject:appName];
            }
        }
        _perAppDetail = [(context->perAppWantsDiscrete ? discreteNames : integratedNames) componentsJoinedByString:@", "];
    }

    if ([prefs boolForKey:GSDisplayRuleEnabledKey]) {
        context->displayRuleEnabled = 1;
        context->externalDisplayConnected = [self _externalDisplayConnected] ? 1 : 0;
    }

    if ([prefs boolForKey:GSBatteryThresholdEnabledKey]) {
        context->batteryThresholdEnabled = 1;
        _thresholdPercent = [prefs integerForKey:GSBatteryThresholdPercentKey fallback:20];
        context->batteryThresholdPercent = (int)_thresholdPercent;
        BOOL known = NO;
        int percent = [self _batteryPercentKnown:&known];
        context->batteryPercentKnown = known ? 1 : 0;
        context->batteryPercent = percent;
    }

    if ([prefs boolForKey:GSSchedulesEnabledKey]) {
        context->scheduleEnabled = 1;
        NSDateComponents *parts = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
        int minute = (int)parts.hour * 60 + (int)parts.minute;
        for (id entry in [prefs arrayForKey:GSSchedulesKey]) {
            if (![entry isKindOfClass:[NSDictionary class]])
                continue;
            int start = [entry[@"start"] intValue];
            int end = [entry[@"end"] intValue];
            int mode = [entry[@"mode"] intValue];
            if (mode < GSPowerSourceBasedSwitchingModeIntegrated || mode > GSPowerSourceBasedSwitchingModeDynamic)
                continue;
            if (!GSRulesMinuteInRange(minute, start, end))
                continue;
            context->scheduleHasMatch = 1;
            context->scheduleMode = mode;
            _scheduleDetail = [NSString stringWithFormat:@"%d:%02d-%d:%02d", start / 60, start % 60, end / 60, end % 60];
            break;
        }
    }

    if ([prefs shouldUsePowerSourceBasedSwitching]) {
        context->powerEnabled = 1;
        if (power.currentSource == GSPowerSourceBattery) {
            context->powerMode = [prefs modeForBattery];
            _powerDetail = Str(@"Battery");
        } else if (power.currentSource == GSPowerSourceACAdapter) {
            context->powerMode = [prefs modeForACAdapter];
            _powerDetail = Str(@"ACAdapter");
        } else {
            context->powerMode = GSPowerSourceBasedSwitchingModeDontChange;
            _powerDetail = Str(@"UnknownPowerSource");
        }
    }

    if (event == GSRuleEventLaunch && [prefs boolForKey:GSLaunchDefaultEnabledKey]) {
        context->oneShotEnabled = 1;
        context->oneShotMode = (int)[prefs integerForKey:GSLaunchDefaultModeKey fallback:GSPowerSourceBasedSwitchingModeDynamic];
        context->oneShotReason = GSRuleReasonLaunch;
    } else if (event == GSRuleEventWake && [prefs boolForKey:GSWakeRuleEnabledKey]) {
        context->oneShotEnabled = 1;
        context->oneShotMode = (int)[prefs integerForKey:GSWakeModeKey fallback:GSPowerSourceBasedSwitchingModeDynamic];
        context->oneShotReason = GSRuleReasonWake;
    }
}

- (BOOL)_externalDisplayConnected
{
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || count == 0)
        return NO;

    CGDirectDisplayID *displays = calloc(count, sizeof(CGDirectDisplayID));
    if (!displays)
        return NO;

    uint32_t actual = 0;
    BOOL connected = NO;
    if (CGGetOnlineDisplayList(count, displays, &actual) == kCGErrorSuccess) {
        for (uint32_t index = 0; index < actual; index++) {
            if (CGDisplayIsBuiltin(displays[index]))
                continue;
            if (!CGDisplayIsActive(displays[index]))
                continue;
            connected = YES;
            break;
        }
    }
    free(displays);
    return connected;
}

- (int)_batteryPercentKnown:(BOOL *)known
{
    if (known)
        *known = NO;

    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info)
        return -1;

    CFArrayRef list = IOPSCopyPowerSourcesList(info);
    int percent = -1;
    if (list) {
        CFIndex count = CFArrayGetCount(list);
        for (CFIndex index = 0; index < count; index++) {
            CFDictionaryRef description = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, index));
            if (!description)
                continue;
            CFTypeRef present = CFDictionaryGetValue(description, CFSTR(kIOPSIsPresentKey));
            if (present && CFGetTypeID(present) == CFBooleanGetTypeID() && !CFBooleanGetValue((CFBooleanRef)present))
                continue;

            CFNumberRef current = CFDictionaryGetValue(description, CFSTR(kIOPSCurrentCapacityKey));
            CFNumberRef maximum = CFDictionaryGetValue(description, CFSTR(kIOPSMaxCapacityKey));
            int currentValue = 0;
            int maximumValue = 0;
            if (!current || !maximum)
                continue;
            if (!CFNumberGetValue(current, kCFNumberIntType, &currentValue))
                continue;
            if (!CFNumberGetValue(maximum, kCFNumberIntType, &maximumValue) || maximumValue <= 0)
                continue;
            percent = (currentValue * 100) / maximumValue;
            if (known)
                *known = YES;
            break;
        }
        CFRelease(list);
    }
    CFRelease(info);
    return percent;
}

- (NSArray<NSString *> *)_namesFromTasks:(NSArray *)tasks
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *dict in tasks) {
        NSString *name = dict[kTaskItemName];
        if (name.length)
            [names addObject:name];
    }
    return names;
}

#pragma mark - User commands

- (BOOL)userRequestedMode:(GSSwitcherMode)mode source:(NSString *)source
{
    if (![[GSPowerSourceController sharedController] isFeatureAvailable]) {
        [[GSNotifier sharedInstance] showCommandUnavailableNotification];
        [self _writeStatusFile];
        return NO;
    }

    if (mode == GSSwitcherModeForceIntegrated) {
        NSArray *tasks = [GSProcess getTaskList];
        if (tasks.count > 0) {
            NSString *detail = [[self _namesFromTasks:tasks] componentsJoinedByString:@", "];
            [self _appendHistoryWithAction:GSPowerActionBlockedByDependencies
                                    reason:GSRuleReasonManual
                                      mode:GSPowerSourceBasedSwitchingModeIntegrated
                                    detail:source.length ? [NSString stringWithFormat:@"%@ — %@", source, detail] : detail];
            [[GSNotifier sharedInstance] showRuleBlockedNotificationForRule:source taskNames:[self _namesFromTasks:tasks]];
            return NO;
        }
    }

    BOOL switched = [[GSMux defaultMux] setMode:mode];
    if (!switched) {
        GSLogError(@"Requested GPU mode %d was not applied.", (int)mode);
        return NO;
    }
    [self noteUserDidSwitchToMode:mode source:source];
    return YES;
}

- (void)noteUserDidSwitchToMode:(GSSwitcherMode)mode source:(NSString *)source
{
    [self _armHistorySuppression];
    [[GSPowerSourceController sharedController] noteManualModeChange];

    int policyMode = -1;
    if (mode == GSSwitcherModeForceIntegrated)
        policyMode = GSPowerSourceBasedSwitchingModeIntegrated;
    else if (mode == GSSwitcherModeForceDiscrete)
        policyMode = GSPowerSourceBasedSwitchingModeDiscrete;
    else if (mode == GSSwitcherModeDynamicSwitching)
        policyMode = GSPowerSourceBasedSwitchingModeDynamic;

    [self _appendHistoryWithAction:GSPowerActionNone reason:GSRuleReasonManual mode:policyMode detail:source ?: @""];
    [self _checkDiscreteAlert];
    [self _writeStatusFile];
    [self notifyStateChanged];
}

- (void)noteGPUChangedTo:(GSGPUType)gpu
{
    [self _checkDiscreteAlert];
    if ([self _historySuppressed])
        return;

    NSString *name = (gpu == GSGPUTypeIntegrated) ? [GSGPU integratedGPUName] : [GSGPU discreteGPUName];
    [self _appendHistoryWithAction:GSPowerActionNone reason:GSRuleReasonExternal mode:-1 detail:name ?: @""];
    [self _writeStatusFile];
}

- (void)pauseForOneHour
{
    NSTimeInterval until = [NSDate date].timeIntervalSince1970 + (60 * 60);
    [[GSPreferences sharedInstance] setDouble:until forKey:GSPausedUntilKey];
    GSLogInfo(@"Automatic rules paused until %@.", [self pausedUntil]);
    [self _writeStatusFile];
    [self notifyStateChanged];
}

- (void)resumeAutomaticRules
{
    [[GSPreferences sharedInstance] setDouble:0 forKey:GSPausedUntilKey];
    [[GSPowerSourceController sharedController] clearManualOverride];
    GSLogInfo(@"Automatic rules resumed.");
    [self applyForEvent:GSRuleEventContinuous];
    [self _writeStatusFile];
    [self notifyStateChanged];
}

- (BOOL)activateProfileNamed:(NSString *)name
{
    GSPreferences *prefs = [GSPreferences sharedInstance];
    if (![prefs settingsForProfileNamed:name]) {
        GSLogError(@"No GPU profile named \"%@\".", name);
        return NO;
    }

    _profileNote = [prefs displayNameForProfile:name];
    _suppressPreferences++;
    [prefs captureActiveProfile];
    [prefs setActiveProfileName:name];
    [prefs applyRuleSettings:[prefs settingsForProfileNamed:name]];
    _suppressPreferences--;
    [prefs savePreferences];
    [[GSPowerSourceController sharedController] clearManualOverride];
    [prefs setDouble:0 forKey:GSPausedUntilKey];
    GSLogInfo(@"Activated GPU profile \"%@\".", name);
    [self applyForEvent:GSRuleEventContinuous];
    [self _writeStatusFile];
    [self notifyStateChanged];
    return YES;
}

- (void)handleURLs:(NSArray<NSURL *> *)urls
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleURLs:urls];
        });
        return;
    }

    for (NSURL *url in urls) {
        if (![url.scheme.lowercaseString isEqualToString:@"gfxcardstatus"])
            continue;

        NSString *command = url.host.lowercaseString ?: @"";
        if ([command isEqualToString:@"integrated"])
            [self userRequestedMode:GSSwitcherModeForceIntegrated source:Str(@"URLCommand")];
        else if ([command isEqualToString:@"discrete"])
            [self userRequestedMode:GSSwitcherModeForceDiscrete source:Str(@"URLCommand")];
        else if ([command isEqualToString:@"dynamic"])
            [self userRequestedMode:GSSwitcherModeDynamicSwitching source:Str(@"URLCommand")];
        else if ([command isEqualToString:@"pause"])
            [self pauseForOneHour];
        else if ([command isEqualToString:@"resume"])
            [self resumeAutomaticRules];
        else if ([command isEqualToString:@"status"])
            [self publishStatusNotifying:YES];
        else if ([command isEqualToString:@"profile"]) {
            NSString *name = url.path ?: @"";
            if ([name hasPrefix:@"/"])
                name = [name substringFromIndex:1];
            name = [name stringByRemovingPercentEncoding] ?: name;
            if (name.length == 0 || ![self activateProfileNamed:name])
                GSLogError(@"URL did not match a profile: %@", url);
        } else {
            GSLogError(@"Unknown gfxcardstatus URL: %@", url);
        }
    }
}

- (void)notifyStateChanged
{
    [self _checkDiscreteAlert];
    [[NSNotificationCenter defaultCenter] postNotificationName:GSRuleEngineStateDidChangeNotification object:self];
}

#pragma mark - Hotkeys

- (void)reloadHotKeys
{
    [self _installHotKeyHandler];
    for (int index = 0; index < 3; index++) {
        if (!sHotKeyRefs[index])
            continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UnregisterEventHotKey(sHotKeyRefs[index]);
#pragma clang diagnostic pop
        sHotKeyRefs[index] = NULL;
    }

    GSPreferences *prefs = [GSPreferences sharedInstance];
    NSArray *codeKeys = @[ GSHotkeyIntegratedKeyCodeKey, GSHotkeyDiscreteKeyCodeKey, GSHotkeyDynamicKeyCodeKey ];
    NSArray *modifierKeys = @[ GSHotkeyIntegratedModifiersKey, GSHotkeyDiscreteModifiersKey, GSHotkeyDynamicModifiersKey ];
    for (NSUInteger index = 0; index < codeKeys.count; index++) {
        NSInteger keyCode = [prefs integerForKey:codeKeys[index] fallback:-1];
        if (keyCode < 0 || keyCode > 127)
            continue;
        NSEventModifierFlags flags = (NSEventModifierFlags)[prefs integerForKey:modifierKeys[index] fallback:0];
        EventHotKeyID hotKeyID;
        hotKeyID.signature = (OSType)0x67667843; // 'gfxC'
        hotKeyID.id = (UInt32)(index + 1);
        EventHotKeyRef ref = NULL;
        OSStatus err;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        err = RegisterEventHotKey((UInt32)keyCode, GSCarbonModifiers(flags), hotKeyID, GetApplicationEventTarget(), 0, &ref);
#pragma clang diagnostic pop
        if (err != noErr) {
            GSLogError(@"Could not register GPU hotkey %lu (OSStatus %d).", (unsigned long)index, (int)err);
            continue;
        }
        sHotKeyRefs[index] = ref;
    }
}

- (void)_installHotKeyHandler
{
    if (sHotKeyHandlerInstalled)
        return;
    EventTypeSpec spec = { kEventClassKeyboard, kEventHotKeyPressed };
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus err = InstallApplicationEventHandler(GSHotKeyHandler, 1, &spec, NULL, NULL);
#pragma clang diagnostic pop
    if (err != noErr) {
        GSLogError(@"Could not install the hotkey handler (OSStatus %d).", (int)err);
        return;
    }
    sHotKeyHandlerInstalled = YES;
}

#pragma mark - Notifications from the system

- (void)_timerFired:(NSTimer *)timer
{
    (void)timer;
    if (![[GSPowerSourceController sharedController] isMonitoring])
        return;

    BOOL expired = [self _expirePauseIfNeeded];
    if (expired) {
        [self applyForEvent:GSRuleEventContinuous];
        [self notifyStateChanged];
    } else if (!self.paused
               && ![[GSPowerSourceController sharedController] isManualOverrideActive]
               && [self _timerShouldReevaluate]) {
        [self applyForEvent:GSRuleEventContinuous];
    }
    [self _checkDiscreteAlert];
}

- (BOOL)_expirePauseIfNeeded
{
    NSTimeInterval until = [[GSPreferences sharedInstance] doubleForKey:GSPausedUntilKey];
    if (until <= 0 || until > [NSDate date].timeIntervalSince1970)
        return NO;
    [[GSPreferences sharedInstance] setDouble:0 forKey:GSPausedUntilKey];
    GSLogInfo(@"Automatic-rule pause expired.");
    return YES;
}

- (void)_runningAppsChanged:(NSNotification *)notification
{
    (void)notification;
    if (![[GSPreferences sharedInstance] boolForKey:GSPerAppRulesEnabledKey])
        return;
    [self applyForEvent:GSRuleEventContinuous];
}

- (void)_screenParametersChanged:(NSNotification *)notification
{
    (void)notification;
    // Power-source-only machines keep the old contract: a blocked Integrated
    // Only attempt is not retried until the power source changes.
    if (![self _hasNonPowerAutomaticRule])
        return;
    [self applyForEvent:GSRuleEventContinuous];
}

- (void)_clockChanged:(NSNotification *)notification
{
    (void)notification;
    if (![[GSPreferences sharedInstance] boolForKey:GSSchedulesEnabledKey])
        return;
    [self applyForEvent:GSRuleEventContinuous];
}

- (void)_didWake:(NSNotification *)notification
{
    (void)notification;
    BOOL wakeRule = [[GSPreferences sharedInstance] boolForKey:GSWakeRuleEnabledKey];
    if (!wakeRule && ![self _hasNonPowerAutomaticRule])
        return;
    [self applyForEvent:wakeRule ? GSRuleEventWake : GSRuleEventContinuous];
}

- (void)_checkDiscreteAlert
{
    GSPreferences *prefs = [GSPreferences sharedInstance];
    if (![prefs boolForKey:GSDiscreteOnBatteryAlertEnabledKey]
        || ![[GSPowerSourceController sharedController] isFeatureAvailable]) {
        _discreteSince = nil;
        _discreteAlertSent = NO;
        return;
    }

    id<GSMuxProtocol> mux = [GSMux defaultMux];
    BOOL discreteOn = mux.isOpen && !mux.isUsingIntegratedGPU;
    BOOL onBattery = [GSPowerSourceController sharedController].currentSource == GSPowerSourceBattery;
    if (!discreteOn || !onBattery) {
        _discreteSince = nil;
        _discreteAlertSent = NO;
        return;
    }

    if (!_discreteSince)
        _discreteSince = [NSDate date];
    if (_discreteAlertSent)
        return;

    NSInteger minutes = [prefs integerForKey:GSDiscreteOnBatteryAlertMinutesKey fallback:30];
    if (minutes < 1)
        minutes = 30;
    if (-[_discreteSince timeIntervalSinceNow] < minutes * 60.0)
        return;

    _discreteAlertSent = YES;
    [[GSNotifier sharedInstance] showDiscreteOnBatteryAlertForMinutes:minutes];
}

#pragma mark - History and status

- (void)_armHistorySuppression
{
    _suppressHistoryUntil = [NSDate dateWithTimeIntervalSinceNow:kHistorySuppressionInterval];
}

- (BOOL)_historySuppressed
{
    return _suppressHistoryUntil && [_suppressHistoryUntil timeIntervalSinceNow] > 0;
}

- (NSString *)_supportDirectory
{
    NSString *path = [@"~/Library/Application Support/gfxCardStatus" stringByExpandingTildeInPath];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
        GSLogError(@"Could not create Application Support directory: %@", error);
        return nil;
    }
    return path;
}

- (NSArray *)_historyEntries
{
    NSString *directory = [self _supportDirectory];
    if (!directory)
        return @[];
    NSString *path = [directory stringByAppendingPathComponent:@"history.plist"];
    id entries = [NSArray arrayWithContentsOfURL:[NSURL fileURLWithPath:path] error:NULL];
    if (![entries isKindOfClass:[NSArray class]])
        return @[];
    return entries;
}

- (void)_appendHistoryWithAction:(GSPowerAction)action reason:(GSRuleReason)reason mode:(int)mode detail:(NSString *)detail
{
    if (![[GSPreferences sharedInstance] boolForKey:GSHistoryEnabledKey])
        return;

    NSString *directory = [self _supportDirectory];
    if (!directory)
        return;

    NSDictionary *entry = @{
        @"date": [NSDate date],
        @"action": @(action),
        @"reason": @(reason),
        @"mode": @(mode),
        @"detail": detail ?: @""
    };
    NSMutableArray *entries = [[self _historyEntries] mutableCopy];
    [entries insertObject:entry atIndex:0];
    if (entries.count > kHistoryLimit)
        [entries removeObjectsInRange:NSMakeRange(kHistoryLimit, entries.count - kHistoryLimit)];

    NSError *error = nil;
    NSString *path = [directory stringByAppendingPathComponent:@"history.plist"];
    if (![entries writeToURL:[NSURL fileURLWithPath:path] error:&error])
        GSLogError(@"Could not write GPU history: %@", error);
}

- (NSArray<NSString *> *)historyMenuLines
{
    NSArray *entries = [self _historyEntries];
    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger limit = MIN(entries.count, kHistoryMenuLimit);
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;

    for (NSUInteger index = 0; index < limit; index++) {
        NSDictionary *entry = entries[index];
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        NSDate *date = entry[@"date"];
        NSString *when = [date isKindOfClass:[NSDate class]] ? [formatter stringFromDate:date] : @"";
        GSPowerAction action = (GSPowerAction)[entry[@"action"] intValue];
        GSRuleReason reason = (GSRuleReason)[entry[@"reason"] intValue];
        int mode = [entry[@"mode"] intValue];
        NSString *detail = entry[@"detail"];
        if (![detail isKindOfClass:[NSString class]])
            detail = @"";

        NSString *line = nil;
        if (reason == GSRuleReasonExternal)
            line = [NSString stringWithFormat:Str(@"HistoryExternalLine"), when, detail];
        else if (action == GSPowerActionBlockedByDependencies)
            line = [NSString stringWithFormat:Str(@"HistoryBlockedLine"), when, [self _reasonName:reason], detail];
        else
            line = [NSString stringWithFormat:Str(@"HistorySwitchLine"), when, [self _modeName:mode], detail.length ? detail : [self _reasonName:reason]];
        if (line.length)
            [lines addObject:line];
    }
    return lines;
}

- (NSString *)_modeName:(int)mode
{
    if (mode == GSPowerSourceBasedSwitchingModeIntegrated)
        return Str(@"IntegratedOnly");
    if (mode == GSPowerSourceBasedSwitchingModeDiscrete)
        return Str(@"DiscreteOnly");
    if (mode == GSPowerSourceBasedSwitchingModeDynamic)
        return Str(@"DynamicSwitching");
    return Str(@"GPUChanged");
}

- (NSString *)_reasonName:(GSRuleReason)reason
{
    switch (reason) {
        case GSRuleReasonManual: return Str(@"HistoryManual");
        case GSRuleReasonPerApp: return Str(@"PerAppRule");
        case GSRuleReasonDisplay: return Str(@"ExternalDisplay");
        case GSRuleReasonBatteryThreshold: return Str(@"BatteryThreshold");
        case GSRuleReasonSchedule: return Str(@"Schedules");
        case GSRuleReasonPowerSource: return Str(@"PowerSourceRule");
        case GSRuleReasonWake: return Str(@"WakeRule");
        case GSRuleReasonLaunch: return Str(@"LaunchDefault");
        case GSRuleReasonExternal: return Str(@"HistoryExternal");
        case GSRuleReasonNone: break;
    }
    return @"";
}

- (NSString *)_statusText
{
    id<GSMuxProtocol> mux = [GSMux defaultMux];
    NSString *gpu = @"unavailable";
    NSString *mode = @"unavailable";
    if (mux.isOpen) {
        BOOL integrated = mux.isUsingIntegratedGPU;
        NSString *name = integrated ? [GSGPU integratedGPUName] : [GSGPU discreteGPUName];
        gpu = name.length ? name : @"unknown";
        if (mux.isUsingDynamicSwitching)
            mode = @"dynamic";
        else if (integrated)
            mode = @"integrated";
        else
            mode = @"discrete";
    }

    GSPowerSource source = [GSPowerSourceController sharedController].currentSource;
    NSString *power = @"unknown";
    if (source == GSPowerSourceBattery)
        power = @"battery";
    else if (source == GSPowerSourceACAdapter)
        power = @"ac";

    NSString *paused = self.paused ? [self.pausedUntil description] : @"no";
    NSString *profile = [[GSPreferences sharedInstance] activeProfileName];
    if (profile.length == 0)
        profile = @"none";
    BOOL manual = [GSPowerSourceController sharedController].manualOverrideActive;
    return [NSString stringWithFormat:@"gpu: %@\nmode: %@\nprofile: %@\npaused: %@\nmanual: %@\npower: %@\n",
            gpu, mode, profile, paused, manual ? @"yes" : @"no", power];
}

- (void)_writeStatusFile
{
    NSString *directory = [self _supportDirectory];
    if (!directory)
        return;
    NSString *path = [directory stringByAppendingPathComponent:@"status.txt"];
    NSError *error = nil;
    if (![[self _statusText] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error])
        GSLogError(@"Could not write GPU status file: %@", error);
}

- (void)publishStatusNotifying:(BOOL)notify
{
    [self _writeStatusFile];
    if (notify)
        [[GSNotifier sharedInstance] showStatusNotification:[self _statusText]];
}

@end
