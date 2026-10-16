//
//  AdvancedPreferencesViewController.m
//  gfxCardStatus
//
//  Created by Michal Vančo on 7/11/11.
//  Copyright 2011 Michal Vančo. All rights reserved.
//

#import "AdvancedPreferencesViewController.h"
#import "GSGPU.h"
#import "GSMux.h"
#import "GSPowerSourceController.h"
#import "GSRuleEngine.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kMargin = 20;
static const CGFloat kContentWidth = 480;
static const CGFloat kViewWidth = 520;

@interface GSFlippedView : NSView
@end

@implementation GSFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface AdvancedPreferencesViewController () <NSTableViewDataSource, NSTableViewDelegate>
- (BOOL)_switchingAvailable;
- (void)_refreshFromPreferences;
- (void)_rulesEdited;
- (void)_endRecording;
@end

@implementation AdvancedPreferencesViewController {
    NSButton *_powerSwitchingCheckbox;
    NSPopUpButton *_batteryPopup;
    NSPopUpButton *_adapterPopup;
    NSButton *_perAppCheckbox;
    NSTableView *_perAppTable;
    NSButton *_displayCheckbox;
    NSButton *_thresholdCheckbox;
    NSTextField *_thresholdField;
    NSButton *_scheduleCheckbox;
    NSTableView *_scheduleTable;
    NSButton *_launchCheckbox;
    NSPopUpButton *_launchPopup;
    NSButton *_wakeCheckbox;
    NSPopUpButton *_wakePopup;
    NSButton *_listsAppsCheckbox;
    NSButton *_menuBarNameCheckbox;
    NSButton *_historyCheckbox;
    NSButton *_alertCheckbox;
    NSTextField *_alertMinutesField;
    NSPopUpButton *_profilePopup;
    NSTextField *_profileNameField;
    NSButton *_pauseButton;
    NSButton *_resumeButton;
    NSTextField *_shortcutLabels[3];
    NSButton *_shortcutButtons[3];
    id _shortcutMonitor;
    NSWindow *_recordingWindow;
    NSInteger _recordingMode;
    BOOL _refreshing;
}

@synthesize prefs;

#pragma mark - Initializers

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    // The pane is built in code. The xib is not loaded.
    (void)nibNameOrNil;
    (void)nibBundleOrNil;
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;

    prefs = [GSPreferences sharedInstance];
    _recordingMode = -1;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_engineStateChanged:)
                                                 name:GSRuleEngineStateDidChangeNotification
                                               object:nil];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:GSRuleEngineStateDidChangeNotification object:nil];
    [self _endRecording];
    [_powerSwitchingCheckbox unbind:NSValueBinding];
    [_batteryPopup unbind:NSSelectedIndexBinding];
    [_adapterPopup unbind:NSSelectedIndexBinding];
}

- (void)loadView
{
    self.view = [self _buildView];
    [self _refreshFromPreferences];
    if ([self.view isKindOfClass:[NSScrollView class]]) {
        NSScrollView *scroll = (NSScrollView *)self.view;
        [scroll.contentView scrollToPoint:NSZeroPoint];
        [scroll reflectScrolledClipView:scroll.contentView];
    }
}

- (void)willBeDisplayed
{
    [self _refreshFromPreferences];
}

- (void)_engineStateChanged:(NSNotification *)notification
{
    (void)notification;
    // Profile and table edits post this from inside the control action.
    // Refreshing after the action returns avoids rebuilding a menu that is
    // still tracking the click.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isViewLoaded)
            [self _refreshFromPreferences];
    });
}

#pragma mark - GSPreferencesModule protocol

- (NSString *)title
{
    return Str(@"Advanced");
}

- (NSString *)identifier
{
    return @"Advanced";
}

- (NSImage *)image
{
    return [NSImage imageNamed:NSImageNameAdvanced];
}

#pragma mark - Construction

- (BOOL)_switchingAvailable
{
    return [[GSPowerSourceController sharedController] isFeatureAvailable];
}

- (NSTextField *)_wrappingFieldWithString:(NSString *)string
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.editable = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.selectable = YES;
    field.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    field.textColor = [NSColor secondaryLabelColor];
    field.stringValue = string ?: @"";
    field.cell.wraps = YES;
    field.cell.scrollable = NO;
    return field;
}

- (CGFloat)_heightForField:(NSTextField *)field width:(CGFloat)width
{
    field.preferredMaxLayoutWidth = width;
    NSSize size = [field.cell cellSizeForBounds:NSMakeRect(0, 0, width, 10000)];
    CGFloat height = ceil(size.height);
    if (height < 16)
        height = 16;
    return height;
}

- (NSString *)_keyPath:(NSString *)key
{
    return [@"prefsDict." stringByAppendingString:key];
}

- (NSPopUpButton *)_modePopupIncludingDontChange:(BOOL)includeDontChange
{
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [popup addItemWithTitle:Str(@"IntegratedOnly")];
    popup.lastItem.tag = GSPowerSourceBasedSwitchingModeIntegrated;
    [popup addItemWithTitle:Str(@"DiscreteOnly")];
    popup.lastItem.tag = GSPowerSourceBasedSwitchingModeDiscrete;
    [popup addItemWithTitle:Str(@"DynamicSwitching")];
    popup.lastItem.tag = GSPowerSourceBasedSwitchingModeDynamic;
    if (includeDontChange) {
        [popup addItemWithTitle:Str(@"DontChange")];
        popup.lastItem.tag = GSPowerSourceBasedSwitchingModeDontChange;
    }
    return popup;
}

