//
//  GSRuleEngine.h
//  gfxCardStatus
//
//  One place that turns preferences, power, apps, displays, and the clock
//  into a GPU change. GSRulesDecide owns the priority. This object owns the
//  timers, the mux call, history, and the pause / profile commands.
//
//  Manual override > pause > per-app > external display > battery threshold
//  > schedule > power source (including Don't Change) > launch or wake.
//  See GSRules.h and the README.
//

#import "GSGPU.h"
#import "GSMux.h"
#import "GSRules.h"

extern NSString * const GSRuleEngineStateDidChangeNotification;

typedef NS_ENUM(NSInteger, GSRuleEvent) {
    GSRuleEventLaunch = 0,
    GSRuleEventContinuous,
    GSRuleEventWake
};

@interface GSRuleEngine : NSObject

+ (GSRuleEngine *)sharedEngine;

@property (readonly, getter=isPaused) BOOL paused;
@property (readonly) NSDate *pausedUntil;

- (BOOL)isSuppressingPreferenceApplication;
- (BOOL)shouldHandleLaunch;
- (BOOL)anyAutomaticRuleEnabled;

// --pause, --resume, --profile NAME, and --status. Does not switch.
// A profile load replaces the live rule keys before launch is evaluated.
- (void)consumeLaunchArguments:(NSArray<NSString *> *)arguments;
- (BOOL)takeStatusRequest;

- (void)applyForEvent:(GSRuleEvent)event;
- (BOOL)userRequestedMode:(GSSwitcherMode)mode source:(NSString *)source;
// The status menu already called setMode:. Records the hold and history.
- (void)noteUserDidSwitchToMode:(GSSwitcherMode)mode source:(NSString *)source;
- (void)noteGPUChangedTo:(GSGPUType)gpu;

- (void)pauseForOneHour;
- (void)resumeAutomaticRules;
- (BOOL)activateProfileNamed:(NSString *)name;
- (void)reloadHotKeys;
- (void)handleURLs:(NSArray<NSURL *> *)urls;
- (void)publishStatusNotifying:(BOOL)notify;
- (void)notifyStateChanged;
- (NSArray<NSString *> *)historyMenuLines;

@end
