// SPDX-License-Identifier: GPL-3.0-or-later
// Mac OS X Cocoa / AppKit Widget Gallery for Darling Embedded (built from
// source in this repository). Showcases the GUI widgets implemented in the
// in-tree AppKit layer (X11 + Cairo):
//   - NSWindow (Aqua titlebar, traffic lights) & titled NSBox containers
//   - NSButton: Rounded Aqua, tinted, disabled, checkbox, radio, disclosure
//   - NSSegmentedControl: multi-segment selector bar
//   - NSSlider: interactive horizontal track + knob
//   - NSProgressIndicator: determinate bar, indeterminate bar, spinning gear
//   - NSTextField (labels & bezeled input), NSTextView + NSTextStorage
//   - NSImageView (.icns PNG decoding), NSColor swatches, NSFont styles

#include <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>

@interface SwatchStripView : NSView
@end

@implementation SwatchStripView

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSColor* colors[6] = {
      [NSColor blueColor],   [NSColor greenColor],  [NSColor orangeColor],
      [NSColor yellowColor], [NSColor redColor],    [NSColor cyanColor],
  };
  const char* names[6] = {"Blue", "Green", "Orange", "Yellow", "Red", "Cyan"};
  for (int i = 0; i < 6; ++i) {
    NSRect r = NSMakeRect(i * 52.0, 2.0, 46.0, 22.0);
    [colors[i] setFill];
    [NSBezierPath fillRoundedRect:r xRadius:5.0 yRadius:5.0];
    [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.25]
        setStroke];
    [NSBezierPath strokeRoundedRect:r xRadius:5.0 yRadius:5.0 lineWidth:1.0];
    NSColor* tc = (i == 3) ? [NSColor blackColor] : [NSColor whiteColor];
    [NSBezierPath drawText:[NSString stringWithUTF8String:names[i]]
                    inRect:r
                      font:[NSFont boldSystemFontOfSize:10.0]
                     color:tc
                 alignment:NSTextAlignmentCenter];
  }
}

@end

@interface WidgetGalleryDelegate : NSObject {
  NSWindow* _window;
  NSSegmentedControl* _segControl;
  NSButton* _primaryBtn;
  NSButton* _disclosureBtn;
  NSTextField* _disclosureLabel;
  NSButton* _radioAqua;
  NSButton* _radioGraphite;
  NSButton* _radioContrast;
  NSSlider* _slider;
  NSProgressIndicator* _detProgress;
  NSProgressIndicator* _indetProgress;
  NSProgressIndicator* _spinner;
  NSTextField* _progressLabel;
  NSTextField* _bezelField;
  NSTextView* _logView;
  int _actionCount;
}
- (void)applicationDidFinishLaunching:(id)notification;
- (void)appendLog:(NSString*)line;
- (void)onSegmentChanged:(id)sender;
- (void)onPrimaryClicked:(id)sender;
- (void)onSecondaryClicked:(id)sender;
- (void)onDestructiveClicked:(id)sender;
- (void)onDisclosureClicked:(id)sender;
- (void)onCheckboxClicked:(id)sender;
- (void)onRadioClicked:(id)sender;
- (void)onSliderChanged:(id)sender;
- (void)onStepProgress:(id)sender;
- (void)onQuitClicked:(id)sender;
@end

@implementation WidgetGalleryDelegate

- (void)appendLog:(NSString*)line {
  if (!_logView) return;
  _actionCount++;
  NSString* entry = [NSString
      stringWithFormat:@"[#%d] %@\n", _actionCount, line ? line : @""];
  [[_logView textStorage]
      replaceCharactersInRange:NSMakeRange([[_logView textStorage] length], 0)
                    withString:entry];
  [_logView
      scrollRangeToVisible:NSMakeRange([[_logView textStorage] length], 0)];
}

