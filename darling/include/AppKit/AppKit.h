// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef DARLING_EMBEDDED_APPKIT_APPKIT_H_
#define DARLING_EMBEDDED_APPKIT_APPKIT_H_

#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>

enum {
  NSWindowStyleMaskBorderless = 0,
  NSWindowStyleMaskTitled = 1 << 0,
  NSWindowStyleMaskClosable = 1 << 1,
  NSWindowStyleMaskMiniaturizable = 1 << 2,
  NSWindowStyleMaskResizable = 1 << 3,
  NSTitledWindowMask = NSWindowStyleMaskTitled,
  NSClosableWindowMask = NSWindowStyleMaskClosable,
  NSMiniaturizableWindowMask = NSWindowStyleMaskMiniaturizable,
  NSResizableWindowMask = NSWindowStyleMaskResizable,
};

enum {
  NSBackingStoreRetained = 0,
  NSBackingStoreNonretained = 1,
  NSBackingStoreBuffered = 2,
};

enum {
  NSApplicationActivationPolicyRegular = 0,
  NSApplicationActivationPolicyAccessory = 1,
  NSApplicationActivationPolicyProhibited = 2,
};

enum {
  NSTextAlignmentLeft = 0,
  NSTextAlignmentRight = 1,
  NSTextAlignmentCenter = 2,
};

enum {
  NSBezelStyleRounded = 1,
  NSBezelStyleRegularSquare = 2,
  NSBezelStyleDisclosure = 5,
  NSRoundedBezelStyle = NSBezelStyleRounded,
};

#ifdef __OBJC__

@interface NSColor : NSObject {
 @public
  double _r;
  double _g;
  double _b;
  double _a;
}
+ (NSColor*)colorWithCalibratedRed:(CGFloat)red
                             green:(CGFloat)green
                              blue:(CGFloat)blue
                             alpha:(CGFloat)alpha;
+ (NSColor*)colorWithSRGBRed:(CGFloat)red
                       green:(CGFloat)green
                        blue:(CGFloat)blue
                       alpha:(CGFloat)alpha;
+ (NSColor*)whiteColor;
+ (NSColor*)blackColor;
+ (NSColor*)clearColor;
+ (NSColor*)grayColor;
+ (NSColor*)lightGrayColor;
+ (NSColor*)darkGrayColor;
+ (NSColor*)redColor;
+ (NSColor*)greenColor;
+ (NSColor*)blueColor;
+ (NSColor*)cyanColor;
+ (NSColor*)yellowColor;
+ (NSColor*)orangeColor;
+ (NSColor*)windowBackgroundColor;
+ (NSColor*)controlBackgroundColor;
+ (NSColor*)labelColor;
+ (NSColor*)controlTextColor;
- (CGFloat)redComponent;
- (CGFloat)greenComponent;
- (CGFloat)blueComponent;
- (CGFloat)alphaComponent;
- (void)set;
- (void)setFill;
- (void)setStroke;
@end

@interface NSFont : NSObject {
 @public
  CGFloat _size;
  BOOL _bold;
  BOOL _fixedPitch;
}
+ (NSFont*)systemFontOfSize:(CGFloat)fontSize;
+ (NSFont*)boldSystemFontOfSize:(CGFloat)fontSize;
+ (NSFont*)monospacedDigitSystemFontOfSize:(CGFloat)fontSize
                                    weight:(CGFloat)weight;
+ (NSFont*)userFixedPitchFontOfSize:(CGFloat)fontSize;
- (CGFloat)pointSize;
- (BOOL)isBold;
- (BOOL)isFixedPitch;
+ (NSFont*)fontWithName:(NSString*)fontName size:(CGFloat)fontSize;
@end

@interface NSBezierPath : NSObject
+ (void)fillRect:(NSRect)rect;
+ (void)strokeRect:(NSRect)rect;
+ (void)fillRoundedRect:(NSRect)rect xRadius:(CGFloat)xRad yRadius:(CGFloat)yRad;
+ (void)strokeRoundedRect:(NSRect)rect
                  xRadius:(CGFloat)xRad
                  yRadius:(CGFloat)yRad
                lineWidth:(CGFloat)lineWidth;
