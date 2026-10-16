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

NSString * const GSPerAppRulesEnabledKey = @"perAppRulesEnabled";
NSString * const GSPerAppRulesKey = @"perAppRules";
NSString * const GSBatteryThresholdEnabledKey = @"batteryThresholdEnabled";
NSString * const GSBatteryThresholdPercentKey = @"batteryThresholdPercent";
NSString * const GSDisplayRuleEnabledKey = @"displayRuleEnabled";
NSString * const GSSchedulesEnabledKey = @"schedulesEnabled";
NSString * const GSSchedulesKey = @"schedules";
NSString * const GSLaunchDefaultEnabledKey = @"launchDefaultEnabled";
NSString * const GSLaunchDefaultModeKey = @"launchDefaultMode";
NSString * const GSWakeRuleEnabledKey = @"wakeRuleEnabled";
NSString * const GSWakeModeKey = @"wakeMode";
NSString * const GSNotificationListsGPUAppsKey = @"notificationListsGPUApps";
NSString * const GSMenuBarShowsGPUNameKey = @"menuBarShowsGPUName";
NSString * const GSHistoryEnabledKey = @"gpuHistoryEnabled";
NSString * const GSDiscreteOnBatteryAlertEnabledKey = @"discreteOnBatteryAlertEnabled";
NSString * const GSDiscreteOnBatteryAlertMinutesKey = @"discreteOnBatteryAlertMinutes";
NSString * const GSPausedUntilKey = @"rulesPausedUntil";
NSString * const GSProfilesKey = @"gpuProfiles";
NSString * const GSActiveProfileNameKey = @"activeGPUProfile";
NSString * const GSHotkeyIntegratedKeyCodeKey = @"hotkeyIntegratedKeyCode";
NSString * const GSHotkeyIntegratedModifiersKey = @"hotkeyIntegratedModifiers";
NSString * const GSHotkeyIntegratedLabelKey = @"hotkeyIntegratedLabel";
NSString * const GSHotkeyDiscreteKeyCodeKey = @"hotkeyDiscreteKeyCode";
NSString * const GSHotkeyDiscreteModifiersKey = @"hotkeyDiscreteModifiers";
NSString * const GSHotkeyDiscreteLabelKey = @"hotkeyDiscreteLabel";
NSString * const GSHotkeyDynamicKeyCodeKey = @"hotkeyDynamicKeyCode";
NSString * const GSHotkeyDynamicModifiersKey = @"hotkeyDynamicModifiers";
NSString * const GSHotkeyDynamicLabelKey = @"hotkeyDynamicLabel";

NSString * const GSProfileNameDefault = @"Default";
NSString * const GSProfileNameTravel = @"Travel";
NSString * const GSProfileNameDesk = @"Desk";

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
- (BOOL)_ensureRulePreferences;
- (BOOL)_normalizeModeForKey:(NSString *)key fallback:(GSPowerSourceBasedSwitchingMode)fallback;
- (GSPowerSourceBasedSwitchingMode)_modeForKey:(NSString *)key
                                      fallback:(GSPowerSourceBasedSwitchingMode)fallback;
- (NSArray *)_profileRuleKeys;
- (NSDictionary *)_defaultRuleSettings;
- (id)_defaultValueForRuleKey:(NSString *)key;
- (BOOL)_value:(id)value isValidForRuleKey:(NSString *)key;
- (NSDictionary *)_liveRuleSnapshot;
- (NSArray *)_profileEntries;
- (void)_installExampleProfiles;
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

        BOOL dirty = [self _ensurePowerSourcePreferences];
        if ([self _ensureRulePreferences])
            dirty = YES;
        if (dirty)
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

    [self _ensureRulePreferences];
    [self savePreferences];
}

