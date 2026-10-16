//
//  GSPowerSourceController.h
//  gfxCardStatus
//
//  Watches the power source with IOPSNotificationCreateRunLoopSource and
//  applies the per-source GPU rules.
//
//  Rules, in order:
//
//  - The master switch defaults to off. While it is off, nothing here
//    changes the GPU. Launch still forces Dynamic Switching on machines
//    that support it, which is the historical behavior.
//  - While it is on, the saved choice for the current source is applied
//    at launch, when the source changes, when the switch is turned on,
//    and when the choice for the source you are on is edited. Don't Change
//    leaves the GPU alone. Launch does not force Dynamic Switching in that
//    case, because the user asked us not to change anything for this source.
//  - A mode picked from the status menu, or a --integrated / --discrete /
//    --dynamic launch argument, holds until the next settled power-source
//    change. Turning the master switch on, or editing the choice for the
//    source you are on, takes effect immediately and ends that hold.
//  - Editing the choice for the other source only saves it.
//  - The same source reported again does not switch. If the GPU is already
//    in the requested mode, the mux is not called. GPU-change notifications
//    do not re-apply the rules, so a switch cannot feed itself.
//  - IOKit can report a burst of readings while a cable is settling. Those
//    are collapsed into one evaluation so a flicker cannot switch twice.
//  - Integrated Only is not applied while an external display or a process
//    is holding the discrete GPU on. That attempt is not retried until the
//    next power-source change or until the user edits the current rule.
//  - Machines that cannot switch, and 9400M/9600M machines that only toggle,
//    never have the rules applied. The menu and preferences disable the
//    feature there.
//  - Quitting still returns a supported machine to Dynamic Switching.
//

#import <Cocoa/Cocoa.h>
#import "GSPowerPolicy.h"

extern NSString * const GSPowerSourceStateDidChangeNotification;

@interface GSPowerSourceController : NSObject

+ (GSPowerSourceController *)sharedController;

@property (readonly) GSPowerSource currentSource;
@property (readonly, getter=isManualOverrideActive) BOOL manualOverrideActive;
// Mux is open and this is not a legacy toggle-only machine.
@property (readonly, getter=isFeatureAvailable) BOOL featureAvailable;

// manualOverride is YES when a launch argument already chose a GPU mode.
- (void)startMonitoringWithManualOverride:(BOOL)manualOverride;

// The user successfully changed modes from the status menu.
- (void)noteManualModeChange;

@end
