// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded WebKit.framework placeholder. No HTML engine exists in
// this userland: WebView is an NSView that records what it was asked to load
// and draws a notice instead of web content.
#include <AppKit/AppKit.h>

@interface WebPreferences : NSObject
@end

@implementation WebPreferences
+ (instancetype)standardPreferences {
  return [[self alloc] init];
}
- (void)setJavaScriptEnabled:(BOOL)b { (void)b; }
- (void)setPlugInsEnabled:(BOOL)b { (void)b; }
@end

@class WebView;

@interface WebFrame : NSObject {
 @public
  WebView* _view;
}
@end

@interface WebView : NSView {
 @public
  WebFrame* _mainFrame;
  NSString* _lastLoad;
  id _frameLoadDelegate;
  id _policyDelegate;
  id _UIDelegate;
}
@end

@implementation WebFrame
- (void)loadHTMLString:(NSString*)string baseURL:(id)url {
  (void)url;
  _view->_lastLoad = [NSString stringWithFormat:@"HTML (%lu bytes)",
                                              (unsigned long)[string length]];
  [_view setNeedsDisplay:YES];
}
- (void)loadRequest:(id)request {
  id u = [request respondsToSelector:@selector(URL)] ? [request performSelector:@selector(URL)] : nil;
  _view->_lastLoad = u ? [u description] : @"request";
  [_view setNeedsDisplay:YES];
}
- (void)reload {}
@end

@implementation WebView

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _mainFrame = [[WebFrame alloc] init];
    _mainFrame->_view = self;
  }
  return self;
}

- (WebFrame*)mainFrame { return _mainFrame; }
- (void)setFrameLoadDelegate:(id)d { _frameLoadDelegate = d; }
- (void)setPolicyDelegate:(id)d { _policyDelegate = d; }
- (void)setUIDelegate:(id)d { _UIDelegate = d; }
- (void)setResourceLoadDelegate:(id)d { (void)d; }
- (void)setDownloadDelegate:(id)d { (void)d; }
- (void)setPreferences:(WebPreferences*)p { (void)p; }
- (void)setDrawsBackground:(BOOL)b { (void)b; }
- (NSString*)mainFrameURL { return _lastLoad; }

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = [self bounds];
  [[NSColor colorWithCalibratedRed:0.95 green:0.95 blue:0.96 alpha:1.0] setFill];
  [NSBezierPath fillRect:b];
  NSString* msg = _lastLoad
      ? [NSString stringWithFormat:@"WebKit is not available in Darling Embedded.\nRequested: %@", _lastLoad]
      : @"WebKit is not available in Darling Embedded.";
  [NSBezierPath drawText:msg
                  inRect:NSInsetRect(b, 10, 10)
                    font:[NSFont systemFontOfSize:12]
                   color:[NSColor darkGrayColor]
               alignment:NSTextAlignmentCenter];
}

@end