- (void)applicationDidFinishLaunching:(id)notification {
  (void)notification;
  _actionCount = 0;

  _window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(140.0, 56.0, 720.0, 520.0)
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [_window setTitle:@"Mac OS X Widget Gallery - Darling AppKit"];
  [_window setBackgroundColor:[NSColor colorWithCalibratedRed:0.93
                                                        green:0.94
                                                         blue:0.96
                                                        alpha:1.0]];

  NSView* content = [_window contentView];

  // -------------------------------------------------------------------------
  // Header bar: .icns NSImageView + Title/Subtitle + NSSegmentedControl
  // -------------------------------------------------------------------------
  NSView* header =
      [[NSView alloc] initWithFrame:NSMakeRect(14.0, 10.0, 692.0, 54.0)];
  [header setBackgroundColor:[NSColor whiteColor]];
  [content addSubview:header];

  NSImageView* iconView =
      [[NSImageView alloc] initWithFrame:NSMakeRect(10.0, 5.0, 44.0, 44.0)];
  [iconView loadImageFromIcnsFile:
                @"/Applications/FastDMG.app/Contents/Resources/fastdmg.icns"];
  [header addSubview:iconView];

  NSTextField* hdrTitle =
      [[NSTextField alloc] initWithFrame:NSMakeRect(62.0, 6.0, 380.0, 22.0)];
  [hdrTitle setFont:[NSFont boldSystemFontOfSize:15.0]];
  [hdrTitle setTextColor:[NSColor labelColor]];
  [hdrTitle setStringValue:@"Darling AppKit - Mac OS X Widget Gallery"];
  [header addSubview:hdrTitle];

  NSTextField* hdrSub =
      [[NSTextField alloc] initWithFrame:NSMakeRect(62.0, 28.0, 385.0, 20.0)];
  [hdrSub setFont:[NSFont systemFontOfSize:11.0]];
  [hdrSub setTextColor:[NSColor darkGrayColor]];
  [hdrSub setStringValue:
              @"Cocoa GUI widgets rendered via X11 + Cairo on Darwin 25.5.0"];
  [header addSubview:hdrSub];

  _segControl = [[NSSegmentedControl alloc]
      initWithFrame:NSMakeRect(452.0, 13.0, 228.0, 28.0)];
  [_segControl setSegmentCount:3];
  [_segControl setLabel:@"Aqua" forSegment:0];
  [_segControl setLabel:@"Controls" forSegment:1];
  [_segControl setLabel:@"Metrics" forSegment:2];
  [_segControl setSelectedSegment:0];
  [_segControl setTarget:self];
  [_segControl setAction:@selector(onSegmentChanged:)];
  [header addSubview:_segControl];

  // -------------------------------------------------------------------------
  // Panel 1 (Top-Left): Push Buttons & Bezel Styles (NSButton)
  // -------------------------------------------------------------------------
  NSBox* boxButtons =
      [[NSBox alloc] initWithFrame:NSMakeRect(14.0, 74.0, 340.0, 204.0)];
  [boxButtons setTitle:@"1. Push Buttons & Bezel Styles (NSButton)"];
  [content addSubview:boxButtons];

  _primaryBtn = [NSButton buttonWithTitle:@"Primary Aqua"
                                   target:self
                                   action:@selector(onPrimaryClicked:)];
  [_primaryBtn setFrame:NSMakeRect(14.0, 30.0, 148.0, 32.0)];
  [boxButtons addSubview:_primaryBtn];

  NSButton* secBtn = [NSButton buttonWithTitle:@"Secondary"
                                        target:self
                                        action:@selector(onSecondaryClicked:)];
  [secBtn setFrame:NSMakeRect(174.0, 30.0, 150.0, 32.0)];
  [secBtn setTintColor:[NSColor colorWithCalibratedRed:0.86
                                                 green:0.87
                                                  blue:0.90
                                                 alpha:1.0]];
  [boxButtons addSubview:secBtn];

  NSButton* destBtn =
      [NSButton buttonWithTitle:@"Destructive"
                         target:self
                         action:@selector(onDestructiveClicked:)];
  [destBtn setFrame:NSMakeRect(14.0, 72.0, 148.0, 32.0)];
  [destBtn setTintColor:[NSColor redColor]];
  [boxButtons addSubview:destBtn];

  NSButton* disBtn = [NSButton buttonWithTitle:@"Disabled"
                                        target:nil
                                        action:nullptr];
  [disBtn setFrame:NSMakeRect(174.0, 72.0, 150.0, 32.0)];
  [disBtn setEnabled:NO];
  [boxButtons addSubview:disBtn];

  _disclosureBtn =
      [[NSButton alloc] initWithFrame:NSMakeRect(16.0, 118.0, 24.0, 24.0)];
  [_disclosureBtn setTitle:@"Disclosure"];
  [_disclosureBtn setBezelStyle:NSBezelStyleDisclosure];
  [_disclosureBtn setButtonType:NSButtonTypePushOnPushOff];
  [_disclosureBtn setState:1];
  [_disclosureBtn setTarget:self];
  [_disclosureBtn setAction:@selector(onDisclosureClicked:)];
  [boxButtons addSubview:_disclosureBtn];

  _disclosureLabel = [[NSTextField alloc]
      initWithFrame:NSMakeRect(44.0, 120.0, 285.0, 20.0)];
  [_disclosureLabel setFont:[NSFont systemFontOfSize:11.5]];
  [_disclosureLabel setTextColor:[NSColor labelColor]];
  [_disclosureLabel
      setStringValue:@"Disclosure Chevron: Expanded (Bezel 5)"];
  [boxButtons addSubview:_disclosureLabel];

  NSTextField* swatchCaption = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 148.0, 310.0, 18.0)];
  [swatchCaption setFont:[NSFont systemFontOfSize:11.0]];
  [swatchCaption setTextColor:[NSColor darkGrayColor]];
  [swatchCaption setStringValue:@"NSColor + NSBezierPath System Swatches:"];
  [boxButtons addSubview:swatchCaption];

  SwatchStripView* swatches = [[SwatchStripView alloc]
      initWithFrame:NSMakeRect(14.0, 168.0, 312.0, 26.0)];
  [boxButtons addSubview:swatches];

  // -------------------------------------------------------------------------
  // Panel 2 (Top-Right): Checkboxes & Radio Buttons (NSButton)
  // -------------------------------------------------------------------------
  NSBox* boxToggles =
      [[NSBox alloc] initWithFrame:NSMakeRect(366.0, 74.0, 340.0, 204.0)];
  [boxToggles setTitle:@"2. Checkboxes & Radio Group (NSButton)"];
  [content addSubview:boxToggles];

  NSButton* cb1 =
      [[NSButton alloc] initWithFrame:NSMakeRect(14.0, 28.0, 310.0, 22.0)];
  [cb1 setButtonType:NSButtonTypeSwitch];
  [cb1 setTitle:@"Enable Cairo Antialiased Rendering"];
  [cb1 setState:1];
  [cb1 setTarget:self];
  [cb1 setAction:@selector(onCheckboxClicked:)];
  [boxToggles addSubview:cb1];

  NSButton* cb2 =
      [[NSButton alloc] initWithFrame:NSMakeRect(14.0, 54.0, 310.0, 22.0)];
  [cb2 setButtonType:NSButtonTypeSwitch];
  [cb2 setTitle:@"Show Mac OS X Aqua Traffic Lights"];
  [cb2 setState:1];
  [cb2 setTarget:self];
  [cb2 setAction:@selector(onCheckboxClicked:)];
  [boxToggles addSubview:cb2];

  NSButton* cb3 =
      [[NSButton alloc] initWithFrame:NSMakeRect(14.0, 80.0, 310.0, 22.0)];
  [cb3 setButtonType:NSButtonTypeSwitch];
  [cb3 setTitle:@"Use Dark Window Appearance"];
  [cb3 setState:0];
  [cb3 setTarget:self];
  [cb3 setAction:@selector(onCheckboxClicked:)];
  [boxToggles addSubview:cb3];

  NSTextField* radioHdr = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 108.0, 310.0, 18.0)];
  [radioHdr setFont:[NSFont boldSystemFontOfSize:11.5]];
  [radioHdr setTextColor:[NSColor darkGrayColor]];
  [radioHdr setStringValue:@"Radio Group (NSButtonTypeRadio):"];
  [boxToggles addSubview:radioHdr];

  _radioAqua =
      [[NSButton alloc] initWithFrame:NSMakeRect(14.0, 128.0, 310.0, 22.0)];
  [_radioAqua setButtonType:NSButtonTypeRadio];
  [_radioAqua setTitle:@"Aqua Blue (Default macOS Accent)"];
  [_radioAqua setState:1];
  [_radioAqua setTarget:self];
  [_radioAqua setAction:@selector(onRadioClicked:)];
  [boxToggles addSubview:_radioAqua];

  _radioGraphite =
      [[NSButton alloc] initWithFrame:NSMakeRect(14.0, 152.0, 310.0, 22.0)];
  [_radioGraphite setButtonType:NSButtonTypeRadio];
  [_radioGraphite setTitle:@"Graphite Accent"];
  [_radioGraphite setState:0];
  [_radioGraphite setTarget:self];
  [_radioGraphite setAction:@selector(onRadioClicked:)];
  [boxToggles addSubview:_radioGraphite];

  _radioContrast =
      [[NSButton alloc] initWithFrame:NSMakeRect(14.0, 176.0, 310.0, 22.0)];
  [_radioContrast setButtonType:NSButtonTypeRadio];
  [_radioContrast setTitle:@"High Contrast Warm Accent"];
  [_radioContrast setState:0];
  [_radioContrast setTarget:self];
  [_radioContrast setAction:@selector(onRadioClicked:)];
  [boxToggles addSubview:_radioContrast];

  // -------------------------------------------------------------------------
  // Panel 3 (Bottom-Left): NSSlider & NSProgressIndicator
  // -------------------------------------------------------------------------
  NSBox* boxProgress =
      [[NSBox alloc] initWithFrame:NSMakeRect(14.0, 288.0, 340.0, 218.0)];
  [boxProgress setTitle:@"3. Sliders & Progress (NSSlider / NSProgress)"];
  [content addSubview:boxProgress];

  _progressLabel = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 28.0, 210.0, 20.0)];
  [_progressLabel setFont:[NSFont boldSystemFontOfSize:12.0]];
  [_progressLabel setTextColor:[NSColor labelColor]];
  [_progressLabel setStringValue:@"Determinate Value: 65%"];
  [boxProgress addSubview:_progressLabel];

  NSButton* stepBtn = [NSButton buttonWithTitle:@"Step +15%"
                                         target:self
                                         action:@selector(onStepProgress:)];
  [stepBtn setFrame:NSMakeRect(230.0, 24.0, 96.0, 28.0)];
  [boxProgress addSubview:stepBtn];

  _slider =
      [[NSSlider alloc] initWithFrame:NSMakeRect(14.0, 58.0, 312.0, 24.0)];
  [_slider setMinValue:0.0];
  [_slider setMaxValue:100.0];
  [_slider setDoubleValue:65.0];
  [_slider setTarget:self];
  [_slider setAction:@selector(onSliderChanged:)];
  [boxProgress addSubview:_slider];

  NSTextField* detCap = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 88.0, 312.0, 18.0)];
  [detCap setFont:[NSFont systemFontOfSize:11.5]];
  [detCap setTextColor:[NSColor darkGrayColor]];
  [detCap setStringValue:@"Determinate Progress Bar (NSProgressIndicator):"];
  [boxProgress addSubview:detCap];

  _detProgress = [[NSProgressIndicator alloc]
      initWithFrame:NSMakeRect(14.0, 108.0, 312.0, 14.0)];
  [_detProgress setIndeterminate:NO];
  [_detProgress setMinValue:0.0];
  [_detProgress setMaxValue:100.0];
  [_detProgress setDoubleValue:65.0];
  [boxProgress addSubview:_detProgress];

  NSTextField* indetCap = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 130.0, 312.0, 18.0)];
  [indetCap setFont:[NSFont systemFontOfSize:11.5]];
  [indetCap setTextColor:[NSColor darkGrayColor]];
  [indetCap setStringValue:@"Indeterminate Animated Bar:"];
  [boxProgress addSubview:indetCap];

  _indetProgress = [[NSProgressIndicator alloc]
      initWithFrame:NSMakeRect(14.0, 150.0, 312.0, 14.0)];
  [_indetProgress setIndeterminate:YES];
  [_indetProgress startAnimation:self];
  [boxProgress addSubview:_indetProgress];

  _spinner = [[NSProgressIndicator alloc]
      initWithFrame:NSMakeRect(18.0, 174.0, 28.0, 28.0)];
  [_spinner setStyle:1];
  [_spinner startAnimation:self];
  [boxProgress addSubview:_spinner];

  NSTextField* spinCap = [[NSTextField alloc]
      initWithFrame:NSMakeRect(54.0, 178.0, 270.0, 20.0)];
  [spinCap setFont:[NSFont systemFontOfSize:12.0]];
  [spinCap setTextColor:[NSColor labelColor]];
  [spinCap setStringValue:@"Spinning Gear Indicator (style = 1)"];
  [boxProgress addSubview:spinCap];

  // -------------------------------------------------------------------------
  // Panel 4 (Bottom-Right): NSTextField, NSTextView & Fonts
  // -------------------------------------------------------------------------
  NSBox* boxText =
      [[NSBox alloc] initWithFrame:NSMakeRect(366.0, 288.0, 340.0, 218.0)];
  [boxText setTitle:@"4. Text Controls, Fonts & Live Event Log"];
  [content addSubview:boxText];

  _bezelField = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 28.0, 312.0, 26.0)];
  [_bezelField setBezeled:YES];
  [_bezelField setDrawsBackground:YES];
  [_bezelField setBackgroundColor:[NSColor whiteColor]];
  [_bezelField setFont:[NSFont systemFontOfSize:12.5]];
  [_bezelField setTextColor:[NSColor labelColor]];
  [_bezelField setStringValue:@"Bezeled NSTextField: Darling Cocoa on XNU"];
  [boxText addSubview:_bezelField];

  NSTextField* monoSample = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 58.0, 312.0, 18.0)];
  [monoSample setFont:[NSFont userFixedPitchFontOfSize:11.0]];
  [monoSample setTextColor:[NSColor colorWithCalibratedRed:0.08
                                                     green:0.38
                                                      blue:0.20
                                                     alpha:1.0]];
  [monoSample setStringValue:@"Font: DejaVu Sans Mono 11pt (NSTextView)"];
  [boxText addSubview:monoSample];

  _logView = [[NSTextView alloc]
      initWithFrame:NSMakeRect(14.0, 80.0, 312.0, 94.0)];
  [_logView setBackgroundColor:[NSColor whiteColor]];
  [_logView setFont:[NSFont userFixedPitchFontOfSize:11.0]];
  [_logView setTextColor:[NSColor labelColor]];
  [_logView setString:@"[WidgetGallery] Ready - click any widget.\n"];
  [boxText addSubview:_logView];

  NSButton* quitBtn = [NSButton buttonWithTitle:@"Quit"
                                         target:self
                                         action:@selector(onQuitClicked:)];
  [quitBtn setFrame:NSMakeRect(236.0, 180.0, 90.0, 30.0)];
  [boxText addSubview:quitBtn];

  NSTextField* footerNote = [[NSTextField alloc]
      initWithFrame:NSMakeRect(14.0, 185.0, 214.0, 20.0)];
  [footerNote setFont:[NSFont systemFontOfSize:11.0]];
  [footerNote setTextColor:[NSColor darkGrayColor]];
  [footerNote setStringValue:@"All widgets active & interactive"];
  [boxText addSubview:footerNote];

  [_window makeKeyAndOrderFront:nil];
  printf("DARLING_WIDGET_GALLERY_READY\n");
  fflush(stdout);
}