+ (void)strokeLineFromPoint:(NSPoint)point1
                    toPoint:(NSPoint)point2
                  lineWidth:(CGFloat)lineWidth;
+ (void)drawText:(NSString*)text
          inRect:(NSRect)rect
            font:(NSFont*)font
           color:(NSColor*)color
       alignment:(NSInteger)alignment;
@end

@interface NSEvent : NSObject {
 @public
  NSPoint _locationInWindow;
  unsigned int _keyCode;
  NSString* _characters;
}
- (NSPoint)locationInWindow;
- (unsigned int)keyCode;
- (NSString*)characters;
@end

@class NSWindow;

@interface NSView : NSObject {
 @public
  NSRect _frame;
  NSRect _bounds;
  NSView* _superview;
  NSMutableArray* _subviews;
  NSWindow* _window;
  NSColor* _backgroundColor;
  BOOL _hidden;
  BOOL _needsDisplay;
  NSInteger _tag;
  BOOL _translatesAutoresizingMaskOff;
  BOOL _flippedNonAutoLayoutSubviews;
}
- (instancetype)initWithFrame:(NSRect)frameRect;
- (NSRect)frame;
- (void)setFrame:(NSRect)frameRect;
- (NSRect)bounds;
- (NSWindow*)window;
- (NSView*)superview;
- (NSArray*)subviews;
- (void)addSubview:(NSView*)aView;
- (void)setBackgroundColor:(NSColor*)color;
- (NSColor*)backgroundColor;
- (void)setHidden:(BOOL)flag;
- (BOOL)isHidden;
- (void)setNeedsDisplay:(BOOL)flag;
- (void)display;
- (void)drawRect:(NSRect)dirtyRect;
- (void)mouseDown:(NSEvent*)event;
- (void)mouseUp:(NSEvent*)event;
- (void)keyDown:(NSEvent*)event;
- (NSInteger)tag;
- (void)setTag:(NSInteger)tag;
@end

@interface NSControl : NSView {
 @public
  id _target;
  SEL _action;
  NSString* _stringValue;
  NSFont* _font;
  NSInteger _alignment;
  BOOL _enabled;
}
- (id)target;
- (void)setTarget:(id)target;
- (SEL)action;
- (void)setAction:(SEL)action;
- (NSString*)stringValue;
- (void)setStringValue:(NSString*)string;
- (NSFont*)font;
- (void)setFont:(NSFont*)fontObj;
- (NSInteger)alignment;
- (void)setAlignment:(NSInteger)mode;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;
- (BOOL)sendAction:(SEL)theAction to:(id)theTarget;
@end

@interface NSTextField : NSControl {
 @public
  NSColor* _textColor;
  BOOL _editable;
  BOOL _selectable;
  BOOL _bezeled;
  BOOL _drawsBackground;
}
+ (instancetype)labelWithString:(NSString*)stringValue;
- (void)setTextColor:(NSColor*)color;
- (NSColor*)textColor;
- (void)setEditable:(BOOL)flag;
- (BOOL)isEditable;
- (void)setSelectable:(BOOL)flag;
- (BOOL)isSelectable;
- (void)setBezeled:(BOOL)flag;
- (BOOL)isBezeled;
- (void)setDrawsBackground:(BOOL)flag;
- (BOOL)drawsBackground;
@end

@interface NSTextView : NSView {
 @public
  NSColor* _textColor;
  NSString* _string;
  NSFont* _font;
  BOOL _editable;
}
- (void)setTextColor:(NSColor*)color;
- (NSColor*)textColor;
- (void)setString:(NSString*)string;
- (NSString*)string;
- (void)setFont:(NSFont*)font;
- (NSFont*)font;
- (void)setEditable:(BOOL)flag;
- (BOOL)isEditable;
- (BOOL)readRTFDFromFile:(NSString*)path;
@end