- (void)savePreferences
{
    GSLogDebug(@"Writing preferences to disk...");

    // The active profile remembers the live rule keys, so leaving it and
    // coming back does not restore a stale copy.
    [self captureActiveProfile];

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

- (void)setInteger:(NSInteger)value forKey:(NSString *)key
{
    _prefsDict[key] = @(value);
    [self savePreferences];
}

- (NSInteger)integerForKey:(NSString *)key fallback:(NSInteger)fallback
{
    id value = _prefsDict[key];
    if (![value isKindOfClass:[NSNumber class]])
        return fallback;
    return [value integerValue];
}

- (void)setDouble:(double)value forKey:(NSString *)key
{
    _prefsDict[key] = @(value);
    [self savePreferences];
}

- (double)doubleForKey:(NSString *)key
{
    id value = _prefsDict[key];
    if (![value isKindOfClass:[NSNumber class]])
        return 0;
    return [value doubleValue];
}

- (void)setArray:(NSArray *)array forKey:(NSString *)key
{
    _prefsDict[key] = array ?: @[];
    [self savePreferences];
}

- (NSArray *)arrayForKey:(NSString *)key
{
    id value = _prefsDict[key];
    if (![value isKindOfClass:[NSArray class]])
        return @[];
    return value;
}

- (void)setString:(NSString *)value forKey:(NSString *)key
{
    _prefsDict[key] = value ?: @"";
    [self savePreferences];
}

- (NSString *)stringForKey:(NSString *)key
{
    id value = _prefsDict[key];
    if (![value isKindOfClass:[NSString class]])
        return @"";
    return value;
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

#pragma mark - Profiles

- (NSArray<NSString *> *)profileNames
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *entry in [self _profileEntries]) {
        NSString *name = entry[@"name"];
        if ([name isKindOfClass:[NSString class]] && name.length)
            [names addObject:name];
    }
    return names;
}

- (NSString *)activeProfileName
{
    id value = _prefsDict[GSActiveProfileNameKey];
    if (![value isKindOfClass:[NSString class]])
        return @"";
    return value;
}

- (NSString *)displayNameForProfile:(NSString *)name
{
    if ([name isEqualToString:GSProfileNameDefault])
        return Str(@"ProfileDefault");
    if ([name isEqualToString:GSProfileNameTravel])
        return Str(@"ProfileTravel");
    if ([name isEqualToString:GSProfileNameDesk])
        return Str(@"ProfileDesk");
    return name ?: @"";
}

- (NSDictionary *)settingsForProfileNamed:(NSString *)name
{
    if (name.length == 0)
        return nil;
    for (NSDictionary *entry in [self _profileEntries]) {
        if ([entry[@"name"] isEqualToString:name]) {
            id settings = entry[@"settings"];
            if ([settings isKindOfClass:[NSDictionary class]])
                return settings;
            return @{};
        }
    }
    return nil;
}

- (void)captureActiveProfile
{
    NSString *active = [self activeProfileName];
    if (active.length == 0)
        return;

    NSMutableArray *entries = [NSMutableArray array];
    BOOL found = NO;
    NSDictionary *snapshot = [self _liveRuleSnapshot];
    for (NSDictionary *entry in [self _profileEntries]) {
        if ([entry[@"name"] isEqualToString:active]) {
            [entries addObject:@{ @"name": active, @"settings": snapshot }];
            found = YES;
        } else {
            [entries addObject:entry];
        }
    }
    if (!found)
        return;
    _prefsDict[GSProfilesKey] = entries;
}

- (void)setActiveProfileName:(NSString *)name
{
    if (name.length == 0)
        return;
    _prefsDict[GSActiveProfileNameKey] = name;
}

- (void)applyRuleSettings:(NSDictionary *)settings
{
    for (NSString *key in [self _profileRuleKeys]) {
        id value = settings[key];
        if (![self _value:value isValidForRuleKey:key])
            value = [self _defaultValueForRuleKey:key];
        _prefsDict[key] = value;
    }
}

- (BOOL)saveNewProfileNamed:(NSString *)name
{
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || trimmed.length > 64)
        return NO;

    [self captureActiveProfile];
    NSDictionary *snapshot = [self _liveRuleSnapshot];
    NSMutableArray *entries = [NSMutableArray array];
    BOOL found = NO;
    for (NSDictionary *entry in [self _profileEntries]) {
        if ([entry[@"name"] isEqualToString:trimmed]) {
            [entries addObject:@{ @"name": trimmed, @"settings": snapshot }];
            found = YES;
        } else {
            [entries addObject:entry];
        }
    }
    if (!found)
        [entries addObject:@{ @"name": trimmed, @"settings": snapshot }];

    _prefsDict[GSProfilesKey] = entries;
    _prefsDict[GSActiveProfileNameKey] = trimmed;
    [self savePreferences];
    return YES;
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