- (void)onSegmentChanged:(id)sender {
  (void)sender;
  NSInteger seg = [_segControl selectedSegment];
  NSString* label = [_segControl labelForSegment:seg];
  [_bezelField setStringValue:[NSString stringWithFormat:
                                            @"Selected segment %ld: %@",
                                            static_cast<long>(seg), label]];
  [self appendLog:[NSString stringWithFormat:@"NSSegmentedControl -> %@", label]];
}

- (void)onPrimaryClicked:(id)sender {
  (void)sender;
  [self appendLog:@"Clicked Primary Aqua NSButton"];
  [_bezelField setStringValue:@"Action: Primary Aqua Button clicked"];
}

- (void)onSecondaryClicked:(id)sender {
  (void)sender;
  [self appendLog:@"Clicked Secondary Tinted NSButton"];
  [_bezelField setStringValue:@"Action: Secondary Button clicked"];
}

- (void)onDestructiveClicked:(id)sender {
  (void)sender;
  [self appendLog:@"Clicked Destructive Red NSButton"];
  [_bezelField setStringValue:@"Action: Destructive Button clicked"];
}

- (void)onDisclosureClicked:(id)sender {
  (void)sender;
  NSInteger st = [_disclosureBtn state];
  [_disclosureLabel
      setStringValue:st ? @"Disclosure Chevron: Expanded (Bezel 5)"
                        : @"Disclosure Chevron: Collapsed (Bezel 5)"];
  [self appendLog:st ? @"Disclosure -> Expanded" : @"Disclosure -> Collapsed"];
}

