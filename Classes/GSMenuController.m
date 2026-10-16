//
//  GSMenuController.m
//  gfxCardStatus
//
//  Created by Cody Krieger on 6/12/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import "GSMenuController.h"
#import "GeneralPreferencesViewController.h"
#import "AdvancedPreferencesViewController.h"
#import "GSGPU.h"
#import "GSMux.h"
#import "GSNotifier.h"
#import "GSProcess.h"

#define kShouldUseSmartMenuBarIconsKeyPath @"prefsDict.shouldUseSmartMenuBarIcons"

static void *GSSmartMenuBarIconsContext = &GSSmartMenuBarIconsContext;
static void *GSAppearanceContext = &GSAppearanceContext;

@interface GSMenuController (Internal)
- (void)_localizeMenu;
- (void)_updateProcessList;
- (void)_updateMenuBarIconText:(BOOL)isUsingIntegrated cardString:(NSString *)cardString;
@end

@implementation GSMenuController {
    BOOL _observingAppearance;
}

@synthesize statusMenu;

@synthesize versionItem;
@synthesize updateItem;
@synthesize preferencesItem;
@synthesize quitItem;
@synthesize visitWebsiteItem;
@synthesize currentCard;
@synthesize currentPowerSource;
@synthesize switchGPUs;
@synthesize integratedOnly;
@synthesize discreteOnly;
@synthesize dynamicSwitching;
@synthesize processesSeparator;
@synthesize dependentProcesses;
@synthesize processList;

@synthesize menuIsOpen;

#pragma mark - Initializers

- (id)init
{
    if (!(self = [super init]))
        return nil;
    
    _prefs = [GSPreferences sharedInstance];
    [_prefs addObserver:self
             forKeyPath:kShouldUseSmartMenuBarIconsKeyPath
                options:NSKeyValueObservingOptionNew
                context:GSSmartMenuBarIconsContext];
    
    return self;
}