- (NSButton *)_checkboxWithTitle:(NSString *)title identifier:(NSString *)identifier
{
    NSButton *checkbox = [NSButton checkboxWithTitle:title target:self action:@selector(_toggleRule:)];
    checkbox.identifier = identifier;
    return checkbox;
}

- (CGFloat)_place:(NSView *)view in:(NSView *)doc y:(CGFloat)y height:(CGFloat)height
{
    view.frame = NSMakeRect(kMargin, y, kContentWidth, height);
    [doc addSubview:view];
    return y + height + 8;
}

- (CGFloat)_placeCheckbox:(NSButton *)checkbox in:(NSView *)doc y:(CGFloat)y
{
    [checkbox sizeToFit];
    CGFloat height = MAX(NSHeight(checkbox.frame), 18);
    return [self _place:checkbox in:doc y:y height:height];
}

- (CGFloat)_placeHelp:(NSString *)text in:(NSView *)doc y:(CGFloat)y
{
    NSTextField *field = [self _wrappingFieldWithString:text];
    CGFloat height = [self _heightForField:field width:kContentWidth];
    return [self _place:field in:doc y:y height:height] + 8;
}

- (CGFloat)_placeHeading:(NSString *)text in:(NSView *)doc y:(CGFloat)y
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
    [label sizeToFit];
    return [self _place:label in:doc y:y height:MAX(NSHeight(label.frame), 18)] + 2;
}

- (NSTableView *)_tableWithColumns:(NSArray<NSArray *> *)columns
{
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, kContentWidth, 80)];
    table.headerView = [[NSTableHeaderView alloc] init];
    table.rowHeight = 24;
    table.dataSource = self;
    table.delegate = self;
    table.allowsColumnReordering = NO;
    table.allowsColumnResizing = YES;
    for (NSArray *spec in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        [table addTableColumn:column];
    }
    return table;
}

- (NSScrollView *)_scrollForTable:(NSTableView *)table height:(CGFloat)height
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kContentWidth, height)];
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    return scroll;
}