- (void)onCheckboxClicked:(id)sender {
  NSButton* btn = static_cast<NSButton*>(sender);
  [self appendLog:[NSString stringWithFormat:@"Checkbox '%@' = %ld",
                                             [btn title],
                                             static_cast<long>([btn state])]];
}

- (void)onRadioClicked:(id)sender {
  NSButton* clicked = static_cast<NSButton*>(sender);
  [_radioAqua setState:(clicked == _radioAqua) ? 1 : 0];
  [_radioGraphite setState:(clicked == _radioGraphite) ? 1 : 0];
  [_radioContrast setState:(clicked == _radioContrast) ? 1 : 0];
  [self appendLog:[NSString stringWithFormat:@"Radio selected: %@",
                                             [clicked title]]];
}

- (void)onSliderChanged:(id)sender {
  (void)sender;
  int v = static_cast<int>([_slider doubleValue] + 0.5);
  [_detProgress setDoubleValue:v];
  [_progressLabel
      setStringValue:[NSString stringWithFormat:@"Determinate Value: %d%%", v]];
  [self appendLog:[NSString stringWithFormat:@"NSSlider value -> %d%%", v]];
}

- (void)onStepProgress:(id)sender {
  (void)sender;
  int v = static_cast<int>([_detProgress doubleValue] + 15.0);
  if (v > 100) v = 10;
  [_slider setDoubleValue:v];
  [_detProgress setDoubleValue:v];
  [_progressLabel
      setStringValue:[NSString stringWithFormat:@"Determinate Value: %d%%", v]];
  [self appendLog:[NSString stringWithFormat:@"Step +15%% -> %d%%", v]];
  printf("DARLING_GALLERY_STEP:%d\n", v);
  fflush(stdout);
}

- (void)onQuitClicked:(id)sender {
  (void)sender;
  [NSApp terminate:self];
}

@end

extern "C" int main(int argc, const char* argv[]) {
  (void)argc;
  (void)argv;
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  NSApplication* app = [NSApplication sharedApplication];
  [app setActivationPolicy:NSApplicationActivationPolicyRegular];
  WidgetGalleryDelegate* delegate = [[WidgetGalleryDelegate alloc] init];
  [app setDelegate:delegate];
  [app run];
  [pool drain];
  return 0;
}
