//
//  GSPreferences.m
//  gfxCardStatus
//
//  Created by Cody Krieger on 9/26/10.
//  Copyright 2010 Cody Krieger. All rights reserved.
//

#import "GSPreferences.h"
#import "GSStartup.h"
#import "GSGPU.h"

// Unfortunately this value needs to stay misspelled unless there is a desire to
// migrate it to a correctly spelled version instead, since getting and setting
// the existing preferences depend on it.
NSString * const GSPowerSourceBasedSwitchingACModeKey = @"GPUSetting_ACAdaptor";
NSString * const GSPowerSourceBasedSwitchingBatteryModeKey = @"GPUSetting_Battery";
NSString * const GSShouldUsePowerSourceBasedSwitchingKey = @"shouldUsePowerSourceBasedSwitching";

// Written once so an old "feature was on" value cannot start switching GPUs
// again after the feature comes back. The feature stays off until this copy
// of the app saves an explicit choice.
static NSString * const kPowerSourceSwitchingInitializedKey = @"powerSourceBasedSwitchingInitialized";

#define kShouldStartAtLoginKey                  @"shouldStartAtLogin"
#define kShouldCheckForUpdatesOnStartupKey      @"shouldCheckForUpdatesOnStartup"
#define kShouldUseSmartMenuBarIconsKey          @"shouldUseSmartMenuBarIcons"

// This used to be called "shouldGrowl"
#define kShouldDisplayNotificationsKey          @"shouldGrowl"

// Why aren't we just using NSUserDefaults? Because it was unbelievably
// unreliable. This works all the time, no questions asked.
#define kPreferencesPlistPath [@"~/Library/Preferences/com.codykrieger.gfxCardStatus-Preferences.plist" stringByExpandingTildeInPath]

// NSMutableDictionary is not KVO-compliant for its keys, which is what the
// preference checkboxes and the old ReactiveCocoa observers depended on.
// This object stores the same plist dictionary and notifies on every key.
@interface GSPreferencesDictionary : NSObject
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (id)objectForKeyedSubscript:(NSString *)key;
- (void)setObject:(id)object forKeyedSubscript:(NSString *)key;
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;
@end

@implementation GSPreferencesDictionary {
    NSMutableDictionary *_storage;
}

- (instancetype)init {
    return [self initWithDictionary:@{}];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self)
        _storage = dictionary ? [dictionary mutableCopy] : [NSMutableDictionary dictionary];
    return self;
}

- (id)objectForKey:(NSString *)key {
    if (key == nil)
        return nil;
    return _storage[key];
}

- (void)setObject:(id)object forKey:(NSString *)key {
    if (key == nil)
        return;

    [self willChangeValueForKey:key];
    if (object)
        _storage[key] = object;
    else
        [_storage removeObjectForKey:key];
    [self didChangeValueForKey:key];
}

- (id)objectForKeyedSubscript:(NSString *)key {
    return [self objectForKey:key];
}

- (void)setObject:(id)object forKeyedSubscript:(NSString *)key {
    [self setObject:object forKey:key];
}

