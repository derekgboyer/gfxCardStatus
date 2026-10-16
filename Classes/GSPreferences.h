//
//  GSPreferences.h
//  gfxCardStatus
//
//  Created by Cody Krieger on 9/26/10.
//  Copyright 2010 Cody Krieger. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum {
    GSPowerSourceBasedSwitchingModeIntegrated = 0,
    GSPowerSourceBasedSwitchingModeDiscrete = 1,
    GSPowerSourceBasedSwitchingModeDynamic = 2
} GSPowerSourceBasedSwitchingMode;

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

- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;

+ (GSPreferences *)sharedInstance;

@end