typedef NSUInteger NSButtonType;
enum : NSUInteger {
  NSButtonTypeMomentaryLight = 0,
  NSButtonTypePushOnPushOff = 1,
  NSButtonTypeToggle = 2,
  NSButtonTypeSwitch = 3,
  NSButtonTypeRadio = 4,
  NSButtonTypeMomentaryChange = 5,
  NSButtonTypeOnOff = 6,
  NSButtonTypeMomentaryPushIn = 7,
};

@interface NSButton : NSControl {
 @public
  NSString* _title;
  NSInteger _bezelStyle;
  BOOL _highlighted;
  NSColor* _tintColor;
  NSUInteger _buttonType;
  NSInteger _state;
}
+ (instancetype)buttonWithTitle:(NSString*)title
                         target:(id)target
                         action:(SEL)action;
- (NSString*)title;
- (void)setTitle:(NSString*)title;
- (void)setBezelStyle:(NSInteger)bezelStyle;
- (NSInteger)bezelStyle;
- (void)setTintColor:(NSColor*)color;
- (NSColor*)tintColor;
- (void)performClick:(id)sender;
- (void)setButtonType:(NSButtonType)type;
- (NSInteger)state;
- (void)setState:(NSInteger)value;
@end

@interface NSBox : NSView {
 @public
  NSString* _boxTitle;
  BOOL _transparent;
}
- (void)setTitle:(NSString*)title;
- (NSString*)title;
@end

@interface NSTextStorage : NSObject {
 @public
  NSTextView* _view;
  NSInteger _editing;
}
- (NSString*)string;
- (NSMutableString*)mutableString;
- (NSUInteger)length;
- (void)beginEditing;
- (void)endEditing;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString*)str;
- (void)appendAttributedString:(id)attrString;
- (void)setAttributedString:(id)attrString;
- (void)setFont:(NSFont*)font;
- (void)addAttribute:(NSString*)n value:(id)v range:(NSRange)r;
- (void)setAttributes:(NSDictionary*)a range:(NSRange)r;
@end

@interface NSTextView (DarlingAdditions)
- (NSTextStorage*)textStorage;
- (void)scrollRangeToVisible:(NSRange)range;
- (void)setSelectable:(BOOL)flag;
- (void)setRichText:(BOOL)flag;
- (void)setDrawsBackground:(BOOL)flag;
- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)flag;
- (void)setContinuousSpellCheckingEnabled:(BOOL)flag;
- (void)insertText:(id)text;
@end

@interface NSProgressIndicator : NSView {
 @public
  double _value;
  double _minValue;
  double _maxValue;
  BOOL _indeterminate;
  BOOL _spinning;
  BOOL _animating;
  BOOL _displayedWhenStopped;
  NSTimer* _timer;
}
- (double)doubleValue;
- (void)setDoubleValue:(double)v;
- (void)incrementBy:(double)delta;
- (double)minValue;
- (void)setMinValue:(double)v;
- (double)maxValue;
- (void)setMaxValue:(double)v;
- (BOOL)isIndeterminate;
- (void)setIndeterminate:(BOOL)b;
- (void)setUsesThreadedAnimation:(BOOL)b;
- (void)setDisplayedWhenStopped:(BOOL)b;
- (void)setStyle:(NSUInteger)style;
- (void)startAnimation:(id)sender;
- (void)stopAnimation:(id)sender;
@end

@interface NSSlider : NSControl {
 @public
  double _minValue;
  double _maxValue;
  double _value;
}
- (double)minValue;
- (void)setMinValue:(double)v;
- (double)maxValue;
- (void)setMaxValue:(double)v;
- (double)doubleValue;
- (void)setDoubleValue:(double)v;
@end

@interface NSSegmentedControl : NSControl {
 @public
  NSMutableArray* _labels;
  NSInteger _selectedSegment;
}
- (void)setSegmentCount:(NSInteger)count;
- (NSInteger)segmentCount;
- (void)setLabel:(NSString*)label forSegment:(NSInteger)segment;
- (NSString*)labelForSegment:(NSInteger)segment;
- (void)setSelectedSegment:(NSInteger)selectedSegment;
- (NSInteger)selectedSegment;
@end

