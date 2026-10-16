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

+ (GSPreferences *)sharedInstance;

@end
