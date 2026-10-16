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
#import "GSPowerSourceController.h"
#import "GSRuleEngine.h"

#define kShouldUseSmartMenuBarIconsKeyPath @"prefsDict.shouldUseSmartMenuBarIcons"

static void *GSSmartMenuBarIconsContext = &GSSmartMenuBarIconsContext;
static void *GSAppearanceContext = &GSAppearanceContext;

@interface GSMenuController (Internal)
- (void)_localizeMenu;
- (void)_updateMenuForUnavailableSwitching;
- (void)_updateProcessList;
- (void)_updateMenuBarIconText:(BOOL)isUsingIntegrated cardString:(NSString *)cardString;
- (void)_installPowerSourceMenuItems;
- (void)_updatePowerControls;
- (void)_markModeMenu:(NSMenu *)menu selected:(GSPowerSourceBasedSwitchingMode)mode;
- (NSMenu *)_powerModeMenu;
- (NSString *)_menuTitleForPreferenceKey:(NSString *)key;
- (void)_powerSourceStateDidChange:(NSNotification *)notification;
- (void)_rebuildProfilesMenu;
- (void)_rebuildHistoryMenu;
@end

@implementation GSMenuController {
    BOOL _observingAppearance;
    BOOL _observingPowerSource;
    NSMenuItem *_powerSourceSeparator;
    NSMenuItem *_powerSourceSwitchingItem;
    NSMenuItem *_onBatteryItem;
    NSMenuItem *_pluggedInItem;
    NSMenu *_onBatteryMenu;
    NSMenu *_pluggedInMenu;
    NSMenuItem *_pauseItem;
    NSMenuItem *_resumeItem;
    NSMenuItem *_profilesItem;
    NSMenu *_profilesMenu;
    NSMenuItem *_historyItem;
    NSMenu *_historyMenu;
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
@synthesize switchingUnavailableItem;
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
    if (_observingPowerSource) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:GSPowerSourceStateDidChangeNotification
                                                      object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:GSRuleEngineStateDidChangeNotification
                                                      object:nil];
    }
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

    // The power-source item is in the nib and starts hidden. Show it whenever
    // the mux is open, including legacy machines. The rules themselves are
    // only offered where Integrated / Discrete / Dynamic all exist.
    [currentPowerSource setHidden:![[GSMux defaultMux] isOpen]];
    if ([[GSPowerSourceController sharedController] isFeatureAvailable])
        [self _installPowerSourceMenuItems];

    if (!_observingPowerSource) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_powerSourceStateDidChange:)
                                                     name:GSPowerSourceStateDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_powerSourceStateDidChange:)
                                                     name:GSRuleEngineStateDidChangeNotification
                                                   object:nil];
        _observingPowerSource = YES;
    }

    [self updateMenu];
}

- (void)updateMenu
{
    if (![[GSMux defaultMux] isOpen]) {
        [self _updateMenuForUnavailableSwitching];
        return;
    }

    GSLogDebug(@"Updating status...");

    _statusItem.button.appearsDisabled = NO;
    [switchingUnavailableItem setHidden:YES];

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

    // Always refresh. Switching to the integrated GPU (including from a
    // power-source rule) has to hide the dependency list without waiting
    // for the menu to open.
    [self _updateProcessList];

    [self _updatePowerControls];
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
        [[GSRuleEngine sharedEngine] noteUserDidSwitchToMode:GSSwitcherModeToggleGPU source:Str(@"StatusMenu")];
        return;
    }

    // Don't go any further if the user clicked on an already-selected item.
    if ([sender state] == NSControlStateValueOn) return;

    BOOL retval = NO;
    GSSwitcherMode chosen = GSSwitcherModeDynamicSwitching;

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
        chosen = GSSwitcherModeForceIntegrated;
        retval = [[GSMux defaultMux] setMode:GSSwitcherModeForceIntegrated];
    }

    if (sender == discreteOnly) { 
        GSLogInfo(@"Setting Discrete Only...");
        chosen = GSSwitcherModeForceDiscrete;
        retval = [[GSMux defaultMux] setMode:GSSwitcherModeForceDiscrete];
    }

    if (sender == dynamicSwitching) {
        GSLogInfo(@"Setting Dynamic Switching...");
        chosen = GSSwitcherModeDynamicSwitching;
        retval = [[GSMux defaultMux] setMode:GSSwitcherModeDynamicSwitching];
    }

    // Only change status in case of GPU switch success.
    if (retval) {
        [integratedOnly setState:(sender == integratedOnly ? NSControlStateValueOn : NSControlStateValueOff)];
        [discreteOnly setState:(sender == discreteOnly ? NSControlStateValueOn : NSControlStateValueOff)];
        [dynamicSwitching setState:(sender == dynamicSwitching ? NSControlStateValueOn : NSControlStateValueOff)];

        // Holds until the power source changes, Resume, or a profile change.
        [[GSRuleEngine sharedEngine] noteUserDidSwitchToMode:chosen source:Str(@"StatusMenu")];
        // Title and checkmarks, without inserting or removing items while the
        // status menu is still tracking this click.
        [self _updatePowerControls];
    }
}