- (id)valueForUndefinedKey:(NSString *)key {
    return [self objectForKey:key];
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    [self setObject:value forKey:key];
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error {
    return [_storage writeToURL:url error:error];
}

@end

@interface GSPreferences (Internal)
- (NSURL *)_prefsURL;
- (BOOL)_ensurePowerSourcePreferences;
- (BOOL)_normalizeModeForKey:(NSString *)key fallback:(GSPowerSourceBasedSwitchingMode)fallback;
- (GSPowerSourceBasedSwitchingMode)_modeForKey:(NSString *)key
                                      fallback:(GSPowerSourceBasedSwitchingMode)fallback;
@end

@implementation GSPreferences

#pragma mark - Initializers

- (id)init
{
    if (!(self = [super init]))
        return nil;
    
    GSLogDebug(@"Initializing GSPreferences...");
    [self setUpPreferences];
    
    return self;
}

+ (GSPreferences *)sharedInstance
{
    static dispatch_once_t pred = 0;
    __strong static GSPreferences *_sharedObject = nil;
    dispatch_once(&pred, ^{
        _sharedObject = [[self alloc] init];
    });
    return _sharedObject;
}

#pragma mark - GSPreferences API

- (void)setUpPreferences
{
    GSLogDebug(@"Loading preferences and defaults...");
    
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:[self _prefsURL] error:NULL];
    if (!saved) {
        // If preferences file doesn't exist, set the defaults.
        _prefsDict = [[GSPreferencesDictionary alloc] init];
        [self setDefaults];
    } else {
        _prefsDict = [[GSPreferencesDictionary alloc] initWithDictionary:saved];

        // Login Items remain the source of truth, including a one-time migration
        // onto SMAppService for people who opted in with the old API.
        NSNumber *savedLogin = _prefsDict[kShouldStartAtLoginKey];
        if ([GSStartup existsInStartupItems])
            _prefsDict[kShouldStartAtLoginKey] = @YES;
        else if ([savedLogin boolValue])
            [GSStartup loadAtStartup:YES];
        else
            _prefsDict[kShouldStartAtLoginKey] = @NO;

        if ([self _ensurePowerSourcePreferences])
            [self savePreferences];
    }
    
    // Ensure that application will be loaded at startup.
    if ([self shouldStartAtLogin])
        [GSStartup loadAtStartup:YES];
    
    // Since we removed this preference from v2.2 prematurely, some new users
    // might not have had it set in their defaults. If the key doesn't exist in
    // the prefs dictionary, default this sucker to enabled, because
    // notifications are helpful.
    if (_prefsDict[kShouldDisplayNotificationsKey] == nil)
        _prefsDict[kShouldDisplayNotificationsKey] = @YES;
}

- (void)setDefaults
{
    GSLogDebug(@"Setting initial defaults...");
    
    _prefsDict[kShouldCheckForUpdatesOnStartupKey] = @YES;
    _prefsDict[kShouldStartAtLoginKey] = @YES;
    _prefsDict[kShouldDisplayNotificationsKey] = @YES;
    _prefsDict[kShouldUseSmartMenuBarIconsKey] = @NO;

    // Off until the user opts in, including on a brand new preferences file.
    _prefsDict[GSShouldUsePowerSourceBasedSwitchingKey] = @NO;
    _prefsDict[kPowerSourceSwitchingInitializedKey] = @YES;
    _prefsDict[GSPowerSourceBasedSwitchingBatteryModeKey] = @(GSPowerSourceBasedSwitchingModeIntegrated);
    if ([GSGPU isLegacyMachine])
        _prefsDict[GSPowerSourceBasedSwitchingACModeKey] = @(GSPowerSourceBasedSwitchingModeDiscrete);
    else
        _prefsDict[GSPowerSourceBasedSwitchingACModeKey] = @(GSPowerSourceBasedSwitchingModeDynamic);
    
    [self savePreferences];
}

- (void)savePreferences
{
    GSLogDebug(@"Writing preferences to disk...");

    NSError *error = nil;
    if ([_prefsDict writeToURL:[self _prefsURL] error:&error])
        GSLogDebug(@"Successfully wrote preferences to disk.");
    else
        GSLogDebug(@"Failed to write preferences to disk. Permissions problem in ~/Library/Preferences? %@", error);
}

- (void)setBool:(BOOL)value forKey:(NSString *)key
{
    _prefsDict[key] = @(value);
    [self savePreferences];
}

- (BOOL)boolForKey:(NSString *)key
{
    return [_prefsDict[key] boolValue];
}

- (BOOL)shouldCheckForUpdatesOnStartup
{
    return [_prefsDict[kShouldCheckForUpdatesOnStartupKey] boolValue];
}

- (BOOL)shouldStartAtLogin
{
    return [_prefsDict[kShouldStartAtLoginKey] boolValue];
}

- (BOOL)shouldDisplayNotifications
{
    return [_prefsDict[kShouldDisplayNotificationsKey] boolValue];
}

- (BOOL)shouldUsePowerSourceBasedSwitching
{
    return [_prefsDict[GSShouldUsePowerSourceBasedSwitchingKey] boolValue];
}

