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

@implementation AdvancedPreferencesViewController {
    NSButton *_powerSwitchingCheckbox;
    NSPopUpButton *_batteryPopup;
    NSPopUpButton *_adapterPopup;
}

@synthesize prefs;

#pragma mark - Initializers

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    // The pane is built in code so the controls can be enabled or disabled
    // from whether this Mac can actually switch, and so localized strings
    // can size the window. The xib is not loaded.
    // The nib name is intentionally ignored.
    (void)nibNameOrNil;
    (void)nibBundleOrNil;
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;

    prefs = [GSPreferences sharedInstance];
    return self;
}

- (void)dealloc
{
    [_powerSwitchingCheckbox unbind:NSValueBinding];
    [_batteryPopup unbind:NSSelectedIndexBinding];
    [_adapterPopup unbind:NSSelectedIndexBinding];
}

- (void)loadView
{
    self.view = [self _buildView];
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

#pragma mark - View

- (BOOL)_powerSwitchingAvailable
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
    if (height > 220)
        height = 220;
    return height;
}

- (NSPopUpButton *)_modePopup
{
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray *choices = @[
        @[ @"IntegratedOnly", @(GSPowerSourceBasedSwitchingModeIntegrated) ],
        @[ @"DiscreteOnly", @(GSPowerSourceBasedSwitchingModeDiscrete) ],
        @[ @"DynamicSwitching", @(GSPowerSourceBasedSwitchingModeDynamic) ],
        @[ @"DontChange", @(GSPowerSourceBasedSwitchingModeDontChange) ]
    ];
    for (NSArray *choice in choices) {
        [popup addItemWithTitle:Str(choice[0])];
        popup.lastItem.tag = [choice[1] integerValue];
    }
    return popup;
}

- (NSString *)_keyPath:(NSString *)key
{
    return [@"prefsDict." stringByAppendingString:key];
}

- (NSView *)_buildView
{
    BOOL available = [self _powerSwitchingAvailable];
    static const CGFloat margin = 20;
    static const CGFloat gap = 12;
    static const CGFloat rowHeight = 26;
    static const CGFloat labelGap = 8;

    NSButton *checkbox = [NSButton checkboxWithTitle:Str(@"PrefPowerSwitching") target:nil action:nil];
    [checkbox sizeToFit];

    NSTextField *batteryLabel = [NSTextField labelWithString:Str(@"OnBattery")];
    NSTextField *adapterLabel = [NSTextField labelWithString:Str(@"PluggedIn")];
    [batteryLabel sizeToFit];
    [adapterLabel sizeToFit];
    batteryLabel.alignment = NSTextAlignmentRight;
    adapterLabel.alignment = NSTextAlignmentRight;

    NSPopUpButton *batteryPopup = [self _modePopup];
    NSPopUpButton *adapterPopup = [self _modePopup];

    CGFloat labelWidth = MAX(NSWidth(batteryLabel.frame), NSWidth(adapterLabel.frame));
    CGFloat popupWidth = 230;
    CGFloat width = MAX(460, margin + labelWidth + labelGap + popupWidth + margin);
    width = MAX(width, NSWidth(checkbox.frame) + margin * 2);
    width = MIN(width, 640);
    CGFloat textWidth = width - margin * 2;
    CGFloat fittedPopupWidth = textWidth - labelWidth - labelGap;
    if (fittedPopupWidth < 160) {
        labelWidth = MAX(80, textWidth - labelGap - 160);
        fittedPopupWidth = textWidth - labelWidth - labelGap;
    }

    NSString *unsupportedText = nil;
    if (!available) {
        if ([[GSMux defaultMux] isOpen] && [GSGPU isLegacyMachine])
            unsupportedText = Str(@"PowerSwitchingUnsupportedLegacy");
        else
            unsupportedText = Str(@"PowerSwitchingUnsupported");
    }

    NSTextField *help = [self _wrappingFieldWithString:Str(@"PowerBasedSwitchingHelp")];
    NSTextField *unsupported = unsupportedText ? [self _wrappingFieldWithString:unsupportedText] : nil;
    if (unsupported)
        unsupported.textColor = [NSColor labelColor];

    CGFloat helpHeight = [self _heightForField:help width:textWidth];
    CGFloat unsupportedHeight = unsupported ? [self _heightForField:unsupported width:textWidth] : 0;
    CGFloat checkboxHeight = MAX(NSHeight(checkbox.frame), 18);

    CGFloat height = margin + checkboxHeight + gap + rowHeight + gap + rowHeight + gap + helpHeight + margin;
    if (unsupported)
        height += gap + unsupportedHeight;

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];

    CGFloat y = height - margin - checkboxHeight;
    checkbox.frame = NSMakeRect(margin, y, textWidth, checkboxHeight);
    checkbox.enabled = available;

    y -= gap + rowHeight;
    [self _placeLabel:batteryLabel popup:batteryPopup y:y labelWidth:labelWidth popupWidth:fittedPopupWidth rowHeight:rowHeight];
    y -= gap + rowHeight;
    [self _placeLabel:adapterLabel popup:adapterPopup y:y labelWidth:labelWidth popupWidth:fittedPopupWidth rowHeight:rowHeight];

    batteryPopup.enabled = available;
    adapterPopup.enabled = available;

    y -= gap + helpHeight;
    help.frame = NSMakeRect(margin, y, textWidth, helpHeight);

    if (unsupported) {
        y -= gap + unsupportedHeight;
        unsupported.frame = NSMakeRect(margin, y, textWidth, unsupportedHeight);
        [view addSubview:unsupported];
    }

    [view addSubview:checkbox];
    [view addSubview:batteryLabel];
    [view addSubview:batteryPopup];
    [view addSubview:adapterLabel];
    [view addSubview:adapterPopup];
    [view addSubview:help];

    [checkbox bind:NSValueBinding
          toObject:prefs
       withKeyPath:[self _keyPath:GSShouldUsePowerSourceBasedSwitchingKey]
           options:nil];
    // Item order matches GSPowerSourceBasedSwitchingMode, so the selected
    // index is the stored integer. Index 0 is a real selection (Integrated).
    [batteryPopup bind:NSSelectedIndexBinding
              toObject:prefs
           withKeyPath:[self _keyPath:GSPowerSourceBasedSwitchingBatteryModeKey]
               options:nil];
    [adapterPopup bind:NSSelectedIndexBinding
              toObject:prefs
           withKeyPath:[self _keyPath:GSPowerSourceBasedSwitchingACModeKey]
               options:nil];

    _powerSwitchingCheckbox = checkbox;
    _batteryPopup = batteryPopup;
    _adapterPopup = adapterPopup;
    return view;
}

- (void)_placeLabel:(NSTextField *)label
             popup:(NSPopUpButton *)popup
                  y:(CGFloat)y
         labelWidth:(CGFloat)labelWidth
         popupWidth:(CGFloat)popupWidth
          rowHeight:(CGFloat)rowHeight
{
    static const CGFloat margin = 20;
    static const CGFloat labelGap = 8;
    CGFloat labelHeight = NSHeight(label.frame);
    CGFloat labelY = y + (rowHeight - labelHeight) / 2.0;
    label.frame = NSMakeRect(margin, labelY, labelWidth, labelHeight);
    popup.frame = NSMakeRect(margin + labelWidth + labelGap, y, popupWidth, rowHeight);
}

@end