- (void)dealloc
{
    [_prefs removeObserver:self forKeyPath:kShouldUseSmartMenuBarIconsKeyPath context:GSSmartMenuBarIconsContext];
    if (_observingAppearance)
        [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:GSAppearanceContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == GSSmartMenuBarIconsContext || context == GSAppearanceContext) {
        if (context == GSSmartMenuBarIconsContext)
            GSLogDebug(@"Use smart menu bar icons value changed: %@", change[NSKeyValueChangeNewKey]);
        [self updateMenu];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - GSMenuController API

- (void)setupMenu
{
    [statusMenu setDelegate:self];
    
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.menu = statusMenu;
    if (!_observingAppearance) {
        [NSApp addObserver:self
               forKeyPath:@"effectiveAppearance"
                  options:0
                  context:GSAppearanceContext];
        _observingAppearance = YES;
    }
    
    BOOL isLegacyMachine = [GSGPU isLegacyMachine];
    [switchGPUs setHidden:!isLegacyMachine];
    [integratedOnly setHidden:isLegacyMachine];
    [discreteOnly setHidden:isLegacyMachine];
    [dynamicSwitching setHidden:isLegacyMachine];

    [self _localizeMenu];
    [self updateMenu];
}

- (void)updateMenu
{
    GSLogDebug(@"Updating status...");

    BOOL isUsingIntegrated = [GSMux defaultMux].isUsingIntegratedGPU;

    NSString *gpuString = (isUsingIntegrated ? [GSGPU integratedGPUName] : [GSGPU discreteGPUName]);
    [self _updateMenuBarIconText:isUsingIntegrated cardString:gpuString];

    if (![GSGPU isLegacyMachine]) {
        BOOL dynamic = [GSMux defaultMux].isUsingDynamicSwitching;

        GSLogInfo(@"Using dynamic switching?: %d", dynamic);
        GSLogInfo(@"Using old-style switching policy?: %d", [GSMux defaultMux].isUsingOldStyleSwitchPolicy);

        [integratedOnly setState:(isUsingIntegrated && !dynamic) ? NSControlStateValueOn : NSControlStateValueOff];
        [discreteOnly setState:(!isUsingIntegrated && !dynamic) ? NSControlStateValueOn : NSControlStateValueOff];
        [dynamicSwitching setState:dynamic ? NSControlStateValueOn : NSControlStateValueOff];
    }

    [currentCard setTitle:[Str(@"Card") stringByReplacingOccurrencesOfString:@"%%" withString:gpuString]];

    if (isUsingIntegrated)
        GSLogInfo(@"%@ in use. Sweet deal! More battery life.", [GSGPU integratedGPUName]);
    else
        GSLogInfo(@"%@ in use. Bummer! Less battery life for you.", [GSGPU discreteGPUName]);

    if (!isUsingIntegrated)
        [self _updateProcessList];
}

#pragma mark - UI Actions

- (IBAction)openAbout:(id)sender
{
    [[NSApplication sharedApplication] orderFrontStandardAboutPanel:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)openPreferences:(id)sender
{
    if (!_preferencesWindowController) {
        _preferencesWindowController = [[PreferencesWindowController alloc] init];
        
        NSArray *modules = [NSArray arrayWithObjects:
                            [[GeneralPreferencesViewController alloc] init], 
                            [[AdvancedPreferencesViewController alloc] init],
                            nil];
        
        [_preferencesWindowController setModules:modules];
    }
    
    [_preferencesWindowController.window center];
    [_preferencesWindowController.window makeKeyAndOrderFront:self];
    [_preferencesWindowController.window setOrderedIndex:0];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)openApplicationURL:(id)sender
{
    GSOpenURL([NSURL URLWithString:kApplicationWebsiteURL]);
}

- (IBAction)quit:(id)sender
{
    [[NSApplication sharedApplication] terminate:self];
}

- (IBAction)setMode:(id)sender
{
    // For legacy machines.
    if (sender == switchGPUs) {
        GSLogInfo(@"Switching GPUs...");
        [[GSMux defaultMux] setMode:GSSwitcherModeToggleGPU];
        return;
    }

    // Don't go any further if the user clicked on an already-selected item.
    if ([sender state] == NSControlStateValueOn) return;

    BOOL retval = NO;

    if (sender == integratedOnly) {
        NSArray *taskList = [GSProcess getTaskList];
        if (taskList.count > 0) {
            GSLogInfo(@"Not setting Integrated Only because of dependencies list items: %@", taskList);

            NSMutableArray *taskNames = [[NSMutableArray alloc] init];
            for (NSDictionary *dict in taskList) {
                NSString *taskName = [dict objectForKey:kTaskItemName];
                [taskNames addObject:taskName];
            }

            [[GSNotifier sharedInstance] showCantSwitchToIntegratedOnlyMessage:taskNames];
            return;
        }

        GSLogInfo(@"Setting Integrated Only...");
        retval = [[GSMux defaultMux] setMode:GSSwitcherModeForceIntegrated];
    }

    if (sender == discreteOnly) { 
        GSLogInfo(@"Setting Discrete Only...");
        retval = [[GSMux defaultMux] setMode:GSSwitcherModeForceDiscrete];
    }

    if (sender == dynamicSwitching) {
        GSLogInfo(@"Setting Dynamic Switching...");
        retval = [[GSMux defaultMux] setMode:GSSwitcherModeDynamicSwitching];
    }

    // Only change status in case of GPU switch success.
    if (retval) {
        [integratedOnly setState:(sender == integratedOnly ? NSControlStateValueOn : NSControlStateValueOff)];
        [discreteOnly setState:(sender == discreteOnly ? NSControlStateValueOn : NSControlStateValueOff)];
        [dynamicSwitching setState:(sender == dynamicSwitching ? NSControlStateValueOn : NSControlStateValueOff)];
    }
}

#pragma mark - NSMenuDelegate protocol

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [self _updateProcessList];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    self.menuIsOpen = YES;
}

- (void)menuDidClose:(NSMenu *)menu
{
    self.menuIsOpen = NO;
}

@end

@implementation GSMenuController (Internal)

- (void)_localizeMenu
{
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    [versionItem setTitle:[Str(@"About") stringByReplacingOccurrencesOfString:@"%%" withString:version]];
    [visitWebsiteItem setTitle:[Str(visitWebsiteItem.title) stringByReplacingOccurrencesOfString:@"%%" withString:kApplicationWebsiteURL]];
    NSArray *localized = [NSArray arrayWithObjects:updateItem, preferencesItem,
                          quitItem, switchGPUs, integratedOnly, discreteOnly, 
                          dynamicSwitching, dependentProcesses, processList, 
                          nil];
    for (NSButton *loc in localized)
        [loc setTitle:Str([loc title])];
}

- (void)_updateProcessList
{
    for (NSMenuItem *menuItem in [statusMenu itemArray]) {
        if ([menuItem indentationLevel] > 0 && ![menuItem isEqual:processList])
            [statusMenu removeItem:menuItem];
    }
    
    BOOL isUsingIntegrated = [GSMux defaultMux].isUsingIntegratedGPU;

    BOOL hide = isUsingIntegrated || [GSGPU isLegacyMachine];
    [processList setHidden:hide];
    [processesSeparator setHidden:hide];
    [dependentProcesses setHidden:hide];

    // If we're using a 9400M/9600M GT model, or if we're on the integrated GPU,
    // no need to display/update the dependencies list.
    if (hide)
        return;
    
    GSLogDebug(@"Updating process list...");
    
    NSArray *processes = [GSProcess getTaskList];
    
    [processList setHidden:([processes count] > 0)];
    
    for (NSDictionary *dict in processes) {
        NSString *taskName = [dict objectForKey:kTaskItemName];
        NSString *pid = [dict objectForKey:kTaskItemPID];
        NSString *title = [NSString stringWithString:taskName];
        if (![pid isEqualToString:@""])
            title = [title stringByAppendingFormat:@", PID: %@", pid];
        
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title 
                                                      action:nil 
                                               keyEquivalent:@""];
        [item setIndentationLevel:1];
        [statusMenu insertItem:item 
                       atIndex:([statusMenu indexOfItem:processList] + 1)];
    }
}

- (void)_updateMenuBarIconText:(BOOL)isUsingIntegrated cardString:(NSString *)cardString
{
    // Grab the first character of GPU string for the menu bar icon.
    unichar firstLetter;
    
    if ([GSGPU isLegacyMachine] || ![_prefs shouldUseSmartMenuBarIcons]) {
        firstLetter = [GSMux defaultMux].isUsingIntegratedGPU ? 'i' : 'd';
    } else {
        firstLetter = [cardString characterAtIndex:0];
    }

    NSString *letter = [[NSString stringWithFormat:@"%C", firstLetter] lowercaseString];
    CGFloat fontSize = ([letter isEqualToString:@"n"] || [letter isEqualToString:@"a"] ? 19.0 : 18.0);

    // Set our font style. labelColor follows the menu bar appearance, so the
    // glyph stays readable in Dark Mode.
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFont *boldItalic = [fontManager fontWithFamily:@"Georgia"
                                              traits:NSBoldFontMask|NSItalicFontMask
                                              weight:0
                                                size:fontSize];

    // Menu bar metrics from macOS 11 onward. The deployment target is newer.
    NSDictionary *attributes = @{
        NSFontAttributeName: boldItalic,
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSBaselineOffsetAttributeName: @(-1.0)
    };
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:letter attributes:attributes];

    _statusItem.button.attributedTitle = title;
}

@end
