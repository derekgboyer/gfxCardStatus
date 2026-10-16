//
//  GSPowerSourceController.h
//  gfxCardStatus
//
//  Watches the power source with IOPSNotificationCreateRunLoopSource.
//  GSRuleEngine decides whether the GPU changes. A settled battery/AC change
//  clears a manual hold, then the engine runs. Unknown readings do not.
//
//  IOKit readings are debounced. The same settled source does not ask the
//  engine to switch again. Editing the choice for the other power source
//  only saves it. Quitting still returns a supported Mac to Dynamic Switching.
//

#import <Cocoa/Cocoa.h>
#import "GSPowerPolicy.h"

extern NSString * const GSPowerSourceStateDidChangeNotification;

@interface GSPowerSourceController : NSObject

+ (GSPowerSourceController *)sharedController;

@property (readonly) GSPowerSource currentSource;
@property (readonly, getter=isManualOverrideActive) BOOL manualOverrideActive;
@property (readonly, getter=isMonitoring) BOOL monitoring;
// Mux is open and this is not a legacy toggle-only machine.
@property (readonly, getter=isFeatureAvailable) BOOL featureAvailable;

// manualOverride is YES when a launch argument already chose a GPU mode.
- (void)startMonitoringWithManualOverride:(BOOL)manualOverride;

// The user successfully changed modes from the status menu, a shortcut, or a URL.
// Holds until the next settled power-source change, Resume, or a profile change,
// while any automatic rule is enabled.
- (void)noteManualModeChange;

// Clears the hold without switching. The caller evaluates the rules.
- (void)clearManualOverride;

@end