- (BOOL)shouldUseSmartMenuBarIcons
{
    return [_prefsDict[kShouldUseSmartMenuBarIconsKey] boolValue];
}

- (GSPowerSourceBasedSwitchingMode)modeForACAdapter
{
    GSPowerSourceBasedSwitchingMode fallback = [GSGPU isLegacyMachine]
        ? GSPowerSourceBasedSwitchingModeDiscrete
        : GSPowerSourceBasedSwitchingModeDynamic;
    return [self _modeForKey:GSPowerSourceBasedSwitchingACModeKey fallback:fallback];
}

- (GSPowerSourceBasedSwitchingMode)modeForBattery
{
    return [self _modeForKey:GSPowerSourceBasedSwitchingBatteryModeKey
                    fallback:GSPowerSourceBasedSwitchingModeIntegrated];
}

- (void)setPowerSourceBasedSwitchingMode:(GSPowerSourceBasedSwitchingMode)mode
                           forPowerSource:(GSPowerSource)source
{
    if (mode < GSPowerSourceBasedSwitchingModeIntegrated || mode > GSPowerSourceBasedSwitchingModeDontChange)
        return;

    NSString *key = nil;
    if (source == GSPowerSourceBattery)
        key = GSPowerSourceBasedSwitchingBatteryModeKey;
    else if (source == GSPowerSourceACAdapter)
        key = GSPowerSourceBasedSwitchingACModeKey;
    else
        return;

    _prefsDict[key] = @(mode);
    [self savePreferences];
}

#pragma mark - NSWindowDelegate protocol

- (void)windowWillClose:(NSNotification *)notification
{
    [self savePreferences];
}

@end

#pragma mark - Private helpers

@implementation GSPreferences (Internal)

- (NSURL *)_prefsURL
{
    return [NSURL fileURLWithPath:kPreferencesPlistPath];
}

// Fills in anything an older preferences file does not have. A stored YES
// from before the feature was removed is forced back to NO once, so upgrading
// does not start switching GPUs on its own.
- (BOOL)_ensurePowerSourcePreferences
{
    BOOL dirty = NO;

    if (![_prefsDict[kPowerSourceSwitchingInitializedKey] boolValue]) {
        _prefsDict[GSShouldUsePowerSourceBasedSwitchingKey] = @NO;
        _prefsDict[kPowerSourceSwitchingInitializedKey] = @YES;
        dirty = YES;
    } else if (_prefsDict[GSShouldUsePowerSourceBasedSwitchingKey] == nil) {
        _prefsDict[GSShouldUsePowerSourceBasedSwitchingKey] = @NO;
        dirty = YES;
    }

    if ([self _normalizeModeForKey:GSPowerSourceBasedSwitchingBatteryModeKey
                          fallback:GSPowerSourceBasedSwitchingModeIntegrated])
        dirty = YES;

    GSPowerSourceBasedSwitchingMode acFallback = [GSGPU isLegacyMachine]
        ? GSPowerSourceBasedSwitchingModeDiscrete
        : GSPowerSourceBasedSwitchingModeDynamic;
    if ([self _normalizeModeForKey:GSPowerSourceBasedSwitchingACModeKey fallback:acFallback])
        dirty = YES;

    return dirty;
}

- (BOOL)_normalizeModeForKey:(NSString *)key fallback:(GSPowerSourceBasedSwitchingMode)fallback
{
    id value = _prefsDict[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        int mode = [value intValue];
        if (mode >= GSPowerSourceBasedSwitchingModeIntegrated && mode <= GSPowerSourceBasedSwitchingModeDontChange)
            return NO;
    }

    _prefsDict[key] = @(fallback);
    return YES;
}

- (GSPowerSourceBasedSwitchingMode)_modeForKey:(NSString *)key
                                      fallback:(GSPowerSourceBasedSwitchingMode)fallback
{
    id value = _prefsDict[key];
    if (![value isKindOfClass:[NSNumber class]])
        return fallback;

    int mode = [value intValue];
    if (mode < GSPowerSourceBasedSwitchingModeIntegrated || mode > GSPowerSourceBasedSwitchingModeDontChange)
        return fallback;
    return (GSPowerSourceBasedSwitchingMode)mode;
}

@end
