// SPDX-License-Identifier: GPL-3.0-or-later
// Framework smoke test for Darling Embedded (built from source in this repo).
// This is NOT an Apple application; it exercises the in-tree Foundation/AppKit
// and uses Darling-Embedded-specific drawing helpers (e.g. +drawText:inRect:).

#include <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>

@interface HelloBannerView : NSView {
 @public
  int _greetingCount;
}
@end

@implementation HelloBannerView

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = [self bounds];

  // Deep Mac OS X Aqua / Catalina blue card banner
  NSColor* bannerBg = (_greetingCount > 0)
                          ? [NSColor colorWithCalibratedRed:0.06
                                                      green:0.36
                                                       blue:0.72
                                                      alpha:1.0]
                          : [NSColor colorWithCalibratedRed:0.09
                                                      green:0.25
                                                       blue:0.52
                                                      alpha:1.0];
  [bannerBg setFill];
  [NSBezierPath fillRoundedRect:b xRadius:10.0 yRadius:10.0];

  [[NSColor colorWithCalibratedRed:0.35 green:0.62 blue:0.95 alpha:0.85]
      setStroke];
  [NSBezierPath strokeRoundedRect:NSInsetRect(b, 0.5, 0.5)
                          xRadius:10.0
                          yRadius:10.0
                        lineWidth:1.5];

  // Decorative Mac OS X Aqua orb on the left of the banner
  NSRect orbRect = NSMakeRect(18.0, 18.0, 54.0, 54.0);
  [[NSColor colorWithCalibratedRed:0.22 green:0.68 blue:1.0 alpha:1.0] setFill];
  [NSBezierPath fillRoundedRect:orbRect xRadius:27.0 yRadius:27.0];
  [[NSColor whiteColor] setStroke];
  [NSBezierPath strokeRoundedRect:orbRect
                          xRadius:27.0
                          yRadius:27.0
                        lineWidth:2.0];
  [NSBezierPath drawText:@"X"
                  inRect:orbRect
                    font:[NSFont boldSystemFontOfSize:26.0]
                   color:[NSColor whiteColor]
               alignment:NSTextAlignmentCenter];

  [NSBezierPath drawText:@"Hello, Mac OS X World!"
                  inRect:NSMakeRect(86.0, 14.0, b.size.width - 96.0, 32.0)
                    font:[NSFont boldSystemFontOfSize:21.0]
                   color:[NSColor whiteColor]
               alignment:NSTextAlignmentLeft];

  [NSBezierPath
       drawText:@"Native ARM64 Mach-O Cocoa App via Darling on XNU"
         inRect:NSMakeRect(86.0, 46.0, b.size.width - 96.0, 24.0)
           font:[NSFont systemFontOfSize:12.5]
          color:[NSColor colorWithCalibratedRed:0.82
                                          green:0.91
                                           blue:1.0
                                          alpha:1.0]
      alignment:NSTextAlignmentLeft];
}

@end

@interface HelloAppDelegate : NSObject {
  NSWindow* _window;
  HelloBannerView* _bannerView;
  NSTextField* _statusLabel;
  NSButton* _helloButton;
  int _clickCount;
}
- (void)applicationDidFinishLaunching:(id)notification;
- (void)onSayHelloClicked:(id)sender;
@end

@implementation HelloAppDelegate