- (NSArray *)_profileRuleKeys
{
    return @[
        GSShouldUsePowerSourceBasedSwitchingKey,
        GSPowerSourceBasedSwitchingBatteryModeKey,
        GSPowerSourceBasedSwitchingACModeKey,
        GSPerAppRulesEnabledKey,
        GSPerAppRulesKey,
        GSBatteryThresholdEnabledKey,
        GSBatteryThresholdPercentKey,
        GSDisplayRuleEnabledKey,
        GSSchedulesEnabledKey,
        GSSchedulesKey,
        GSLaunchDefaultEnabledKey,
        GSLaunchDefaultModeKey,
        GSWakeRuleEnabledKey,
        GSWakeModeKey,
        GSNotificationListsGPUAppsKey,
        GSDiscreteOnBatteryAlertEnabledKey,
        GSDiscreteOnBatteryAlertMinutesKey
    ];
}

- (NSDictionary *)_defaultRuleSettings
{
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *key in [self _profileRuleKeys])
        settings[key] = [self _defaultValueForRuleKey:key];
    return settings;
}

- (id)_defaultValueForRuleKey:(NSString *)key
{
    if ([key isEqualToString:GSPowerSourceBasedSwitchingBatteryModeKey])
        return @(GSPowerSourceBasedSwitchingModeIntegrated);
    if ([key isEqualToString:GSPowerSourceBasedSwitchingACModeKey]) {
        GSPowerSourceBasedSwitchingMode mode = [GSGPU isLegacyMachine]
            ? GSPowerSourceBasedSwitchingModeDiscrete
            : GSPowerSourceBasedSwitchingModeDynamic;
        return @(mode);
    }
    if ([key isEqualToString:GSLaunchDefaultModeKey] || [key isEqualToString:GSWakeModeKey])
        return @(GSPowerSourceBasedSwitchingModeDynamic);
    if ([key isEqualToString:GSBatteryThresholdPercentKey])
        return @20;
    if ([key isEqualToString:GSDiscreteOnBatteryAlertMinutesKey])
        return @30;
    if ([key isEqualToString:GSPerAppRulesKey] || [key isEqualToString:GSSchedulesKey])
        return @[];
    return @NO;
}

- (BOOL)_value:(id)value isValidForRuleKey:(NSString *)key
{
    if ([key isEqualToString:GSPerAppRulesKey] || [key isEqualToString:GSSchedulesKey])
        return [value isKindOfClass:[NSArray class]];

    if (![value isKindOfClass:[NSNumber class]])
        return NO;

    int number = [value intValue];
    if ([key isEqualToString:GSPowerSourceBasedSwitchingBatteryModeKey]
        || [key isEqualToString:GSPowerSourceBasedSwitchingACModeKey]
        || [key isEqualToString:GSLaunchDefaultModeKey]
        || [key isEqualToString:GSWakeModeKey])
        return number >= GSPowerSourceBasedSwitchingModeIntegrated
            && number <= GSPowerSourceBasedSwitchingModeDontChange;
    if ([key isEqualToString:GSBatteryThresholdPercentKey])
        return number >= 1 && number <= 99;
    if ([key isEqualToString:GSDiscreteOnBatteryAlertMinutesKey])
        return number >= 1 && number <= (24 * 60);
    return YES;
}

- (NSDictionary *)_liveRuleSnapshot
{
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in [self _profileRuleKeys]) {
        id value = _prefsDict[key];
        if (![self _value:value isValidForRuleKey:key])
            value = [self _defaultValueForRuleKey:key];
        snapshot[key] = value;
    }
    return snapshot;
}

- (NSArray *)_profileEntries
{
    id value = _prefsDict[GSProfilesKey];
    if (![value isKindOfClass:[NSArray class]])
        return @[];
    return value;
}