@interface NSImageView : NSControl {
 @public
  void* _imageSurface;  // cairo_surface_t*
}
- (BOOL)loadImageFromIcnsFile:(NSString*)path;
@end

@interface NSWindow : NSObject {
 @public
  NSRect _frame;
  NSUInteger _styleMask;
  NSUInteger _backingType;
  NSString* _title;
  NSView* _contentView;
  NSColor* _backgroundColor;
  BOOL _visible;
  BOOL _needsDisplay;
  unsigned long _x11Window;
  void* _cairoSurface;
  void* _cairoContext;
  void* _backbuffer;
  id _delegate;
  int _surfaceW;
  int _surfaceH;
  uint64_t _paintCount;
}
- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSUInteger)style
                            backing:(NSUInteger)backingStoreType
                              defer:(BOOL)flag;
- (void)setTitle:(NSString*)string;
- (NSString*)title;
- (NSView*)contentView;
- (void)setContentView:(NSView*)aView;
- (void)setBackgroundColor:(NSColor*)color;
- (NSColor*)backgroundColor;
- (NSRect)frame;
- (void)setFrameOrigin:(NSPoint)point;
- (void)center;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderFront:(id)sender;
- (void)close;
- (void)display;
- (unsigned long)windowNumber;
- (void)setDelegate:(id)delegate;
- (id)delegate;
@end

@interface NSApplication : NSObject {
 @public
  id _delegate;
  NSMutableArray* _windows;
  NSMutableArray* _timers;
  NSWindow* _keyWindow;
  BOOL _running;
  NSInteger _activationPolicy;
  void* _x11Display;
  int _x11Screen;
}
+ (NSApplication*)sharedApplication;
- (void)setDelegate:(id)anObject;
- (id)delegate;
- (BOOL)setActivationPolicy:(NSInteger)activationPolicy;
- (void)activateIgnoringOtherApps:(BOOL)flag;
- (NSArray*)windows;
- (NSWindow*)keyWindow;
- (void)run;
- (void)stop:(id)sender;
- (void)terminate:(id)sender;
- (void)arrangeInFront:(id)sender;
- (void)sendEvent:(NSEvent*)theEvent;
@end

@interface NSAlert : NSObject
- (void)setAlertStyle:(NSUInteger)style;
- (void)setMessageText:(NSString*)messageText;
- (void)setInformativeText:(NSString*)informativeText;
- (void)addButtonWithTitle:(NSString*)title;
- (NSInteger)runModal;
@end

@interface NSOpenPanel : NSWindow
+ (NSOpenPanel*)openPanel;
- (void)setCanChooseFiles:(BOOL)flag;
- (void)setCanChooseDirectories:(BOOL)flag;
- (void)setAllowsMultipleSelection:(BOOL)flag;
- (NSInteger)runModal;
- (NSArray*)URLs;
@end

@interface NSWorkspace : NSObject
+ (NSWorkspace*)sharedWorkspace;
- (BOOL)openFile:(NSString*)fullPath;
- (BOOL)openFile:(NSString*)fullPath withApplication:(NSString*)appName;
- (BOOL)openFile:(NSString*)fullPath withApplication:(NSString*)appName andDeactivate:(BOOL)flag;
@end

@interface NSWindowController : NSObject
- (instancetype)initWithWindow:(NSWindow*)window;
- (instancetype)initWithWindowNibName:(NSString*)windowNibName;
- (void)windowDidLoad;
- (void)showWindow:(id)sender;
- (NSWindow*)window;
- (void)setWindow:(NSWindow*)window;
- (void)loadWindow;
@end

extern NSApplication* NSApp;

#ifdef __cplusplus
extern "C" {
#endif
int NSApplicationMain(int argc, const char* argv[]);
void NSBeep(void);
int TransformProcessType(void* psn, uint32_t type);
#ifdef __cplusplus
}
#endif

#endif  // __OBJC__

#endif  // DARLING_EMBEDDED_APPKIT_APPKIT_H_
