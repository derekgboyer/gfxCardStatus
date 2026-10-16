//
//  gfxCardStatusAppDelegate.m
//  gfxCardStatus
//
//  Created by Cody Krieger on 4/22/10.
//  Copyright 2010 Cody Krieger. All rights reserved.
//

#import "gfxCardStatusAppDelegate.h"
#import "NSAttributedString+Hyperlink.h"
#import "GeneralPreferencesViewController.h"
#import "AdvancedPreferencesViewController.h"
#import "GSProcess.h"
#import "GSMux.h"
#import "GSNotifier.h"
#import "GSPowerSourceController.h"

#define kHasSeenOneTimeNotificationKey @"hasSeenVersionTwoMessage"
#define kShouldCheckForUpdatesOnStartupKeyPath @"prefsDict.shouldCheckForUpdatesOnStartup"

static void *GSShouldCheckForUpdatesContext = &GSShouldCheckForUpdatesContext;

@implementation gfxCardStatusAppDelegate {
    BOOL _observingUpdateCheck;
}

#pragma mark - Initialization

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Initialize the preferences object and set default preferences if this is
    // a first-time run.
    _prefs = [GSPreferences sharedInstance];

    // Attempt to open a connection to AppleGraphicsControl. Apple silicon and
    // other Macs without a mux don't have this driver; keep running so the
    // menu bar item can explain that switching doesn't apply.
    BOOL switchingAvailable = [[GSMux defaultMux] switcherOpen];
    BOOL commandLineOverride = NO;
    if (!switchingAvailable) {
        GSLogError(@"Can't open connection to AppleGraphicsControl. GPU switching isn't available on this Mac.");
    } else {
        GSLogInfo(@"GPUs present: %@", [GSGPU getGPUNames]);
        GSLogInfo(@"Integrated GPU name: %@", [GSGPU integratedGPUName]);
        GSLogInfo(@"Discrete GPU name: %@", [GSGPU discreteGPUName]);
        
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if ([args indexOfObject:@"--discrete"] != NSNotFound) {
            [[GSMux defaultMux] setMode:GSSwitcherModeForceDiscrete];
            commandLineOverride = YES;
        } else if ([args indexOfObject:@"--integrated"] != NSNotFound) {
            [[GSMux defaultMux] setMode:GSSwitcherModeForceIntegrated];
            commandLineOverride = YES;
        } else if ([args indexOfObject:@"--dynamic"] != NSNotFound) {
            [[GSMux defaultMux] setMode:GSSwitcherModeDynamicSwitching];
            commandLineOverride = YES;
        } else if (![GSGPU isLegacyMachine] && ![_prefs shouldUsePowerSourceBasedSwitching]) {
            // Set the machine to dynamic switching to get it out of any kind of
            // weird state from the get go. Skipped when power-source rules are
            // on: those rules, including Don't Change, decide the launch mode.
            [[GSMux defaultMux] setMode:GSSwitcherModeDynamicSwitching];
        }

        // Now accepting GPU change notifications! Apply at your nearest GSGPU today.
        [GSGPU registerForGPUChangeNotifications:self];
    }

    // Register with NSWorkspace for system shutdown notifications to ensure
    // proper termination in the event of system shutdown and/or user logout.
    // Goal is to ensure machine is set to default dynamic switching before shut down.
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    [[workspace notificationCenter] addObserver:self
                                       selector:@selector(workspaceWillPowerOff:)
                                           name:NSWorkspaceWillPowerOffNotification
                                         object:workspace];

    // Initialize the menu bar icon and hook the menu up to it.
    [_menuController setupMenu];

    // Menu is listening for power-source updates before monitoring starts,
    // so the first reading refreshes the status menu.
    if (switchingAvailable)
        [[GSPowerSourceController sharedController] startMonitoringWithManualOverride:commandLineOverride];

    if (!switchingAvailable && ![_prefs boolForKey:@"hasSeenGPUSwitchingUnavailableMessage"]) {
        [[GSNotifier sharedInstance] showGPUSwitchingUnavailableMessage];
        [_prefs setBool:YES forKey:@"hasSeenGPUSwitchingUnavailableMessage"];
    }

    // Show the one-time startup notification asking users to be kind and donate
    // if they like gfxCardStatus. Then make it go away forever.
    if (![_prefs boolForKey:kHasSeenOneTimeNotificationKey]) {
        [[GSNotifier sharedInstance] showOneTimeNotification];
        [_prefs setBool:YES forKey:kHasSeenOneTimeNotificationKey];
    }

    // Argh. In v2.5b1, I introduced some code that set the _updater.feedURL property, which results in the
    // SUFeedURL defaults key being set. Sparkle will prefer that value over the SUFeedURL defined in
    // Info.plist, resulting in gfxCardStatus being "pinned" to the beta channel on that machine in
    // perpetuity. In order to fix that silly mistake, the appcasts on the server side have been moved to
    // /appcasts/<channel>.xml, which allows us to easily detect and remove the bad value from the defaults
    // store without accidentally deleting someone's intentionally-set SUFeedURL.
    NSString *feedURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"SUFeedURL"];
    if ([feedURL containsString:@"appcast.beta.xml"])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SUFeedURL"];

    GSLogInfo(@"Appcast URL: %@", _updaterController.updater.feedURL);

    // Hook up the check for updates on startup preference directly to the
    // automaticallyChecksForUpdates property on the updater.
    _updaterController.updater.automaticallyChecksForUpdates = _prefs.shouldCheckForUpdatesOnStartup;
    [_prefs addObserver:self
             forKeyPath:kShouldCheckForUpdatesOnStartupKeyPath
                options:NSKeyValueObservingOptionNew
                context:GSShouldCheckForUpdatesContext];
    _observingUpdateCheck = YES;

    // Check for updates if the user has them enabled.
    if ([_prefs shouldCheckForUpdatesOnStartup])
        [_updaterController.updater checkForUpdatesInBackground];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == GSShouldCheckForUpdatesContext) {
        id value = change[NSKeyValueChangeNewKey];
        BOOL enabled = [value isKindOfClass:[NSNumber class]] && [value boolValue];
        GSLogDebug(@"Check for updates on startup value changed: %@", value);
        _updaterController.updater.automaticallyChecksForUpdates = enabled;
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)dealloc
{
    if (_observingUpdateCheck)
        [_prefs removeObserver:self forKeyPath:kShouldCheckForUpdatesOnStartupKeyPath context:GSShouldCheckForUpdatesContext];
}

#pragma mark - Termination Notifications

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Set the machine to dynamic switching before shutdown to avoid machine restarting
    // stuck in a forced GPU mode.
    if ([[GSMux defaultMux] isOpen] && ![GSGPU isLegacyMachine])
        [[GSMux defaultMux] setMode:GSSwitcherModeDynamicSwitching];

    GSLogDebug(@"Termination notification received. Going to Dynamic Switching.");
}

- (void)workspaceWillPowerOff:(NSNotification *)aNotification
{
    // Selector called in response to application termination notification from
    // NSWorkspace. Also implemented to avoid the machine shuting down in a forced
    // GPU state.
    [[NSApplication sharedApplication] terminate:self];
    GSLogDebug(@"NSWorkspaceWillPowerOff notification received. Terminating application.");
}

#pragma mark - GSGPUDelegate protocol

- (void)GPUDidChangeTo:(GSGPUType)gpu
{
    // The display-reconfiguration callback invokes this off the main queue.
    // Power-source rules also refresh the menu on the main queue, so the GPU
    // update has to land there too.
    dispatch_async(dispatch_get_main_queue(), ^{
        [_menuController updateMenu];
        [[GSNotifier sharedInstance] showGPUChangeNotification:gpu];
    });
}

@end