- (void)applicationDidFinishLaunching:(id)notification {
  (void)notification;
  _clickCount = 0;

  _window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(24.0, 48.0, 460.0, 330.0)
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [_window setTitle:@"Hello World - Darling Mac OS X"];
  [_window setBackgroundColor:[NSColor colorWithCalibratedRed:0.94
                                                        green:0.95
                                                         blue:0.97
                                                        alpha:1.0]];

  NSView* content = [_window contentView];

  _bannerView = [[HelloBannerView alloc]
      initWithFrame:NSMakeRect(16.0, 14.0, 428.0, 84.0)];
  _bannerView->_greetingCount = 0;
  [content addSubview:_bannerView];

  // System details card
  NSView* infoCard =
      [[NSView alloc] initWithFrame:NSMakeRect(16.0, 106.0, 428.0, 126.0)];
  [infoCard setBackgroundColor:[NSColor whiteColor]];
  [content addSubview:infoCard];

  NSProcessInfo* pinfo = [NSProcessInfo processInfo];
  NSBundle* bundle = [NSBundle mainBundle];

  NSTextField* line1 = [[NSTextField alloc]
      initWithFrame:NSMakeRect(12.0, 10.0, 394.0, 24.0)];
  [line1 setFont:[NSFont boldSystemFontOfSize:13.0]];
  [line1 setTextColor:[NSColor colorWithCalibratedRed:0.12
                                                green:0.14
                                                 blue:0.18
                                                alpha:1.0]];
  [line1 setStringValue:[NSString stringWithFormat:@"OS Environment: %@",
                                                   [pinfo operatingSystemVersionString]]];
  [infoCard addSubview:line1];

  NSTextField* line2 = [[NSTextField alloc]
      initWithFrame:NSMakeRect(12.0, 38.0, 394.0, 22.0)];
  [line2 setFont:[NSFont systemFontOfSize:12.5]];
  [line2 setTextColor:[NSColor darkGrayColor]];
  [line2 setStringValue:[NSString stringWithFormat:@"Bundle ID: %@  (PID %d)",
                                                   [bundle bundleIdentifier],
                                                   [pinfo processIdentifier]]];
  [infoCard addSubview:line2];

  NSTextField* line3 = [[NSTextField alloc]
      initWithFrame:NSMakeRect(12.0, 64.0, 394.0, 22.0)];
  [line3 setFont:[NSFont systemFontOfSize:12.5]];
  [line3 setTextColor:[NSColor darkGrayColor]];
  unsigned long long memMiB = [pinfo physicalMemory] / (1024ULL * 1024ULL);
  [line3 setStringValue:[NSString
                            stringWithFormat:@"Hardware: %lu ARM64 Cores | %llu MiB RAM | Host: %@",
                                             [pinfo processorCount], memMiB,
                                             [pinfo hostName]]];
  [infoCard addSubview:line3];

  NSTextField* line4 = [[NSTextField alloc]
      initWithFrame:NSMakeRect(12.0, 92.0, 394.0, 24.0)];
  [line4 setFont:[NSFont boldSystemFontOfSize:12.5]];
  [line4 setTextColor:[NSColor colorWithCalibratedRed:0.05
                                                green:0.45
                                                 blue:0.22
                                                alpha:1.0]];
  [line4 setStringValue:
             @"Runtime: libobjc.A.dylib + Foundation + AppKit (Cocoa/Cairo)"];
  [infoCard addSubview:line4];

  // Interactive status field
  _statusLabel = [[NSTextField alloc]
      initWithFrame:NSMakeRect(16.0, 240.0, 428.0, 32.0)];
  [_statusLabel setDrawsBackground:YES];
  [_statusLabel setBezeled:YES];
  [_statusLabel
      setBackgroundColor:[NSColor colorWithCalibratedRed:0.89
                                                   green:0.94
                                                    blue:1.0
                                                   alpha:1.0]];
  [_statusLabel setFont:[NSFont boldSystemFontOfSize:13.0]];
  [_statusLabel setAlignment:NSTextAlignmentCenter];
  [_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.04
                                                       green:0.30
                                                        blue:0.65
                                                       alpha:1.0]];
  [_statusLabel
      setStringValue:@"Ready: Click 'Say Hello!' to dispatch Objective-C action"];
  [content addSubview:_statusLabel];

  // Interactive Cocoa button
  _helloButton = [NSButton buttonWithTitle:@"Say Hello!"
                                    target:self
                                    action:@selector(onSayHelloClicked:)];
  [_helloButton setFrame:NSMakeRect(150.0, 282.0, 160.0, 36.0)];
  [content addSubview:_helloButton];

  [_window makeKeyAndOrderFront:nil];
  NSLog(@"HelloWorld.app GUI launched on XNU/Darwin via Darling");
}

- (void)onSayHelloClicked:(id)sender {
  (void)sender;
  _clickCount++;
  _bannerView->_greetingCount = _clickCount;
  [_bannerView setNeedsDisplay:YES];
  [_statusLabel
      setStringValue:[NSString
                         stringWithFormat:
                             @"Hello #%d from Native Mac OS X Cocoa on XNU!",
                             _clickCount]];
  [_statusLabel
      setBackgroundColor:[NSColor colorWithCalibratedRed:0.84
                                                   green:0.97
                                                    blue:0.88
                                                   alpha:1.0]];
  [_statusLabel
      setTextColor:[NSColor colorWithCalibratedRed:0.06
                                             green:0.46
                                              blue:0.18
                                             alpha:1.0]];
  printf("DARLING_HELLO_GUI_ACTION:%d\n", _clickCount);
  fflush(stdout);
}

@end

extern "C" int main(int argc, const char* argv[]) {
  printf("DARLING_HELLO_START\n");
  fflush(stdout);
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  NSProcessInfo* info = [NSProcessInfo processInfo];

  for (int i = 1; i < argc; ++i) {
    if (strcmp(argv[i], "--cli") == 0 || strcmp(argv[i], "--test") == 0) {
      NSString* greeting = [NSString
          stringWithFormat:@"Hello, Mac OS X World from Darling! (%@)",
                           [info operatingSystemVersionString]];
      printf("%s\n", [greeting UTF8String]);
      printf("DARLING_HELLO_CLI_OK:pid=%d:cpus=%lu\n",
             [info processIdentifier], [info processorCount]);
      fflush(stdout);
      [pool drain];
      return 0;
    }
  }

  NSApplication* app = [NSApplication sharedApplication];
  [app setActivationPolicy:NSApplicationActivationPolicyRegular];
  HelloAppDelegate* delegate = [[HelloAppDelegate alloc] init];
  [app setDelegate:delegate];
  [app run];
  [pool drain];
  return 0;
}
