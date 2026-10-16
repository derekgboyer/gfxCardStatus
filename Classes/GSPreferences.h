//
//  GSPreferences.h
//  gfxCardStatus
//
//  Created by Cody Krieger on 9/26/10.
//  Copyright 2010 Cody Krieger. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GSPowerPolicy.h"

// Keys in the gfxCardStatus preferences plist. The names stay compatible with
// copies of the file written by older versions. The mode values are the
// GSPowerSourceBasedSwitchingMode integers.
extern NSString * const GSShouldUsePowerSourceBasedSwitchingKey;
extern NSString * const GSPowerSourceBasedSwitchingACModeKey;
extern NSString * const GSPowerSourceBasedSwitchingBatteryModeKey;

// Automatic rules. All of these default off except GPU history, which only
// records and never switches. Profiles store the rule keys; shortcuts, the
// menu-bar name, history, and pause are global.
extern NSString * const GSPerAppRulesEnabledKey;
extern NSString * const GSPerAppRulesKey;
extern NSString * const GSBatteryThresholdEnabledKey;
extern NSString * const GSBatteryThresholdPercentKey;
extern NSString * const GSDisplayRuleEnabledKey;
extern NSString * const GSSchedulesEnabledKey;
extern NSString * const GSSchedulesKey;
extern NSString * const GSLaunchDefaultEnabledKey;
extern NSString * const GSLaunchDefaultModeKey;
extern NSString * const GSWakeRuleEnabledKey;
extern NSString * const GSWakeModeKey;
extern NSString * const GSNotificationListsGPUAppsKey;
extern NSString * const GSMenuBarShowsGPUNameKey;
extern NSString * const GSHistoryEnabledKey;
extern NSString * const GSDiscreteOnBatteryAlertEnabledKey;
extern NSString * const GSDiscreteOnBatteryAlertMinutesKey;
extern NSString * const GSPausedUntilKey;
extern NSString * const GSProfilesKey;
extern NSString * const GSActiveProfileNameKey;
extern NSString * const GSHotkeyIntegratedKeyCodeKey;
extern NSString * const GSHotkeyIntegratedModifiersKey;
extern NSString * const GSHotkeyIntegratedLabelKey;
extern NSString * const GSHotkeyDiscreteKeyCodeKey;
extern NSString * const GSHotkeyDiscreteModifiersKey;
extern NSString * const GSHotkeyDiscreteLabelKey;
extern NSString * const GSHotkeyDynamicKeyCodeKey;
extern NSString * const GSHotkeyDynamicModifiersKey;
extern NSString * const GSHotkeyDynamicLabelKey;

extern NSString * const GSProfileNameDefault;
extern NSString * const GSProfileNameTravel;
extern NSString * const GSProfileNameDesk;

@class GSPreferencesDictionary;

@interface GSPreferences : NSObject <NSWindowDelegate>

// KVO-compliant map of preference keys. Cocoa bindings and observers use
// key paths such as "prefsDict.shouldStartAtLogin".
@property (strong) GSPreferencesDictionary *prefsDict;

- (void)setUpPreferences;
- (void)setDefaults;
- (void)savePreferences;

- (BOOL)shouldCheckForUpdatesOnStartup;
- (BOOL)shouldStartAtLogin;
- (BOOL)shouldDisplayNotifications;
- (BOOL)shouldUsePowerSourceBasedSwitching;
- (BOOL)shouldUseSmartMenuBarIcons;
- (GSPowerSourceBasedSwitchingMode)modeForACAdapter;
- (GSPowerSourceBasedSwitchingMode)modeForBattery;

// Saves immediately. Used by the status menu. Out-of-range modes are ignored.
// source must be battery or AC.
- (void)setPowerSourceBasedSwitchingMode:(GSPowerSourceBasedSwitchingMode)mode
                           forPowerSource:(GSPowerSource)source;

- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key fallback:(NSInteger)fallback;
- (void)setDouble:(double)value forKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
- (void)setArray:(NSArray *)array forKey:(NSString *)key;
- (NSArray *)arrayForKey:(NSString *)key;
- (void)setString:(NSString *)value forKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;

// Named bundles of the automatic-rule keys. The live keys are what the
// engine reads. Activating a profile copies those live keys back into the
// profile that was active, then loads the chosen snapshot.
- (NSArray<NSString *> *)profileNames;
- (NSString *)activeProfileName;
- (NSString *)displayNameForProfile:(NSString *)name;
- (NSDictionary *)settingsForProfileNamed:(NSString *)name;
- (void)captureActiveProfile;
- (void)setActiveProfileName:(NSString *)name;
- (void)applyRuleSettings:(NSDictionary *)settings;
- (BOOL)saveNewProfileNamed:(NSString *)name;

+ (GSPreferences *)sharedInstance;

@end