- (IBAction)togglePowerSourceSwitching:(id)sender
{
    BOOL enabled = ![_prefs shouldUsePowerSourceBasedSwitching];
    [_prefs setBool:enabled forKey:GSShouldUsePowerSourceBasedSwitchingKey];
    [self _updatePowerControls];
}

- (IBAction)pauseAutomaticRules:(id)sender
{
    (void)sender;
    [[GSRuleEngine sharedEngine] pauseForOneHour];
    [self _updatePowerControls];
}

- (IBAction)resumeAutomaticRules:(id)sender
{
    (void)sender;
    [[GSRuleEngine sharedEngine] resumeAutomaticRules];
    [self _updatePowerControls];
}

- (IBAction)selectProfile:(id)sender
{
    if (![sender isKindOfClass:[NSMenuItem class]])
        return;
    NSString *name = [sender representedObject];
    if (![name isKindOfClass:[NSString class]])
        return;
    [[GSRuleEngine sharedEngine] activateProfileNamed:name];
    [self _updatePowerControls];
}

- (IBAction)setPowerSourceMode:(id)sender
{
    if (![sender isKindOfClass:[NSMenuItem class]])
        return;

    NSMenuItem *item = sender;
    GSPowerSource source = (item.menu == _onBatteryMenu) ? GSPowerSourceBattery : GSPowerSourceACAdapter;
    [_prefs setPowerSourceBasedSwitchingMode:(GSPowerSourceBasedSwitchingMode)item.tag
                               forPowerSource:source];
    [self _updatePowerControls];
}

#pragma mark - NSMenuDelegate protocol

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu == _profilesMenu) {
        [self _rebuildProfilesMenu];
        return;
    }
    if (menu == _historyMenu) {
        [self _rebuildHistoryMenu];
        return;
    }
    if (![[GSMux defaultMux] isOpen])
        return;

    [self _updateProcessList];
    [self _updatePowerControls];
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
                          dynamicSwitching, switchingUnavailableItem, dependentProcesses, processList, 
                          nil];
    for (NSButton *loc in localized)
        [loc setTitle:Str([loc title])];
}