- (void)_installExampleProfiles
{
    NSDictionary *fallback = [self _defaultRuleSettings];
    NSMutableDictionary *travel = [fallback mutableCopy];
    travel[GSShouldUsePowerSourceBasedSwitchingKey] = @YES;
    travel[GSPowerSourceBasedSwitchingBatteryModeKey] = @(GSPowerSourceBasedSwitchingModeIntegrated);
    travel[GSPowerSourceBasedSwitchingACModeKey] = @(GSPowerSourceBasedSwitchingModeDynamic);
    travel[GSBatteryThresholdEnabledKey] = @YES;
    travel[GSBatteryThresholdPercentKey] = @30;

    NSMutableDictionary *desk = [fallback mutableCopy];
    desk[GSShouldUsePowerSourceBasedSwitchingKey] = @YES;
    desk[GSPowerSourceBasedSwitchingBatteryModeKey] = @(GSPowerSourceBasedSwitchingModeDynamic);
    desk[GSPowerSourceBasedSwitchingACModeKey] = @(GSPowerSourceBasedSwitchingModeDiscrete);
    desk[GSDisplayRuleEnabledKey] = @YES;

    _prefsDict[GSProfilesKey] = @[
        @{ @"name": GSProfileNameDefault, @"settings": [self _liveRuleSnapshot] },
        @{ @"name": GSProfileNameTravel, @"settings": travel },
        @{ @"name": GSProfileNameDesk, @"settings": desk }
    ];
    _prefsDict[GSActiveProfileNameKey] = GSProfileNameDefault;
}

- (BOOL)_ensureRulePreferences
{
    BOOL dirty = NO;
    for (NSString *key in [self _profileRuleKeys]) {
        if ([self _value:_prefsDict[key] isValidForRuleKey:key])
            continue;
        _prefsDict[key] = [self _defaultValueForRuleKey:key];
        dirty = YES;
    }

    if (_prefsDict[GSHistoryEnabledKey] == nil) {
        // Recording is passive. It does not change the GPU.
        _prefsDict[GSHistoryEnabledKey] = @YES;
        dirty = YES;
    }
    if (_prefsDict[GSMenuBarShowsGPUNameKey] == nil) {
        _prefsDict[GSMenuBarShowsGPUNameKey] = @NO;
        dirty = YES;
    }
    if (![_prefsDict[GSPausedUntilKey] isKindOfClass:[NSNumber class]]) {
        _prefsDict[GSPausedUntilKey] = @0;
        dirty = YES;
    }

    NSArray *hotkeyCodes = @[
        GSHotkeyIntegratedKeyCodeKey, GSHotkeyDiscreteKeyCodeKey, GSHotkeyDynamicKeyCodeKey
    ];
    NSArray *hotkeyModifiers = @[
        GSHotkeyIntegratedModifiersKey, GSHotkeyDiscreteModifiersKey, GSHotkeyDynamicModifiersKey
    ];
    NSArray *hotkeyLabels = @[
        GSHotkeyIntegratedLabelKey, GSHotkeyDiscreteLabelKey, GSHotkeyDynamicLabelKey
    ];
    for (NSString *key in hotkeyCodes) {
        if (![_prefsDict[key] isKindOfClass:[NSNumber class]]) {
            _prefsDict[key] = @(-1);
            dirty = YES;
        }
    }
    for (NSString *key in hotkeyModifiers) {
        if (![_prefsDict[key] isKindOfClass:[NSNumber class]]) {
            _prefsDict[key] = @0;
            dirty = YES;
        }
    }
    for (NSString *key in hotkeyLabels) {
        if (![_prefsDict[key] isKindOfClass:[NSString class]]) {
            _prefsDict[key] = @"";
            dirty = YES;
        }
    }

    if (![_prefsDict[GSProfilesKey] isKindOfClass:[NSArray class]]) {
        [self _installExampleProfiles];
        dirty = YES;
    } else if (![[self profileNames] containsObject:[self activeProfileName]]) {
        NSArray *names = [self profileNames];
        _prefsDict[GSActiveProfileNameKey] = [names containsObject:GSProfileNameDefault] ? GSProfileNameDefault : (names.firstObject ?: GSProfileNameDefault);
        dirty = YES;
    }

    return dirty;
}

@end
