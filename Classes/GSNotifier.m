//
//  GSNotifier.m
//  gfxCardStatus
//
//  Created by Cody Krieger on 6/12/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import "GSNotifier.h"
#import "NSAttributedString+Hyperlink.h"
#import "GSMux.h"
#import "GSPreferences.h"

#import <UserNotifications/UserNotifications.h>

#define kGPUChangedNotificationKey @"GrowlGPUChanged"

#define kIntegratedOnlyMessageExplanationURL [kApplicationWebsiteURL stringByAppendingString:@"/switching.html#integrated-only-mode-limitations"]
#define kGPUChangeNotificationIdentifier @"com.codykrieger.gfxCardStatus.gpu-changed"

@interface GSNotifier () <UNUserNotificationCenterDelegate>
- (NSString *)_keyForNotificationType:(GSGPUType)type;
@end

@implementation GSNotifier {
    NSString *_lastMessage;
}

#pragma mark - Initializers

+ (GSNotifier *)sharedInstance
{
    static dispatch_once_t pred = 0;
    __strong static GSNotifier *_sharedObject = nil;
    dispatch_once(&pred, ^{
        _sharedObject = [[self alloc] init];
    });
    return _sharedObject;
}

- (id)init
{
    if (!(self = [super init]))
        return nil;

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                          completionHandler:^(BOOL granted, NSError *error) {
        if (error)
            GSLogError(@"Notification authorization failed: %@", error);
        else
            GSLogDebug(@"Notification authorization granted: %d", granted);
    }];

    return self;
}

#pragma mark - GSNotifier API

- (void)showGPUChangeNotification:(GSGPUType)type
{
    // Get the localized notification name and message, as well as the current
    // GPU name for display in the message.
    NSString *key = [self _keyForNotificationType:type];
    NSString *title = Str(key);
    NSString *cardName = type == GSGPUTypeIntegrated ? [GSGPU integratedGPUName] : [GSGPU discreteGPUName];
    NSString *message = [NSString stringWithFormat:Str([key stringByAppendingString:@"Message"]), cardName];

    // Make sure that we don't display the notification if it's the same message
    // as the last one we fired off. Because that's unbelievably annoying. Also
    // check to make sure the user even wants to see the notifications in the
    // first place.
    if (![message isEqualToString:_lastMessage] && [GSPreferences sharedInstance].shouldDisplayNotifications) {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body = message;

        // A stable identifier replaces the previous GPU notification instead of stacking them.
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:kGPUChangeNotificationIdentifier
                                                                              content:content
                                                                              trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                               withCompletionHandler:^(NSError *error) {
            if (error)
                GSLogError(@"Failed to deliver GPU change notification: %@", error);
        }];

        _lastMessage = message;
    }
}

- (void)showOneTimeNotification
{
    NSAlert *versionInfo = [[NSAlert alloc] init];
    versionInfo.messageText = Str(@"ThanksForDownloading");
    versionInfo.informativeText = Str(@"PleaseConsiderDonating");
    NSTextView *accessory = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 15)];
    NSAttributedString *link = [NSAttributedString hyperlinkFromString:kApplicationWebsiteURL
                                                                withURL:[NSURL URLWithString:kApplicationWebsiteURL]];
    [accessory.textStorage setAttributedString:link];
    accessory.editable = NO;
    accessory.drawsBackground = NO;
    accessory.selectable = YES;
    versionInfo.accessoryView = accessory;
    [versionInfo addButtonWithTitle:Str(@"DontShowAgain")];
    [versionInfo runModal];
}

- (void)showGPUSwitchingUnavailableMessage
{
    BOOL appleSilicon = [GSGPU isAppleSiliconMac];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = Str(appleSilicon ? @"AppleSiliconUnsupported" : @"UnsupportedMachine");
    alert.informativeText = Str(appleSilicon ? @"AppleSiliconUnsupportedMessage" : @"UnsupportedMachineMessage");
    [alert addButtonWithTitle:Str(@"OhISee")];
    [alert runModal];
}

- (void)showCantSwitchToIntegratedOnlyMessage:(NSArray *)taskList
{
    NSString *messageKey = [NSString stringWithFormat:@"Can'tSwitchToIntegratedOnly%@", (taskList.count > 1 ? @"Plural" : @"Singular")];

    NSMutableString *descriptionText = [[NSMutableString alloc] init];
    for (NSString *taskName in taskList)
        [descriptionText appendFormat:@"%@\n", taskName];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = Str(messageKey);
    alert.informativeText = descriptionText;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Why?"];

    if ([alert runModal] == NSAlertSecondButtonReturn)
        GSOpenURL([NSURL URLWithString:kIntegratedOnlyMessageExplanationURL]);
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    // gfxCardStatus is a menu bar agent, so it is effectively always "foreground".
    // Show the banner anyway, matching the old shouldPresentNotification: behavior.
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}

#pragma mark - Private helpers

- (NSString *)_keyForNotificationType:(GSGPUType)type
{
    if (type == GSGPUTypeIntegrated || type == GSGPUTypeDiscrete)
        return kGPUChangedNotificationKey;
    
    assert(false); // We shouldn't ever get here.
    
    return nil;
}

@end