- (void)_updateMenuForUnavailableSwitching
{
    [switchGPUs setHidden:YES];
    [integratedOnly setHidden:YES];
    [discreteOnly setHidden:YES];
    [dynamicSwitching setHidden:YES];
    [switchingUnavailableItem setHidden:NO];
    [processList setHidden:YES];
    [processesSeparator setHidden:YES];
    [dependentProcesses setHidden:YES];
    [currentCard setTitle:Str(@"GPUSwitchingUnavailable")];
    [currentPowerSource setHidden:YES];
    [_powerSourceSeparator setHidden:YES];
    [_powerSourceSwitchingItem setHidden:YES];
    [_onBatteryItem setHidden:YES];
    [_pluggedInItem setHidden:YES];
    [_pauseItem setHidden:YES];
    [_resumeItem setHidden:YES];
    [_profilesItem setHidden:YES];
    [_historyItem setHidden:YES];

    if (_statusItem != nil)
        _statusItem.button.appearsDisabled = YES;

    // A dash stands in for the usual i/d (or vendor) glyph.
    [self _updateMenuBarIconText:NO cardString:@"–"];
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

- (void)_updateMenuBarIconText:(BOOL)__unused isUsingIntegrated cardString:(NSString *)cardString
{
    if ([[GSMux defaultMux] isOpen] && [_prefs boolForKey:GSMenuBarShowsGPUNameKey]) {
        NSString *name = cardString.length ? cardString : @"?";
        if (name.length > 18)
            name = [[name substringToIndex:17] stringByAppendingString:@"…"];
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor labelColor]
        };
        _statusItem.button.attributedTitle = [[NSAttributedString alloc] initWithString:name attributes:attributes];
        return;
    }

    // Grab the first character of GPU string for the menu bar icon.
    unichar firstLetter;

    if (![[GSMux defaultMux] isOpen]) {
        firstLetter = [@"–" characterAtIndex:0];
    } else if ([GSGPU isLegacyMachine] || ![_prefs shouldUseSmartMenuBarIcons]) {
        firstLetter = [GSMux defaultMux].isUsingIntegratedGPU ? 'i' : 'd';
    } else if (cardString.length == 0) {
        firstLetter = '?';
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

- (void)_installPowerSourceMenuItems
{
    if (_powerSourceSwitchingItem)
        return;

    _powerSourceSwitchingItem = [[NSMenuItem alloc] initWithTitle:Str(@"PrefPowerSwitching")
                                                           action:@selector(togglePowerSourceSwitching:)
                                                    keyEquivalent:@""];
    _powerSourceSwitchingItem.target = self;

    _onBatteryMenu = [self _powerModeMenu];
    _pluggedInMenu = [self _powerModeMenu];

    _onBatteryItem = [[NSMenuItem alloc] initWithTitle:[self _menuTitleForPreferenceKey:@"OnBattery"]
                                                action:nil
                                         keyEquivalent:@""];
    _onBatteryItem.submenu = _onBatteryMenu;

    _pluggedInItem = [[NSMenuItem alloc] initWithTitle:[self _menuTitleForPreferenceKey:@"PluggedIn"]
                                                action:nil
                                         keyEquivalent:@""];
    _pluggedInItem.submenu = _pluggedInMenu;

    NSInteger index = [statusMenu indexOfItem:dynamicSwitching];
    if (index == NSNotFound)
        index = [statusMenu numberOfItems];
    else
        index += 1;

    _powerSourceSeparator = [NSMenuItem separatorItem];
    [statusMenu insertItem:_powerSourceSeparator atIndex:index++];
    [statusMenu insertItem:_powerSourceSwitchingItem atIndex:index++];
    [statusMenu insertItem:_onBatteryItem atIndex:index++];
    [statusMenu insertItem:_pluggedInItem atIndex:index++];

    _pauseItem = [[NSMenuItem alloc] initWithTitle:Str(@"PauseAutomaticRules")
                                           action:@selector(pauseAutomaticRules:)
                                    keyEquivalent:@""];
    _pauseItem.target = self;
    _resumeItem = [[NSMenuItem alloc] initWithTitle:Str(@"ResumeAutomaticRules")
                                            action:@selector(resumeAutomaticRules:)
                                     keyEquivalent:@""];
    _resumeItem.target = self;

    _profilesMenu = [[NSMenu alloc] init];
    _profilesMenu.delegate = self;
    _profilesItem = [[NSMenuItem alloc] initWithTitle:Str(@"Profiles") action:nil keyEquivalent:@""];
    _profilesItem.submenu = _profilesMenu;

    _historyMenu = [[NSMenu alloc] init];
    _historyMenu.delegate = self;
    _historyItem = [[NSMenuItem alloc] initWithTitle:Str(@"GPUHistory") action:nil keyEquivalent:@""];
    _historyItem.submenu = _historyMenu;

    [statusMenu insertItem:_pauseItem atIndex:index++];
    [statusMenu insertItem:_resumeItem atIndex:index++];
    [statusMenu insertItem:_profilesItem atIndex:index++];
    [statusMenu insertItem:_historyItem atIndex:index++];
}

- (NSMenu *)_powerModeMenu
{
    NSMenu *menu = [[NSMenu alloc] init];
    struct {
        NSString *key;
        GSPowerSourceBasedSwitchingMode mode;
    } choices[] = {
        { @"IntegratedOnly", GSPowerSourceBasedSwitchingModeIntegrated },
        { @"DiscreteOnly", GSPowerSourceBasedSwitchingModeDiscrete },
        { @"DynamicSwitching", GSPowerSourceBasedSwitchingModeDynamic },
        { @"DontChange", GSPowerSourceBasedSwitchingModeDontChange }
    };

    for (NSUInteger i = 0; i < sizeof(choices) / sizeof(choices[0]); i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:Str(choices[i].key)
                                                      action:@selector(setPowerSourceMode:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = choices[i].mode;
        [menu addItem:item];
    }
    return menu;
}

- (NSString *)_menuTitleForPreferenceKey:(NSString *)key
{
    NSString *title = Str(key);
    while (title.length > 0) {
        unichar last = [title characterAtIndex:title.length - 1];
        if (last != ':' && last != ' ' && last != 0xFF1A)
            break;
        title = [title substringToIndex:title.length - 1];
    }
    return title;
}

- (void)_updatePowerControls
{
    if (![[GSMux defaultMux] isOpen]) {
        [currentPowerSource setHidden:YES];
        return;
    }

    GSPowerSourceController *power = [GSPowerSourceController sharedController];
    NSString *sourceName = Str(@"UnknownPowerSource");
    if (power.currentSource == GSPowerSourceBattery)
        sourceName = Str(@"Battery");
    else if (power.currentSource == GSPowerSourceACAdapter)
        sourceName = Str(@"ACAdapter");

    NSString *title = [Str(@"PowerSource") stringByReplacingOccurrencesOfString:@"%%" withString:sourceName];
    if (power.featureAvailable && power.manualOverrideActive && [[GSRuleEngine sharedEngine] anyAutomaticRuleEnabled])
        title = [NSString stringWithFormat:@"%@ (%@)", title, Str(@"ManualOverride")];

    [currentPowerSource setTitle:title];
    [currentPowerSource setHidden:NO];
    [_powerSourceSeparator setHidden:NO];
    [_powerSourceSwitchingItem setHidden:NO];
    [_onBatteryItem setHidden:NO];
    [_pluggedInItem setHidden:NO];
    [_pauseItem setHidden:!power.featureAvailable];
    [_resumeItem setHidden:!power.featureAvailable];
    [_profilesItem setHidden:!power.featureAvailable];
    [_historyItem setHidden:!power.featureAvailable];

    GSRuleEngine *rules = [GSRuleEngine sharedEngine];
    _pauseItem.enabled = !rules.paused;
    if (rules.paused && rules.pausedUntil) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.timeStyle = NSDateFormatterShortStyle;
        formatter.dateStyle = NSDateFormatterNoStyle;
        _pauseItem.title = [NSString stringWithFormat:Str(@"PausedUntil"), [formatter stringFromDate:rules.pausedUntil]];
    } else {
        _pauseItem.title = Str(@"PauseAutomaticRules");
    }
    _resumeItem.enabled = rules.paused || power.manualOverrideActive;

    _powerSourceSwitchingItem.state = [_prefs shouldUsePowerSourceBasedSwitching] ? NSControlStateValueOn : NSControlStateValueOff;
    [self _markModeMenu:_onBatteryMenu selected:[_prefs modeForBattery]];
    [self _markModeMenu:_pluggedInMenu selected:[_prefs modeForACAdapter]];
}

- (void)_markModeMenu:(NSMenu *)menu selected:(GSPowerSourceBasedSwitchingMode)mode
{
    for (NSMenuItem *item in menu.itemArray)
        item.state = (item.tag == (NSInteger)mode) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)_rebuildProfilesMenu
{
    [_profilesMenu removeAllItems];
    GSPreferences *prefs = _prefs;
    NSString *active = [prefs activeProfileName];
    NSArray *names = [prefs profileNames];
    if (names.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:Str(@"NoProfiles") action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [_profilesMenu addItem:empty];
        return;
    }
    for (NSString *name in names) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[prefs displayNameForProfile:name]
                                                      action:@selector(selectProfile:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = name;
        item.state = [name isEqualToString:active] ? NSControlStateValueOn : NSControlStateValueOff;
        [_profilesMenu addItem:item];
    }
}

- (void)_rebuildHistoryMenu
{
    [_historyMenu removeAllItems];
    if (![_prefs boolForKey:GSHistoryEnabledKey]) {
        NSMenuItem *off = [[NSMenuItem alloc] initWithTitle:Str(@"HistoryOff") action:nil keyEquivalent:@""];
        off.enabled = NO;
        [_historyMenu addItem:off];
        return;
    }
    NSArray *lines = [[GSRuleEngine sharedEngine] historyMenuLines];
    if (lines.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:Str(@"HistoryEmpty") action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [_historyMenu addItem:empty];
        return;
    }
    for (NSString *line in lines) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:line action:nil keyEquivalent:@""];
        item.enabled = NO;
        [_historyMenu addItem:item];
    }
}

- (void)_powerSourceStateDidChange:(NSNotification *)__unused notification
{
    // The notification can arrive in the middle of a status-menu click
    // (a manual switch, or a power-source callback while the menu is
    // tracking). Updating the menu synchronously can insert or remove items
    // during tracking. Wait until the current event finishes.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[GSMux defaultMux] isOpen])
            [self updateMenu];
    });
}

@end
