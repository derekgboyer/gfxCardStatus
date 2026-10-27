//
//  main.m
//  gfxCardStatus
//
//  Created by Cody Krieger on 4/22/10.
//  Copyright 2010 Cody Krieger. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// Sparkle prefers SUFeedURL in the user defaults domain over Info.plist, and it
// can read that value while the main nib loads. This app shares the domain with
// the original gfxCardStatus. v2.5b1 wrote the beta appcast there, and a gfx.io
// feed would keep updates on the original project. Drop only those upstream
// feeds before NSApplicationMain. Any other explicit SUFeedURL stays.
static BOOL GSDefaultsFeedURLIsUpstream(NSString *feedURL)
{
    if (![feedURL isKindOfClass:[NSString class]] || feedURL.length == 0)
        return NO;

    NSString *lower = feedURL.lowercaseString;
    if ([lower containsString:@"appcast.beta.xml"])
        return YES;
    if ([lower containsString:@"://gfx.io/"] || [lower hasSuffix:@"://gfx.io"] ||
        [lower containsString:@"://www.gfx.io/"] || [lower hasSuffix:@"://www.gfx.io"])
        return YES;

    NSURL *url = [NSURL URLWithString:feedURL];
    NSString *host = url.host.lowercaseString;
    if (host.length && ([host isEqualToString:@"gfx.io"] || [host hasSuffix:@".gfx.io"]))
        return YES;

    NSString *path = url.path.lowercaseString;
    if ([host isEqualToString:@"github.com"] &&
        ([path isEqualToString:@"/codykrieger/gfxcardstatus"] ||
         [path hasPrefix:@"/codykrieger/gfxcardstatus/"]))
        return YES;

    return NO;
}

static void GSRemoveUpstreamSparkleFeedURL(void)
{
    // Edit the application domain by bundle id. standardUserDefaults is that
    // domain once the bundle is loaded; persistentDomainForName: also covers
    // the on-disk plist if the in-memory search list is not ready yet.
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID.length == 0)
        bundleID = @"com.codykrieger.gfxCardStatus";

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *persistent = [defaults persistentDomainForName:bundleID];
    NSString *feedURL = persistent[@"SUFeedURL"];
    if (![feedURL isKindOfClass:[NSString class]])
        feedURL = [defaults stringForKey:@"SUFeedURL"];
    if (!GSDefaultsFeedURLIsUpstream(feedURL))
        return;

    NSLog(@"info: Removing upstream SUFeedURL from user defaults so updates use this fork's appcast.");
    if (persistent != nil) {
        NSMutableDictionary *updated = [persistent mutableCopy];
        [updated removeObjectForKey:@"SUFeedURL"];
        [defaults setPersistentDomain:updated forName:bundleID];
    }
    [defaults removeObjectForKey:@"SUFeedURL"];
}

int main(int argc, char *argv[])
{
    GSRemoveUpstreamSparkleFeedURL();
    return NSApplicationMain(argc,  (const char **) argv);
}