- (NSView *)_buildView
{
    GSFlippedView *doc = [[GSFlippedView alloc] initWithFrame:NSMakeRect(0, 0, kViewWidth, 10)];
    BOOL available = [self _switchingAvailable];
    CGFloat y = 16;

    if (!available) {
        NSString *text = ([[GSMux defaultMux] isOpen] && [GSGPU isLegacyMachine])
            ? Str(@"RulesUnsupportedLegacy")
            : Str(@"RulesUnsupported");
        y = [self _placeHelp:text in:doc y:y];
    }

    y = [self _placeHeading:Str(@"PowerSourceRules") in:doc y:y];
    _powerSwitchingCheckbox = [self _checkboxWithTitle:Str(@"PrefPowerSwitching") identifier:GSShouldUsePowerSourceBasedSwitchingKey];
    _powerSwitchingCheckbox.action = nil;
    _powerSwitchingCheckbox.target = nil;
    y = [self _placeCheckbox:_powerSwitchingCheckbox in:doc y:y];

    _batteryPopup = [self _modePopupIncludingDontChange:YES];
    _adapterPopup = [self _modePopupIncludingDontChange:YES];
    y = [self _placeLabeled:Str(@"OnBattery") control:_batteryPopup in:doc y:y];
    y = [self _placeLabeled:Str(@"PluggedIn") control:_adapterPopup in:doc y:y];
    y = [self _placeHelp:Str(@"PowerBasedSwitchingHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"AutomaticRules") in:doc y:y];
    y = [self _placeHelp:Str(@"AutomaticRulesHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"PerAppRule") in:doc y:y];
    _perAppCheckbox = [self _checkboxWithTitle:Str(@"PerAppEnabled") identifier:GSPerAppRulesEnabledKey];
    y = [self _placeCheckbox:_perAppCheckbox in:doc y:y];
    _perAppTable = [self _tableWithColumns:@[
        @[ @"name", Str(@"Application"), @230 ],
        @[ @"mode", Str(@"GPUMode"), @150 ],
        @[ @"remove", @"", @70 ]
    ]];
    NSScrollView *perAppScroll = [self _scrollForTable:_perAppTable height:120];
    y = [self _place:perAppScroll in:doc y:y height:120];
    NSButton *addRunning = [NSButton buttonWithTitle:Str(@"AddRunningApp") target:self action:@selector(_showRunningApps:)];
    NSButton *chooseApp = [NSButton buttonWithTitle:Str(@"ChooseApplication") target:self action:@selector(_chooseApplication:)];
    y = [self _placeButtons:@[ addRunning, chooseApp ] in:doc y:y];
    y = [self _placeHelp:Str(@"PerAppHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"BatteryThreshold") in:doc y:y];
    _thresholdCheckbox = [self _checkboxWithTitle:Str(@"BatteryThresholdEnabled") identifier:GSBatteryThresholdEnabledKey];
    y = [self _placeCheckbox:_thresholdCheckbox in:doc y:y];
    _thresholdField = [self _numberFieldWithAction:@selector(_thresholdChanged:) min:1 max:99];
    y = [self _placeLabeled:Str(@"ChargePercent") control:_thresholdField in:doc y:y];
    y = [self _placeHelp:Str(@"BatteryThresholdHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"ExternalDisplay") in:doc y:y];
    _displayCheckbox = [self _checkboxWithTitle:Str(@"DisplayRuleEnabled") identifier:GSDisplayRuleEnabledKey];
    y = [self _placeCheckbox:_displayCheckbox in:doc y:y];
    y = [self _placeHelp:Str(@"DisplayRuleHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"Schedules") in:doc y:y];
    _scheduleCheckbox = [self _checkboxWithTitle:Str(@"SchedulesEnabled") identifier:GSSchedulesEnabledKey];
    y = [self _placeCheckbox:_scheduleCheckbox in:doc y:y];
    _scheduleTable = [self _tableWithColumns:@[
        @[ @"start", Str(@"From"), @100 ],
        @[ @"end", Str(@"Until"), @100 ],
        @[ @"mode", Str(@"GPUMode"), @170 ],
        @[ @"remove", @"", @70 ]
    ]];
    y = [self _place:[self _scrollForTable:_scheduleTable height:110] in:doc y:y height:110];
    NSButton *addSchedule = [NSButton buttonWithTitle:Str(@"AddSchedule") target:self action:@selector(_addSchedule:)];
    y = [self _placeButtons:@[ addSchedule ] in:doc y:y];
    y = [self _placeHelp:Str(@"SchedulesHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"KeyboardShortcuts") in:doc y:y];
    NSArray *shortcutNames = @[ Str(@"IntegratedOnly"), Str(@"DiscreteOnly"), Str(@"DynamicSwitching") ];
    for (NSInteger index = 0; index < 3; index++) {
        _shortcutLabels[index] = [NSTextField labelWithString:Str(@"ShortcutNone")];
        _shortcutButtons[index] = [NSButton buttonWithTitle:Str(@"SetShortcut") target:self action:@selector(_recordShortcut:)];
        _shortcutButtons[index].tag = index;
        NSButton *clear = [NSButton buttonWithTitle:Str(@"ClearShortcut") target:self action:@selector(_clearShortcut:)];
        clear.tag = index;
        y = [self _placeShortcutRow:shortcutNames[index]
                              label:_shortcutLabels[index]
                                set:_shortcutButtons[index]
                              clear:clear
                                 in:doc
                                  y:y];
    }
    y = [self _placeHelp:Str(@"ShortcutsHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"NotificationsSection") in:doc y:y];
    _listsAppsCheckbox = [self _checkboxWithTitle:Str(@"ListGPUApps") identifier:GSNotificationListsGPUAppsKey];
    y = [self _placeCheckbox:_listsAppsCheckbox in:doc y:y];
    y = [self _placeHelp:Str(@"ListGPUAppsHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"LaunchDefault") in:doc y:y];
    _launchCheckbox = [self _checkboxWithTitle:Str(@"LaunchDefaultEnabled") identifier:GSLaunchDefaultEnabledKey];
    y = [self _placeCheckbox:_launchCheckbox in:doc y:y];
    _launchPopup = [self _modePopupIncludingDontChange:YES];
    _launchPopup.identifier = GSLaunchDefaultModeKey;
    _launchPopup.target = self;
    _launchPopup.action = @selector(_modePopupChanged:);
    y = [self _placeLabeled:Str(@"GPUMode") control:_launchPopup in:doc y:y];
    y = [self _placeHelp:Str(@"LaunchDefaultHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"WakeRule") in:doc y:y];
    _wakeCheckbox = [self _checkboxWithTitle:Str(@"WakeRuleEnabled") identifier:GSWakeRuleEnabledKey];
    y = [self _placeCheckbox:_wakeCheckbox in:doc y:y];
    _wakePopup = [self _modePopupIncludingDontChange:YES];
    _wakePopup.identifier = GSWakeModeKey;
    _wakePopup.target = self;
    _wakePopup.action = @selector(_modePopupChanged:);
    y = [self _placeLabeled:Str(@"GPUMode") control:_wakePopup in:doc y:y];
    y = [self _placeHelp:Str(@"WakeRuleHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"PauseSection") in:doc y:y];
    _pauseButton = [NSButton buttonWithTitle:Str(@"PauseAutomaticRules") target:self action:@selector(_pause:)];
    _resumeButton = [NSButton buttonWithTitle:Str(@"ResumeAutomaticRules") target:self action:@selector(_resume:)];
    y = [self _placeButtons:@[ _pauseButton, _resumeButton ] in:doc y:y];
    y = [self _placeHelp:Str(@"PauseHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"MenuBarSection") in:doc y:y];
    _menuBarNameCheckbox = [self _checkboxWithTitle:Str(@"ShowGPUName") identifier:GSMenuBarShowsGPUNameKey];
    y = [self _placeCheckbox:_menuBarNameCheckbox in:doc y:y];
    y = [self _placeHelp:Str(@"ShowGPUNameHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"DiscreteOnBatteryTitle") in:doc y:y];
    _alertCheckbox = [self _checkboxWithTitle:Str(@"DiscreteAlertEnabled") identifier:GSDiscreteOnBatteryAlertEnabledKey];
    y = [self _placeCheckbox:_alertCheckbox in:doc y:y];
    _alertMinutesField = [self _numberFieldWithAction:@selector(_alertMinutesChanged:) min:1 max:1440];
    y = [self _placeLabeled:Str(@"AlertAfterMinutes") control:_alertMinutesField in:doc y:y];
    y = [self _placeHelp:Str(@"DiscreteAlertHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"GPUHistory") in:doc y:y];
    _historyCheckbox = [self _checkboxWithTitle:Str(@"HistoryEnabled") identifier:GSHistoryEnabledKey];
    y = [self _placeCheckbox:_historyCheckbox in:doc y:y];
    y = [self _placeHelp:Str(@"HistoryHelp") in:doc y:y];

    y = [self _placeHeading:Str(@"Profiles") in:doc y:y];
    _profilePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _profilePopup.target = self;
    _profilePopup.action = @selector(_profileChosen:);
    y = [self _placeLabeled:Str(@"ActiveProfile") control:_profilePopup in:doc y:y];
    _profileNameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _profileNameField.placeholderString = Str(@"ProfileNamePlaceholder");
    NSButton *saveProfile = [NSButton buttonWithTitle:Str(@"SaveProfile") target:self action:@selector(_saveProfile:)];
    y = [self _placeField:_profileNameField button:saveProfile in:doc y:y];
    y = [self _placeHelp:Str(@"ProfilesHelp") in:doc y:y];

    doc.frame = NSMakeRect(0, 0, kViewWidth, y + 8);

    [_powerSwitchingCheckbox bind:NSValueBinding toObject:prefs withKeyPath:[self _keyPath:GSShouldUsePowerSourceBasedSwitchingKey] options:nil];
    [_batteryPopup bind:NSSelectedIndexBinding toObject:prefs withKeyPath:[self _keyPath:GSPowerSourceBasedSwitchingBatteryModeKey] options:nil];
    [_adapterPopup bind:NSSelectedIndexBinding toObject:prefs withKeyPath:[self _keyPath:GSPowerSourceBasedSwitchingACModeKey] options:nil];
    _powerSwitchingCheckbox.enabled = available;
    _batteryPopup.enabled = available;
    _adapterPopup.enabled = available;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kViewWidth, 560)];
    scroll.documentView = doc;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    return scroll;
}

- (CGFloat)_placeLabeled:(NSString *)title control:(NSView *)control in:(NSView *)doc y:(CGFloat)y
{
    NSTextField *label = [NSTextField labelWithString:title];
    [label sizeToFit];
    CGFloat row = 26;
    label.frame = NSMakeRect(kMargin, y + 4, 160, NSHeight(label.frame));
    control.frame = NSMakeRect(kMargin + 168, y, kContentWidth - 168, row);
    [doc addSubview:label];
    [doc addSubview:control];
    return y + row + 8;
}

- (CGFloat)_placeButtons:(NSArray<NSButton *> *)buttons in:(NSView *)doc y:(CGFloat)y
{
    CGFloat x = kMargin;
    CGFloat height = 28;
    for (NSButton *button in buttons) {
        [button sizeToFit];
        CGFloat width = MAX(NSWidth(button.frame) + 16, 80);
        button.frame = NSMakeRect(x, y, width, height);
        [doc addSubview:button];
        x += width + 8;
    }
    return y + height + 8;
}

- (CGFloat)_placeField:(NSTextField *)field button:(NSButton *)button in:(NSView *)doc y:(CGFloat)y
{
    [button sizeToFit];
    CGFloat buttonWidth = MAX(NSWidth(button.frame) + 16, 100);
    field.frame = NSMakeRect(kMargin, y, kContentWidth - buttonWidth - 8, 24);
    button.frame = NSMakeRect(kMargin + kContentWidth - buttonWidth, y, buttonWidth, 24);
    [doc addSubview:field];
    [doc addSubview:button];
    return y + 32;
}

- (CGFloat)_placeShortcutRow:(NSString *)title
                       label:(NSTextField *)label
                         set:(NSButton *)setButton
                       clear:(NSButton *)clearButton
                          in:(NSView *)doc
                           y:(CGFloat)y
{
    NSTextField *name = [NSTextField labelWithString:title];
    [name sizeToFit];
    name.frame = NSMakeRect(kMargin, y + 4, 130, NSHeight(name.frame));
    label.frame = NSMakeRect(kMargin + 136, y + 4, 140, NSHeight(label.frame));
    [setButton sizeToFit];
    [clearButton sizeToFit];
    CGFloat setWidth = MAX(NSWidth(setButton.frame) + 12, 90);
    CGFloat clearWidth = MAX(NSWidth(clearButton.frame) + 12, 60);
    setButton.frame = NSMakeRect(kMargin + 280, y, setWidth, 26);
    clearButton.frame = NSMakeRect(kMargin + 288 + setWidth, y, clearWidth, 26);
    [doc addSubview:name];
    [doc addSubview:label];
    [doc addSubview:setButton];
    [doc addSubview:clearButton];
    return y + 32;
}

- (NSTextField *)_numberFieldWithAction:(SEL)action min:(NSInteger)min max:(NSInteger)max
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.allowsFloats = NO;
    formatter.minimum = @(min);
    formatter.maximum = @(max);
    field.formatter = formatter;
    field.target = self;
    field.action = action;
    return field;
}

#pragma mark - Refresh

- (void)_refreshFromPreferences
{
    if (_refreshing || _powerSwitchingCheckbox == nil)
        return;
    _refreshing = YES;
    BOOL available = [self _switchingAvailable];

    _perAppCheckbox.state = [prefs boolForKey:GSPerAppRulesEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _displayCheckbox.state = [prefs boolForKey:GSDisplayRuleEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _thresholdCheckbox.state = [prefs boolForKey:GSBatteryThresholdEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _scheduleCheckbox.state = [prefs boolForKey:GSSchedulesEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _launchCheckbox.state = [prefs boolForKey:GSLaunchDefaultEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _wakeCheckbox.state = [prefs boolForKey:GSWakeRuleEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _listsAppsCheckbox.state = [prefs boolForKey:GSNotificationListsGPUAppsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _menuBarNameCheckbox.state = [prefs boolForKey:GSMenuBarShowsGPUNameKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _historyCheckbox.state = [prefs boolForKey:GSHistoryEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    _alertCheckbox.state = [prefs boolForKey:GSDiscreteOnBatteryAlertEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;

    _thresholdField.integerValue = [prefs integerForKey:GSBatteryThresholdPercentKey fallback:20];
    _alertMinutesField.integerValue = [prefs integerForKey:GSDiscreteOnBatteryAlertMinutesKey fallback:30];
    [_launchPopup selectItemWithTag:[prefs integerForKey:GSLaunchDefaultModeKey fallback:GSPowerSourceBasedSwitchingModeDynamic]];
    [_wakePopup selectItemWithTag:[prefs integerForKey:GSWakeModeKey fallback:GSPowerSourceBasedSwitchingModeDynamic]];

    for (NSControl *control in @[ _perAppCheckbox, _displayCheckbox, _thresholdCheckbox, _thresholdField, _scheduleCheckbox, _launchCheckbox, _launchPopup, _wakeCheckbox, _wakePopup, _listsAppsCheckbox, _alertCheckbox, _alertMinutesField, _profilePopup, _profileNameField, _pauseButton, _resumeButton ])
        control.enabled = available;
    _menuBarNameCheckbox.enabled = YES;
    _historyCheckbox.enabled = YES;

    [_perAppTable reloadData];
    [_scheduleTable reloadData];
    [self _reloadProfilePopup];
    [self _refreshShortcutButtons];

    GSRuleEngine *rules = [GSRuleEngine sharedEngine];
    _pauseButton.enabled = available && !rules.paused;
    _resumeButton.enabled = available && (rules.paused || [GSPowerSourceController sharedController].manualOverrideActive);
    _refreshing = NO;
}

- (void)_reloadProfilePopup
{
    [_profilePopup removeAllItems];
    NSString *active = [prefs activeProfileName];
    NSInteger selected = 0;
    NSInteger index = 0;
    for (NSString *name in [prefs profileNames]) {
        [_profilePopup addItemWithTitle:[prefs displayNameForProfile:name]];
        _profilePopup.lastItem.representedObject = name;
        if ([name isEqualToString:active])
            selected = index;
        index++;
    }
    if (_profilePopup.numberOfItems == 0) {
        [_profilePopup addItemWithTitle:Str(@"NoProfiles")];
        _profilePopup.enabled = NO;
        return;
    }
    [_profilePopup selectItemAtIndex:selected];
}

- (void)_refreshShortcutButtons
{
    NSArray *codeKeys = @[ GSHotkeyIntegratedKeyCodeKey, GSHotkeyDiscreteKeyCodeKey, GSHotkeyDynamicKeyCodeKey ];
    NSArray *labelKeys = @[ GSHotkeyIntegratedLabelKey, GSHotkeyDiscreteLabelKey, GSHotkeyDynamicLabelKey ];
    for (NSInteger index = 0; index < 3; index++) {
        NSString *label = [prefs stringForKey:labelKeys[index]];
        NSInteger code = [prefs integerForKey:codeKeys[index] fallback:-1];
        _shortcutLabels[index].stringValue = (code >= 0 && label.length) ? label : Str(@"ShortcutNone");
        _shortcutButtons[index].title = (_recordingMode == index) ? Str(@"PressShortcut") : Str(@"SetShortcut");
        _shortcutButtons[index].enabled = [self _switchingAvailable];
    }
}

- (void)_rulesEdited
{
    [_perAppTable reloadData];
    [_scheduleTable reloadData];
    [[GSRuleEngine sharedEngine] applyForEvent:GSRuleEventContinuous];
    [[GSRuleEngine sharedEngine] notifyStateChanged];
}

#pragma mark - Actions

- (IBAction)_toggleRule:(id)sender
{
    if (_refreshing || ![sender isKindOfClass:[NSButton class]])
        return;
    NSButton *button = sender;
    NSString *key = button.identifier;
    if (key.length == 0)
        return;
    BOOL on = button.state == NSControlStateValueOn;
    if (![self _switchingAvailable] && ![key isEqualToString:GSMenuBarShowsGPUNameKey] && ![key isEqualToString:GSHistoryEnabledKey])
        return;
    [prefs setBool:on forKey:key];
    if ([key isEqualToString:GSMenuBarShowsGPUNameKey] || [key isEqualToString:GSHistoryEnabledKey])
        [[GSRuleEngine sharedEngine] notifyStateChanged];
    else
        [self _rulesEdited];
}

- (IBAction)_modePopupChanged:(id)sender
{
    if (_refreshing || ![sender isKindOfClass:[NSPopUpButton class]])
        return;
    NSPopUpButton *popup = sender;
    if (popup.identifier.length == 0)
        return;
    [prefs setInteger:popup.selectedTag forKey:popup.identifier];
    [[GSRuleEngine sharedEngine] applyForEvent:GSRuleEventContinuous];
}

- (IBAction)_thresholdChanged:(id)sender
{
    (void)sender;
    if (_refreshing)
        return;
    NSInteger percent = _thresholdField.integerValue;
    if (percent < 1)
        percent = 1;
    if (percent > 99)
        percent = 99;
    [prefs setInteger:percent forKey:GSBatteryThresholdPercentKey];
    [[GSRuleEngine sharedEngine] applyForEvent:GSRuleEventContinuous];
}

- (IBAction)_alertMinutesChanged:(id)sender
{
    (void)sender;
    if (_refreshing)
        return;
    NSInteger minutes = _alertMinutesField.integerValue;
    if (minutes < 1)
        minutes = 1;
    if (minutes > 24 * 60)
        minutes = 24 * 60;
    [prefs setInteger:minutes forKey:GSDiscreteOnBatteryAlertMinutesKey];
}

- (IBAction)_pause:(id)sender
{
    (void)sender;
    [[GSRuleEngine sharedEngine] pauseForOneHour];
}

- (IBAction)_resume:(id)sender
{
    (void)sender;
    [[GSRuleEngine sharedEngine] resumeAutomaticRules];
}

- (IBAction)_profileChosen:(id)sender
{
    (void)sender;
    if (_refreshing)
        return;
    NSString *name = _profilePopup.selectedItem.representedObject;
    if (![name isKindOfClass:[NSString class]] || [name isEqualToString:[prefs activeProfileName]])
        return;
    [[GSRuleEngine sharedEngine] activateProfileNamed:name];
}

- (IBAction)_saveProfile:(id)sender
{
    (void)sender;
    if (![prefs saveNewProfileNamed:_profileNameField.stringValue]) {
        NSBeep();
        return;
    }
    _profileNameField.stringValue = @"";
    [self _refreshFromPreferences];
    [[GSRuleEngine sharedEngine] notifyStateChanged];
}

- (IBAction)_showRunningApps:(id)sender
{
    if (![self _switchingAvailable])
        return;
    NSButton *button = sender;
    NSMenu *menu = [[NSMenu alloc] init];
    NSMutableArray *apps = [NSMutableArray array];
    for (NSRunningApplication *app in [NSWorkspace sharedWorkspace].runningApplications) {
        if (app.activationPolicy != NSApplicationActivationPolicyRegular)
            continue;
        if (app.bundleIdentifier.length == 0)
            continue;
        [apps addObject:app];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSRunningApplication *a, NSRunningApplication *b) {
        return [a.localizedName ?: a.bundleIdentifier compare:b.localizedName ?: b.bundleIdentifier];
    }];
    if (apps.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:Str(@"NoRunningApps") action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    }
    for (NSRunningApplication *app in apps) {
        NSString *title = app.localizedName.length ? app.localizedName : app.bundleIdentifier;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(_addAppFromMenu:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = @{ @"bundleID": app.bundleIdentifier, @"name": title };
        [menu addItem:item];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(button.bounds) + 4) inView:button];
}

- (IBAction)_addAppFromMenu:(id)sender
{
    NSDictionary *info = [sender representedObject];
    if (![info isKindOfClass:[NSDictionary class]])
        return;
    [self _addAppWithBundleID:info[@"bundleID"] name:info[@"name"]];
}

- (IBAction)_chooseApplication:(id)sender
{
    (void)sender;
    if (![self _switchingAvailable])
        return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    UTType *applicationType = [UTType typeWithIdentifier:@"com.apple.application-bundle"];
    if (applicationType)
        panel.allowedContentTypes = @[ applicationType ];
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK)
            return;
        NSBundle *bundle = [NSBundle bundleWithURL:panel.URL];
        NSString *bundleID = bundle.bundleIdentifier;
        if (bundleID.length == 0) {
            NSBeep();
            return;
        }
        NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if (name.length == 0)
            name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
        if (name.length == 0)
            name = panel.URL.lastPathComponent;
        [self _addAppWithBundleID:bundleID name:name];
    }];
}

- (void)_addAppWithBundleID:(NSString *)bundleID name:(NSString *)name
{
    if (bundleID.length == 0)
        return;
    NSMutableArray *rules = [[prefs arrayForKey:GSPerAppRulesKey] mutableCopy];
    for (NSDictionary *rule in rules) {
        if ([rule[@"bundleID"] isEqualToString:bundleID])
            return;
    }
    [rules addObject:@{
        @"bundleID": bundleID,
        @"name": name ?: bundleID,
        @"mode": @(GSPowerSourceBasedSwitchingModeDiscrete)
    }];
    [prefs setArray:rules forKey:GSPerAppRulesKey];
    [self _rulesEdited];
}

- (IBAction)_addSchedule:(id)sender
{
    (void)sender;
    if (![self _switchingAvailable])
        return;
    NSMutableArray *slots = [[prefs arrayForKey:GSSchedulesKey] mutableCopy];
    [slots addObject:@{
        @"start": @(9 * 60),
        @"end": @(17 * 60),
        @"mode": @(GSPowerSourceBasedSwitchingModeDynamic)
    }];
    [prefs setArray:slots forKey:GSSchedulesKey];
    [self _rulesEdited];
}

- (IBAction)_removePerApp:(id)sender
{
    [self _removeRow:[sender tag] fromKey:GSPerAppRulesKey];
}

- (IBAction)_removeSchedule:(id)sender
{
    [self _removeRow:[sender tag] fromKey:GSSchedulesKey];
}

- (void)_removeRow:(NSInteger)row fromKey:(NSString *)key
{
    if (_refreshing || ![self _switchingAvailable])
        return;
    NSMutableArray *entries = [[prefs arrayForKey:key] mutableCopy];
    if (row < 0 || (NSUInteger)row >= entries.count)
        return;
    [entries removeObjectAtIndex:(NSUInteger)row];
    [prefs setArray:entries forKey:key];
    [self _rulesEdited];
}

- (IBAction)_perAppModeChanged:(id)sender
{
    [self _updateRow:[sender tag] key:GSPerAppRulesKey field:@"mode" value:@([sender selectedTag])];
}

- (IBAction)_scheduleModeChanged:(id)sender
{
    [self _updateRow:[sender tag] key:GSSchedulesKey field:@"mode" value:@([sender selectedTag])];
}

- (IBAction)_scheduleStartChanged:(id)sender
{
    [self _updateRow:[sender tag] key:GSSchedulesKey field:@"start" value:@([sender selectedTag] * 60)];
}

- (IBAction)_scheduleEndChanged:(id)sender
{
    [self _updateRow:[sender tag] key:GSSchedulesKey field:@"end" value:@([sender selectedTag] * 60)];
}

- (void)_updateRow:(NSInteger)row key:(NSString *)key field:(NSString *)field value:(id)value
{
    if (_refreshing || ![self _switchingAvailable])
        return;
    NSMutableArray *entries = [[prefs arrayForKey:key] mutableCopy];
    if (row < 0 || (NSUInteger)row >= entries.count)
        return;
    NSMutableDictionary *entry = [entries[(NSUInteger)row] mutableCopy];
    entry[field] = value;
    entries[(NSUInteger)row] = entry;
    [prefs setArray:entries forKey:key];
    [self _rulesEdited];
}

#pragma mark - Shortcuts

- (IBAction)_recordShortcut:(id)sender
{
    if (![self _switchingAvailable])
        return;
    NSInteger mode = [sender tag];
    [self _endRecording];
    _recordingMode = mode;
    NSWindow *window = self.view.window;
    if (window) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_endRecording)
                                                     name:NSWindowWillCloseNotification
                                                   object:window];
        _recordingWindow = window;
    }
    __weak AdvancedPreferencesViewController *weakSelf = self;
    _shortcutMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        AdvancedPreferencesViewController *strongSelf = weakSelf;
        if (!strongSelf)
            return event;
        return [strongSelf _handleRecordingEvent:event];
    }];
    [self _refreshShortcutButtons];
}

- (NSEvent *)_handleRecordingEvent:(NSEvent *)event
{
    if (_recordingMode < 0)
        return event;
    if (event.keyCode == 53) {
        [self _endRecording];
        return nil;
    }
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
    if (mods == 0) {
        NSBeep();
        return nil;
    }
    [self _storeShortcutForMode:_recordingMode event:event modifiers:mods];
    [self _endRecording];
    return nil;
}

- (void)_storeShortcutForMode:(NSInteger)mode event:(NSEvent *)event modifiers:(NSEventModifierFlags)modifiers
{
    NSArray *codeKeys = @[ GSHotkeyIntegratedKeyCodeKey, GSHotkeyDiscreteKeyCodeKey, GSHotkeyDynamicKeyCodeKey ];
    NSArray *modKeys = @[ GSHotkeyIntegratedModifiersKey, GSHotkeyDiscreteModifiersKey, GSHotkeyDynamicModifiersKey ];
    NSArray *labelKeys = @[ GSHotkeyIntegratedLabelKey, GSHotkeyDiscreteLabelKey, GSHotkeyDynamicLabelKey ];
    if (mode < 0 || mode > 2)
        return;
    [prefs setInteger:event.keyCode forKey:codeKeys[mode]];
    [prefs setInteger:(NSInteger)modifiers forKey:modKeys[mode]];
    [prefs setString:[self _shortcutLabelForEvent:event modifiers:modifiers] forKey:labelKeys[mode]];
    [[GSRuleEngine sharedEngine] reloadHotKeys];
    [self _refreshShortcutButtons];
}

- (NSString *)_shortcutLabelForEvent:(NSEvent *)event modifiers:(NSEventModifierFlags)modifiers
{
    NSMutableString *label = [NSMutableString string];
    if (modifiers & NSEventModifierFlagControl)
        [label appendString:@"⌃"];
    if (modifiers & NSEventModifierFlagOption)
        [label appendString:@"⌥"];
    if (modifiers & NSEventModifierFlagShift)
        [label appendString:@"⇧"];
    if (modifiers & NSEventModifierFlagCommand)
        [label appendString:@"⌘"];

    NSString *key = nil;
    switch (event.keyCode) {
        case 36: key = @"↩"; break;
        case 48: key = @"⇥"; break;
        case 49: key = @"Space"; break;
        case 51: key = @"⌫"; break;
        case 123: key = @"←"; break;
        case 124: key = @"→"; break;
        case 125: key = @"↓"; break;
        case 126: key = @"↑"; break;
        default: break;
    }
    if (!key) {
        NSString *chars = event.charactersIgnoringModifiers;
        if (chars.length == 1)
            key = chars.uppercaseString;
        else
            key = [NSString stringWithFormat:@"%d", (int)event.keyCode];
    }
    [label appendString:key ?: @""];
    return label;
}

- (IBAction)_clearShortcut:(id)sender
{
    NSInteger mode = [sender tag];
    NSArray *codeKeys = @[ GSHotkeyIntegratedKeyCodeKey, GSHotkeyDiscreteKeyCodeKey, GSHotkeyDynamicKeyCodeKey ];
    NSArray *modKeys = @[ GSHotkeyIntegratedModifiersKey, GSHotkeyDiscreteModifiersKey, GSHotkeyDynamicModifiersKey ];
    NSArray *labelKeys = @[ GSHotkeyIntegratedLabelKey, GSHotkeyDiscreteLabelKey, GSHotkeyDynamicLabelKey ];
    if (mode < 0 || mode > 2)
        return;
    [prefs setInteger:-1 forKey:codeKeys[mode]];
    [prefs setInteger:0 forKey:modKeys[mode]];
    [prefs setString:@"" forKey:labelKeys[mode]];
    [[GSRuleEngine sharedEngine] reloadHotKeys];
    [self _refreshShortcutButtons];
}

- (void)_endRecording
{
    if (_shortcutMonitor) {
        [NSEvent removeMonitor:_shortcutMonitor];
        _shortcutMonitor = nil;
    }
    if (_recordingWindow) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:_recordingWindow];
        _recordingWindow = nil;
    }
    _recordingMode = -1;
    if (_shortcutButtons[0])
        [self _refreshShortcutButtons];
}

#pragma mark - NSTableView

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == _perAppTable)
        return (NSInteger)[prefs arrayForKey:GSPerAppRulesKey].count;
    if (tableView == _scheduleTable)
        return (NSInteger)[prefs arrayForKey:GSSchedulesKey].count;
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    if (tableView == _perAppTable)
        return [self _perAppViewForColumn:column.identifier row:row];
    if (tableView == _scheduleTable)
        return [self _scheduleViewForColumn:column.identifier row:row];
    return nil;
}

- (NSView *)_perAppViewForColumn:(NSString *)identifier row:(NSInteger)row
{
    NSArray *rules = [prefs arrayForKey:GSPerAppRulesKey];
    if (row < 0 || (NSUInteger)row >= rules.count)
        return nil;
    NSDictionary *rule = rules[(NSUInteger)row];
    if ([identifier isEqualToString:@"name"])
        return [self _label:rule[@"name"] ?: rule[@"bundleID"] identifier:@"perAppName" table:_perAppTable];
    if ([identifier isEqualToString:@"mode"]) {
        NSPopUpButton *popup = [self _smallModePopupIncludingDontChange:NO identifier:@"perAppMode" action:@selector(_perAppModeChanged:)];
        popup.tag = row;
        [popup selectItemWithTag:[rule[@"mode"] integerValue]];
        return popup;
    }
    return [self _removeButtonWithAction:@selector(_removePerApp:) row:row identifier:@"perAppRemove"];
}

- (NSView *)_scheduleViewForColumn:(NSString *)identifier row:(NSInteger)row
{
    NSArray *slots = [prefs arrayForKey:GSSchedulesKey];
    if (row < 0 || (NSUInteger)row >= slots.count)
        return nil;
    NSDictionary *slot = slots[(NSUInteger)row];
    if ([identifier isEqualToString:@"start"] || [identifier isEqualToString:@"end"]) {
        SEL action = [identifier isEqualToString:@"start"] ? @selector(_scheduleStartChanged:) : @selector(_scheduleEndChanged:);
        NSPopUpButton *popup = [self _hourPopupWithIdentifier:identifier action:action];
        popup.tag = row;
        NSInteger minute = [slot[identifier] integerValue];
        [popup selectItemWithTag:minute / 60];
        return popup;
    }
    if ([identifier isEqualToString:@"mode"]) {
        NSPopUpButton *popup = [self _smallModePopupIncludingDontChange:NO identifier:@"scheduleMode" action:@selector(_scheduleModeChanged:)];
        popup.tag = row;
        [popup selectItemWithTag:[slot[@"mode"] integerValue]];
        return popup;
    }
    return [self _removeButtonWithAction:@selector(_removeSchedule:) row:row identifier:@"scheduleRemove"];
}

- (NSTextField *)_label:(NSString *)text identifier:(NSString *)identifier table:(NSTableView *)table
{
    NSTextField *field = (NSTextField *)[table makeViewWithIdentifier:identifier owner:self];
    if (![field isKindOfClass:[NSTextField class]]) {
        field = [NSTextField labelWithString:@""];
        field.identifier = identifier;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    field.stringValue = text ?: @"";
    return field;
}

- (NSPopUpButton *)_smallModePopupIncludingDontChange:(BOOL)include identifier:(NSString *)identifier action:(SEL)action
{
    NSPopUpButton *popup = (NSPopUpButton *)[_perAppTable makeViewWithIdentifier:identifier owner:self];
    if (![popup isKindOfClass:[NSPopUpButton class]] && _scheduleTable)
        popup = (NSPopUpButton *)[_scheduleTable makeViewWithIdentifier:identifier owner:self];
    if (![popup isKindOfClass:[NSPopUpButton class]]) {
        popup = [self _modePopupIncludingDontChange:include];
        popup.identifier = identifier;
        popup.controlSize = NSControlSizeSmall;
        popup.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    }
    popup.target = self;
    popup.action = action;
    return popup;
}

- (NSPopUpButton *)_hourPopupWithIdentifier:(NSString *)identifier action:(SEL)action
{
    NSPopUpButton *popup = (NSPopUpButton *)[_scheduleTable makeViewWithIdentifier:identifier owner:self];
    if (![popup isKindOfClass:[NSPopUpButton class]] || popup.numberOfItems != 24) {
        popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        popup.identifier = identifier;
        popup.controlSize = NSControlSizeSmall;
        popup.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        for (NSInteger hour = 0; hour < 24; hour++) {
            [popup addItemWithTitle:[NSString stringWithFormat:@"%ld:00", (long)hour]];
            popup.lastItem.tag = hour;
        }
    }
    popup.target = self;
    popup.action = action;
    return popup;
}

- (NSButton *)_removeButtonWithAction:(SEL)action row:(NSInteger)row identifier:(NSString *)identifier
{
    NSButton *button = (NSButton *)[_perAppTable makeViewWithIdentifier:identifier owner:self];
    if (![button isKindOfClass:[NSButton class]])
        button = (NSButton *)[_scheduleTable makeViewWithIdentifier:identifier owner:self];
    if (![button isKindOfClass:[NSButton class]]) {
        button = [NSButton buttonWithTitle:Str(@"Remove") target:self action:action];
        button.identifier = identifier;
        button.bezelStyle = NSBezelStyleRounded;
        button.controlSize = NSControlSizeSmall;
        button.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    }
    button.target = self;
    button.action = action;
    button.tag = row;
    button.enabled = [self _switchingAvailable];
    return button;
}

@end
