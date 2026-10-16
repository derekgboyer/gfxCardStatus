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
#define kPowerSourceBasedSwitchingACMode        @"GPUSetting_ACAdaptor"
#define kPowerSourceBasedSwitchingBatteryMode   @"GPUSetting_Battery"

#define kShouldStartAtLoginKey                  @"shouldStartAtLogin"
#define kShouldCheckForUpdatesOnStartupKey      @"shouldCheckForUpdatesOnStartup"
#define kShouldUsePowerSourceBasedSwitchingKey  @"shouldUsePowerSourceBasedSwitching"
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
    _prefsDict[kShouldUsePowerSourceBasedSwitchingKey] = @NO;
    _prefsDict[kShouldUseSmartMenuBarIconsKey] = @NO;
    
    _prefsDict[kPowerSourceBasedSwitchingBatteryMode] = @(GSPowerSourceBasedSwitchingModeIntegrated);
    if ([GSGPU isLegacyMachine])
        _prefsDict[kPowerSourceBasedSwitchingACMode] = @(GSPowerSourceBasedSwitchingModeDiscrete);
    else
        _prefsDict[kPowerSourceBasedSwitchingACMode] = @(GSPowerSourceBasedSwitchingModeDynamic);
    
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
    return [_prefsDict[kShouldUsePowerSourceBasedSwitchingKey] boolValue];
}

- (BOOL)shouldUseSmartMenuBarIcons
{
    return [_prefsDict[kShouldUseSmartMenuBarIconsKey] boolValue];
}

- (GSPowerSourceBasedSwitchingMode)modeForACAdapter
{
    return [_prefsDict[kPowerSourceBasedSwitchingACMode] intValue];
}

- (GSPowerSourceBasedSwitchingMode)modeForBattery
{
    return [_prefsDict[kPowerSourceBasedSwitchingBatteryMode] intValue];
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

@end
