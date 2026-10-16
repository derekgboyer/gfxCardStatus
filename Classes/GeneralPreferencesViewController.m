//
//  GeneralPreferencesViewController.m
//  gfxCardStatus
//
//  Created by Michal Vančo on 7/11/11.
//  Copyright 2011 Michal Vančo. All rights reserved.
//

#import "GeneralPreferencesViewController.h"
#import "GSNotifier.h"
#import "GSPreferences.h"
#import "GSStartup.h"
#import "GSGPU.h"

#define kGeneralPreferencesName         @"General"

#define kShouldStartAtLoginKeyPath      @"prefsDict.shouldStartAtLogin"

static void *GSShouldStartAtLoginContext = &GSShouldStartAtLoginContext;

@interface GeneralPreferencesViewController (Internal)
- (BOOL)isLegacyMachine;
@end

@implementation GeneralPreferencesViewController {
    BOOL _observingStartupPreference;
}

@synthesize prefChkSmartIcons;
@synthesize prefChkUpdate;
@synthesize prefChkStartup;
@synthesize prefChkGrowl;
@synthesize prefs;

#pragma mark - Initializers

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (!(self = [super initWithNibName:@"GeneralPreferencesView" bundle:nil]))
        return nil;
    
    prefs = [GSPreferences sharedInstance];
    
    return self;
}

#pragma mark - Overrides

- (void)loadView
{
    [super loadView];

    // Add or remove the app from the current user's Login Items when the
    // bound preference changes.
    if (!_observingStartupPreference) {
        [prefs addObserver:self
                forKeyPath:kShouldStartAtLoginKeyPath
                   options:NSKeyValueObservingOptionNew
                   context:GSShouldStartAtLoginContext];
        _observingStartupPreference = YES;
    }
    
    NSArray *localizedButtons = [[NSArray alloc] initWithObjects:prefChkStartup, prefChkUpdate, prefChkSmartIcons, prefChkGrowl, nil];
    for (NSButton *loc in localizedButtons)
        [loc setTitle:Str([loc title])];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == GSShouldStartAtLoginContext) {
        id value = change[NSKeyValueChangeNewKey];
        BOOL enabled = [value isKindOfClass:[NSNumber class]] && [value boolValue];
        GSLogDebug(@"Start at login value changed: %@", value);
        [GSStartup loadAtStartup:enabled];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)dealloc
{
    if (_observingStartupPreference)
        [prefs removeObserver:self forKeyPath:kShouldStartAtLoginKeyPath context:GSShouldStartAtLoginContext];
}

#pragma mark - Passthrough properties

- (BOOL)isLegacyMachine
{
    return [GSGPU isLegacyMachine];
}

#pragma mark - GSPreferencesModule protocol

- (NSString *)title
{
    return Str(kGeneralPreferencesName);
}

- (NSString *)identifier
{
    return kGeneralPreferencesName;
}

- (NSImage *)image
{
    return [NSImage imageNamed:NSImageNamePreferencesGeneral];
}

@end
