// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded AppKit: additional classes used by real-world Cocoa
// applications (menus, progress indicators, text storage, images,
// appearance, panels, status items) plus AppKit string constants.
// Included from appkit.mm before the nib loader.

#include <time.h>

static BOOL DarlingLoadNibNamed(NSString* name, id owner, NSBundle* bundle);

extern "C" NSString* const NSAppearanceNameAqua;
NSString* const NSAppearanceNameAqua = @"NSAppearanceNameAqua";
extern "C" NSString* const NSAppearanceNameDarkAqua;
NSString* const NSAppearanceNameDarkAqua = @"NSAppearanceNameDarkAqua";
extern "C" NSString* const NSCalibratedRGBColorSpace;
NSString* const NSCalibratedRGBColorSpace = @"NSCalibratedRGBColorSpace";
extern "C" NSString* const NSDeviceRGBColorSpace;
NSString* const NSDeviceRGBColorSpace = @"NSDeviceRGBColorSpace";
extern "C" NSString* const NSFilenamesPboardType;
NSString* const NSFilenamesPboardType = @"NSFilenamesPboardType";
extern "C" NSString* const NSStringPboardType;
NSString* const NSStringPboardType = @"NSStringPboardType";
extern "C" NSString* const NSURLPboardType;
NSString* const NSURLPboardType = @"Apple URL pasteboard type";
extern "C" NSString* const NSPasteboardTypeString;
NSString* const NSPasteboardTypeString = @"public.utf8-plain-text";
extern "C" NSString* const NSFontAttributeName;
NSString* const NSFontAttributeName = @"NSFont";
extern "C" NSString* const NSForegroundColorAttributeName;
NSString* const NSForegroundColorAttributeName = @"NSColor";
extern "C" NSString* const NSBackgroundColorAttributeName;
NSString* const NSBackgroundColorAttributeName = @"NSBackgroundColor";
extern "C" NSString* const NSParagraphStyleAttributeName;
NSString* const NSParagraphStyleAttributeName = @"NSParagraphStyle";
extern "C" NSString* const NSLinkAttributeName;
NSString* const NSLinkAttributeName = @"NSLink";
extern "C" NSString* const NSWindowWillCloseNotification;
NSString* const NSWindowWillCloseNotification = @"NSWindowWillCloseNotification";
extern "C" NSString* const NSApplicationWillTerminateNotification;
NSString* const NSApplicationWillTerminateNotification = @"NSApplicationWillTerminateNotification";
extern "C" NSString* const NSApplicationDidFinishLaunchingNotification;
NSString* const NSApplicationDidFinishLaunchingNotification = @"NSApplicationDidFinishLaunchingNotification";
extern "C" NSString* const NSWorkspaceDidTerminateApplicationNotification;
NSString* const NSWorkspaceDidTerminateApplicationNotification = @"NSWorkspaceDidTerminateApplicationNotification";
extern "C" const double NSFontWeightRegular;
const double NSFontWeightRegular = 0.0;
extern "C" NSString* const NSImageNameApplicationIcon;
NSString* const NSImageNameApplicationIcon = @"NSApplicationIcon";
extern "C" NSString* const NSDocumentTypeDocumentAttribute;
NSString* const NSDocumentTypeDocumentAttribute = @"DocumentType";
extern "C" NSString* const NSPasteboardNameFind;
NSString* const NSPasteboardNameFind = @"Apple CFPasteboard find";
extern "C" NSString* const NSPasteboardTypeRTF;
NSString* const NSPasteboardTypeRTF = @"public.rtf";
extern "C" NSString* const NSPasteboardTypeRTFD;
NSString* const NSPasteboardTypeRTFD = @"com.apple.flat-rtfd";
extern "C" NSString* const NSPrintHeaderAndFooter;
NSString* const NSPrintHeaderAndFooter = @"NSPrintHeaderAndFooter";
extern "C" NSString* const NSRTFDTextDocumentType;
NSString* const NSRTFDTextDocumentType = @"NSRTFD";
extern "C" NSString* const NSRTFTextDocumentType;
NSString* const NSRTFTextDocumentType = @"NSRTF";
extern "C" NSString* const NSStrikethroughStyleAttributeName;
NSString* const NSStrikethroughStyleAttributeName = @"NSStrikethrough";

// ===========================================================================
// NSColor additions. A CGColorRef is represented by a pointer to the color's
// four contiguous CGFloat components (r, g, b, a); see CoreGraphics.
// ===========================================================================
@implementation NSColor (DarlingAdditions)

+ (NSColor*)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
  return [self colorWithCalibratedRed:r green:g blue:b alpha:a];
}

+ (NSColor*)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
  return [self colorWithCalibratedRed:r green:g blue:b alpha:a];
}

+ (NSColor*)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a {
  return [self colorWithCalibratedRed:w green:w blue:w alpha:a];
}

+ (NSColor*)colorWithWhite:(CGFloat)w alpha:(CGFloat)a {
  return [self colorWithCalibratedRed:w green:w blue:w alpha:a];
}

+ (NSColor*)textColor { return [self blackColor]; }
+ (NSColor*)textBackgroundColor { return [self whiteColor]; }
+ (NSColor*)secondaryLabelColor { return [self darkGrayColor]; }
+ (NSColor*)disabledControlTextColor { return [self grayColor]; }
+ (NSColor*)selectedTextBackgroundColor {
  return [self colorWithCalibratedRed:0.70 green:0.84 blue:1.0 alpha:1.0];
}
+ (NSColor*)controlColor { return [self controlBackgroundColor]; }

- (NSColor*)colorUsingColorSpaceName:(NSString*)name {
  (void)name;
  return self;
}

- (NSColor*)colorUsingColorSpace:(id)space {
  (void)space;
  return self;
}

- (void*)CGColor {
  return &_r;
}

- (void)getRed:(CGFloat*)r green:(CGFloat*)g blue:(CGFloat*)b alpha:(CGFloat*)a {
  if (r) *r = _r;
  if (g) *g = _g;
  if (b) *b = _b;
  if (a) *a = _a;
}

- (CGFloat)whiteComponent {
  return (_r + _g + _b) / 3.0;
}

@end

// ===========================================================================
// NSAppearance (always Aqua: the guest has no dark mode)
// ===========================================================================
@interface NSAppearance : NSObject {
 @public
  NSString* _name;
}
@end

@implementation NSAppearance

+ (NSAppearance*)appearanceNamed:(NSString*)name {
  NSAppearance* a = [[NSAppearance alloc] init];
  a->_name = [name copy];
  return a;
}

+ (NSAppearance*)currentAppearance {
  return [self appearanceNamed:NSAppearanceNameAqua];
}

+ (NSAppearance*)currentDrawingAppearance {
  return [self currentAppearance];
}

- (NSString*)name {
  return _name;
}

- (NSString*)bestMatchFromAppearancesWithNames:(NSArray*)names {
  return [names containsObject:_name] ? _name : [names firstObject];
}

@end

// ===========================================================================
// NSImage (PNG data or .icns/.png files, decoded with Cairo)
// ===========================================================================
@interface NSImage : NSObject {
 @public
  void* _surface;  // cairo_surface_t*
  NSSize _size;
  NSString* _name;
  BOOL _template;
}
@end

namespace {

struct DataReadCtx {
  const uint8_t* data;
  size_t len;
  size_t pos;
};

cairo_status_t ReadPngFromMemory(void* closure, unsigned char* out, unsigned int length) {
  auto* c = static_cast<DataReadCtx*>(closure);
  if (c->pos + length > c->len) return CAIRO_STATUS_READ_ERROR;
  memcpy(out, c->data + c->pos, length);
  c->pos += length;
  return CAIRO_STATUS_SUCCESS;
}

cairo_surface_t* SurfaceFromPngBytes(const uint8_t* bytes, size_t len) {
  static const uint8_t kPng[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
  if (!bytes || len < 8 || memcmp(bytes, kPng, 8) != 0) return nullptr;
  DataReadCtx ctx = {bytes, len, 0};
  cairo_surface_t* s = cairo_image_surface_create_from_png_stream(ReadPngFromMemory, &ctx);
  if (cairo_surface_status(s) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(s);
    return nullptr;
  }
  return s;
}

}  // namespace

@implementation NSImage

+ (NSImage*)imageNamed:(NSString*)name {
  NSBundle* b = [NSBundle mainBundle];
  NSString* path = [b pathForResource:name ofType:@"png"];
  if (!path) path = [b pathForResource:name ofType:@"icns"];
  NSImage* img = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
  if (img) img->_name = [name copy];
  return img;
}

- (instancetype)initWithSize:(NSSize)size {
  self = [super init];
  if (self) _size = size;
  return self;
}

- (instancetype)initWithData:(NSData*)data {
  self = [super init];
  if (self) {
    auto* s = SurfaceFromPngBytes(static_cast<const uint8_t*>([data bytes]), [data length]);
    if (!s) return nil;
    _surface = s;
    _size = NSMakeSize(cairo_image_surface_get_width(s), cairo_image_surface_get_height(s));
  }
  return self;
}

- (instancetype)initWithContentsOfFile:(NSString*)path {
  FILE* fp = path ? fopen([path UTF8String], "rb") : nullptr;
  if (!fp) return nil;
  fseek(fp, 0, SEEK_END);
  long sz = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (sz <= 8 || sz > 32 * 1024 * 1024) {
    fclose(fp);
    return nil;
  }
  uint8_t* buf = static_cast<uint8_t*>(malloc(static_cast<size_t>(sz)));
  size_t n = buf ? fread(buf, 1, static_cast<size_t>(sz), fp) : 0;
  fclose(fp);
  cairo_surface_t* best = nullptr;
  if (n > 8 && memcmp(buf, "icns", 4) == 0) {
    // Choose the largest PNG representation up to 512px.
    size_t pos = 8;
    int best_w = 0;
    while (pos + 8 <= n) {
      uint32_t elen = (uint32_t(buf[pos + 4]) << 24) | (uint32_t(buf[pos + 5]) << 16) |
                      (uint32_t(buf[pos + 6]) << 8) | buf[pos + 7];
      if (elen < 8 || pos + elen > n) break;
      cairo_surface_t* s = SurfaceFromPngBytes(buf + pos + 8, elen - 8);
      if (s && cairo_image_surface_get_width(s) > best_w &&
          cairo_image_surface_get_width(s) <= 512) {
        if (best) cairo_surface_destroy(best);
        best = s;
        best_w = cairo_image_surface_get_width(s);
      } else if (s) {
        cairo_surface_destroy(s);
      }
      pos += elen;
    }
  } else if (n) {
    best = SurfaceFromPngBytes(buf, n);
  }
  free(buf);
  if (!best) return nil;
  self = [super init];
  if (self) {
    _surface = best;
    _size = NSMakeSize(cairo_image_surface_get_width(best),
                       cairo_image_surface_get_height(best));
  }
  return self;
}

- (NSSize)size { return _size; }
- (void)setSize:(NSSize)size { _size = size; }
- (void)setTemplate:(BOOL)t { _template = t; }
- (BOOL)isTemplate { return _template; }
- (NSString*)name { return _name; }
- (BOOL)isValid { return _surface != nullptr; }

- (void)drawInRect:(NSRect)rect {
  if (!_surface || !g_current_cairo) return;
  auto* s = static_cast<cairo_surface_t*>(_surface);
  double iw = cairo_image_surface_get_width(s), ih = cairo_image_surface_get_height(s);
  cairo_save(g_current_cairo);
  cairo_translate(g_current_cairo, rect.origin.x, rect.origin.y);
  cairo_scale(g_current_cairo, rect.size.width / iw, rect.size.height / ih);
  cairo_set_source_surface(g_current_cairo, s, 0, 0);
  cairo_paint(g_current_cairo);
  cairo_restore(g_current_cairo);
}

@end

// ===========================================================================
// NSMenu / NSMenuItem (model objects; this AppKit has no global menu bar)
// ===========================================================================
@interface NSMenuItem : NSObject {
 @public
  NSString* _title;
  NSString* _keyEquivalent;
  SEL _action;
  id _target;
  id _submenu;
  id _representedObject;
  NSInteger _tag;
  NSInteger _state;
  BOOL _enabled;
  BOOL _separator;
  BOOL _hidden;
  NSImage* _image;
  NSUInteger _keyMask;
}
@end

@interface NSMenu : NSObject {
 @public
  NSString* _title;
  NSMutableArray* _items;
  id _delegate;
  BOOL _autoenables;
}
@end

// Implemented in appkit_menubar.mm (global menu bar).
@interface NSApplication (DarlingMainMenu)
- (void)setMainMenu:(NSMenu*)menu;
- (NSMenu*)mainMenu;
- (void)orderFrontStandardAboutPanel:(id)sender;
@end

@implementation NSMenuItem

+ (NSMenuItem*)separatorItem {
  NSMenuItem* m = [[NSMenuItem alloc] initWithTitle:@"" action:nullptr keyEquivalent:@""];
  m->_separator = YES;
  return m;
}

+ (NSMenuItem*)sectionHeaderWithTitle:(NSString*)title {
  NSMenuItem* m = [[NSMenuItem alloc] initWithTitle:title ? title : @""
                                             action:nullptr
                                      keyEquivalent:@""];
  m->_enabled = NO;
  return m;
}

- (void)_setActionImage:(NSImage*)img { (void)img; }
- (NSMenu*)menu { return _submenu; }
- (void)setMenu:(NSMenu*)m { (void)m; }

- (instancetype)init {
  return [self initWithTitle:@"" action:nullptr keyEquivalent:@""];
}

- (instancetype)initWithTitle:(NSString*)title action:(SEL)action keyEquivalent:(NSString*)key {
  self = [super init];
  if (self) {
    _title = [title copy];
    _action = action;
    _keyEquivalent = [key copy];
    _enabled = YES;
    _keyMask = 1UL << 20;  // NSEventModifierFlagCommand
  }
  return self;
}

- (NSString*)title { return _title; }
- (void)setTitle:(NSString*)t { _title = [t copy]; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (NSString*)keyEquivalent { return _keyEquivalent; }
- (void)setKeyEquivalent:(NSString*)k { _keyEquivalent = [k copy]; }
- (void)setKeyEquivalentModifierMask:(NSUInteger)m { _keyMask = m; }
- (NSUInteger)keyEquivalentModifierMask { return _keyMask; }
- (NSMenu*)submenu { return _submenu; }
- (void)setSubmenu:(NSMenu*)m { _submenu = m; }
- (BOOL)hasSubmenu { return _submenu != nil; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)e { _enabled = e; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)h { _hidden = h; }
- (BOOL)isSeparatorItem { return _separator; }
- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)t { _tag = t; }
- (NSInteger)state { return _state; }
- (void)setState:(NSInteger)s { _state = s; }
- (id)representedObject { return _representedObject; }
- (void)setRepresentedObject:(id)o { _representedObject = o; }
- (NSImage*)image { return _image; }
- (void)setImage:(NSImage*)i { _image = i; }
- (void)setToolTip:(NSString*)t { (void)t; }

@end

@implementation NSMenu

- (instancetype)init {
  return [self initWithTitle:@""];
}

- (instancetype)initWithTitle:(NSString*)title {
  self = [super init];
  if (self) {
    _title = [title copy];
    _items = [[NSMutableArray alloc] init];
    _autoenables = YES;
  }
  return self;
}

- (NSString*)title { return _title; }
- (void)setTitle:(NSString*)t { _title = [t copy]; }
- (NSArray*)itemArray { return _items; }
- (NSInteger)numberOfItems { return static_cast<NSInteger>([_items count]); }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (void)setAutoenablesItems:(BOOL)b { _autoenables = b; }

- (NSMenuItem*)itemAtIndex:(NSInteger)index {
  return index >= 0 ? [_items objectAtIndex:static_cast<NSUInteger>(index)] : nil;
}

- (NSMenuItem*)itemWithTitle:(NSString*)title {
  for (NSMenuItem* i in _items) {
    if ([i->_title isEqualToString:title]) return i;
  }
  return nil;
}

- (NSMenuItem*)itemWithTag:(NSInteger)tag {
  for (NSMenuItem* i in _items) {
    if (i->_tag == tag) return i;
  }
  return nil;
}

- (NSInteger)indexOfItem:(NSMenuItem*)item {
  NSUInteger i = [_items indexOfObject:item];
  return i == static_cast<NSUInteger>(-1) ? -1 : static_cast<NSInteger>(i);
}

- (void)addItem:(NSMenuItem*)item {
  if (item) [_items addObject:item];
}

- (NSMenuItem*)addItemWithTitle:(NSString*)title action:(SEL)action keyEquivalent:(NSString*)key {
  NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
  [self addItem:item];
  return item;
}

- (void)insertItem:(NSMenuItem*)item atIndex:(NSInteger)index {
  if (item) [_items insertObject:item atIndex:static_cast<NSUInteger>(index < 0 ? 0 : index)];
}

- (NSMenuItem*)insertItemWithTitle:(NSString*)title
                            action:(SEL)action
                     keyEquivalent:(NSString*)key
                           atIndex:(NSInteger)index {
  NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
  [self insertItem:item atIndex:index];
  return item;
}

- (void)removeItemAtIndex:(NSInteger)index {
  if (index >= 0) [_items removeObjectAtIndex:static_cast<NSUInteger>(index)];
}

- (void)removeItem:(NSMenuItem*)item {
  [_items removeObject:item];
}

- (void)removeAllItems {
  [_items removeAllObjects];
}

@end

// ===========================================================================
// NSProgressIndicator (bar and spinning styles, determinate/indeterminate)
// ===========================================================================
@implementation NSProgressIndicator

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _maxValue = 100.0;
    _indeterminate = YES;
    _displayedWhenStopped = YES;
  }
  return self;
}

- (double)doubleValue { return _value; }
- (void)setDoubleValue:(double)v {
  _value = v;
  [self setNeedsDisplay:YES];
}
- (void)incrementBy:(double)delta { [self setDoubleValue:_value + delta]; }
- (double)minValue { return _minValue; }
- (void)setMinValue:(double)v { _minValue = v; }
- (double)maxValue { return _maxValue; }
- (void)setMaxValue:(double)v { _maxValue = v; }
- (BOOL)isIndeterminate { return _indeterminate; }
- (void)setIndeterminate:(BOOL)b {
  _indeterminate = b;
  [self setNeedsDisplay:YES];
}
- (void)setUsesThreadedAnimation:(BOOL)b { (void)b; }
- (void)setDisplayedWhenStopped:(BOOL)b { _displayedWhenStopped = b; }
- (void)setStyle:(NSUInteger)style { _spinning = style == 1; }

- (void)tick:(NSTimer*)timer {
  (void)timer;
  [self setNeedsDisplay:YES];
}

- (void)startAnimation:(id)sender {
  (void)sender;
  _animating = YES;
  if (!_timer) {
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.08
                                              target:self
                                            selector:@selector(tick:)
                                            userInfo:nil
                                             repeats:YES];
  }
  [self setNeedsDisplay:YES];
}

- (void)stopAnimation:(id)sender {
  (void)sender;
  _animating = NO;
  [_timer invalidate];
  _timer = nil;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  if (!g_current_cairo) return;
  if (!_animating && !_displayedWhenStopped) return;
  NSRect b = [self bounds];
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  double t = static_cast<double>(ts.tv_sec) + ts.tv_nsec / 1e9;
  cairo_t* cr = g_current_cairo;
  if (_spinning) {
    double cx = b.size.width / 2, cy = b.size.height / 2;
    double r = fmin(cx, cy) - 1;
    int phase = _animating ? static_cast<int>(t * 12) % 12 : 0;
    for (int i = 0; i < 12; ++i) {
      double ang = i * kPi / 6.0;
      double alpha = _animating ? 0.15 + 0.85 * ((i - phase + 12) % 12) / 11.0 : 0.25;
      cairo_set_source_rgba(cr, 0.3, 0.3, 0.32, alpha);
      cairo_set_line_width(cr, fmax(1.5, r / 5));
      cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
      cairo_move_to(cr, cx + cos(ang) * r * 0.45, cy + sin(ang) * r * 0.45);
      cairo_line_to(cr, cx + cos(ang) * r, cy + sin(ang) * r);
      cairo_stroke(cr);
    }
    return;
  }
  double h = fmin(b.size.height, 8.0);
  NSRect track = NSMakeRect(1, (b.size.height - h) / 2, b.size.width - 2, h);
  [[NSColor colorWithCalibratedRed:0.86 green:0.87 blue:0.89 alpha:1.0] setFill];
  [NSBezierPath fillRoundedRect:track xRadius:h / 2 yRadius:h / 2];
  [[NSColor colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0] setFill];
  if (_indeterminate) {
    // A moving highlight segment (barber-pole substitute).
    double seg = track.size.width / 3;
    double x = track.origin.x + fmod(t * 120.0, track.size.width + seg) - seg;
    double x0 = fmax(x, track.origin.x);
    double x1 = fmin(x + seg, track.origin.x + track.size.width);
    if (_animating && x1 > x0) {
      [NSBezierPath fillRoundedRect:NSMakeRect(x0, track.origin.y, x1 - x0, h)
                            xRadius:h / 2
                            yRadius:h / 2];
    }
  } else {
    double range = _maxValue - _minValue;
    double frac = range > 0 ? (_value - _minValue) / range : 0;
    frac = fmax(0.0, fmin(1.0, frac));
    if (frac > 0) {
      [NSBezierPath fillRoundedRect:NSMakeRect(track.origin.x, track.origin.y,
                                               track.size.width * frac, h)
                            xRadius:h / 2
                            yRadius:h / 2];
    }
  }
}

@end

// ===========================================================================
// NSSlider & NSSegmentedControl
// ===========================================================================
namespace {

double ViewOriginXInWindow(NSView* v) {
  double x = 0.0;
  for (NSView* cur = v; cur && cur->_superview; cur = cur->_superview) {
    x += cur->_frame.origin.x;
  }
  return x;
}

}  // namespace

@implementation NSSlider

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _minValue = 0.0;
    _maxValue = 100.0;
    _value = 50.0;
  }
  return self;
}

- (double)minValue { return _minValue; }
- (void)setMinValue:(double)v {
  _minValue = v;
  [self setNeedsDisplay:YES];
}
- (double)maxValue { return _maxValue; }
- (void)setMaxValue:(double)v {
  _maxValue = v;
  [self setNeedsDisplay:YES];
}
- (double)doubleValue { return _value; }
- (void)setDoubleValue:(double)v {
  if (v < _minValue) v = _minValue;
  if (v > _maxValue) v = _maxValue;
  _value = v;
  [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent*)event {
  if (!_enabled || !event) return;
  double local_x = [event locationInWindow].x - ViewOriginXInWindow(self);
  double pad = 8.0;
  double w = _bounds.size.width - pad * 2.0;
  double frac = w > 1.0 ? (local_x - pad) / w : 0.0;
  if (frac < 0.0) frac = 0.0;
  if (frac > 1.0) frac = 1.0;
  [self setDoubleValue:_minValue + frac * (_maxValue - _minValue)];
  [self sendAction:_action to:_target];
  if ([self window]) [[self window] display];
}

- (void)mouseUp:(NSEvent*)event {
  (void)event;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = [self bounds];
  double pad = 8.0;
  double track_h = 5.0;
  double track_y = (b.size.height - track_h) * 0.5;
  double track_w = b.size.width - pad * 2.0;
  if (track_w < 4.0) return;

  NSRect track = NSMakeRect(pad, track_y, track_w, track_h);
  [[NSColor colorWithCalibratedRed:0.82 green:0.84 blue:0.87 alpha:1.0] setFill];
  [NSBezierPath fillRoundedRect:track xRadius:2.5 yRadius:2.5];

  double range = _maxValue - _minValue;
  double frac = range > 0.0 ? (_value - _minValue) / range : 0.0;
  if (frac < 0.0) frac = 0.0;
  if (frac > 1.0) frac = 1.0;

  if (frac > 0.0) {
    [[NSColor colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0] setFill];
    [NSBezierPath fillRoundedRect:NSMakeRect(pad, track_y, track_w * frac, track_h)
                          xRadius:2.5
                          yRadius:2.5];
  }

  double knob_r = 7.5;
  double knob_x = pad + track_w * frac - knob_r;
  double knob_y = b.size.height * 0.5 - knob_r;
  NSRect knob = NSMakeRect(knob_x, knob_y, knob_r * 2.0, knob_r * 2.0);
  [[NSColor whiteColor] setFill];
  [NSBezierPath fillRoundedRect:knob xRadius:knob_r yRadius:knob_r];
  [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.35] setStroke];
  [NSBezierPath strokeRoundedRect:knob xRadius:knob_r yRadius:knob_r lineWidth:1.2];
}

@end

@implementation NSSegmentedControl

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _labels = [[NSMutableArray alloc] init];
    _selectedSegment = 0;
  }
  return self;
}

- (void)setSegmentCount:(NSInteger)count {
  [_labels removeAllObjects];
  for (NSInteger i = 0; i < count; ++i) {
    [_labels addObject:[NSString stringWithFormat:@"Seg %ld", static_cast<long>(i + 1)]];
  }
  [self setNeedsDisplay:YES];
}

- (NSInteger)segmentCount {
  return static_cast<NSInteger>([_labels count]);
}

- (void)setLabel:(NSString*)label forSegment:(NSInteger)segment {
  if (segment >= 0 && segment < [self segmentCount] && label) {
    [_labels removeObjectAtIndex:static_cast<NSUInteger>(segment)];
    [_labels insertObject:[label copy] atIndex:static_cast<NSUInteger>(segment)];
    [self setNeedsDisplay:YES];
  }
}

- (NSString*)labelForSegment:(NSInteger)segment {
  if (segment >= 0 && segment < [self segmentCount]) {
    return [_labels objectAtIndex:static_cast<NSUInteger>(segment)];
  }
  return @"";
}

- (void)setSelectedSegment:(NSInteger)selectedSegment {
  _selectedSegment = selectedSegment;
  [self setNeedsDisplay:YES];
}

- (NSInteger)selectedSegment {
  return _selectedSegment;
}

- (void)mouseDown:(NSEvent*)event {
  NSInteger n = [self segmentCount];
  if (!_enabled || !event || n <= 0) return;
  double local_x = [event locationInWindow].x - ViewOriginXInWindow(self);
  double seg_w = _bounds.size.width / static_cast<double>(n);
  NSInteger idx = static_cast<NSInteger>(local_x / seg_w);
  if (idx < 0) idx = 0;
  if (idx >= n) idx = n - 1;
  _selectedSegment = idx;
  [self setNeedsDisplay:YES];
  [self sendAction:_action to:_target];
  if ([self window]) [[self window] display];
}

- (void)mouseUp:(NSEvent*)event {
  (void)event;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSInteger n = [self segmentCount];
  if (n <= 0) return;
  NSRect b = NSInsetRect([self bounds], 1.0, 1.0);
  [[NSColor whiteColor] setFill];
  [NSBezierPath fillRoundedRect:b xRadius:6.0 yRadius:6.0];
  double seg_w = b.size.width / static_cast<double>(n);
  for (NSInteger i = 0; i < n; ++i) {
    NSRect sr = NSMakeRect(b.origin.x + i * seg_w, b.origin.y, seg_w, b.size.height);
    BOOL sel = (i == _selectedSegment);
    if (sel) {
      [[NSColor colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0] setFill];
      [NSBezierPath fillRoundedRect:sr xRadius:5.0 yRadius:5.0];
    } else if (i > 0) {
      [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.15] setStroke];
      [NSBezierPath strokeLineFromPoint:NSMakePoint(sr.origin.x, sr.origin.y + 3.0)
                                toPoint:NSMakePoint(sr.origin.x, sr.origin.y + sr.size.height - 3.0)
                              lineWidth:1.0];
    }
    [NSBezierPath drawText:[self labelForSegment:i]
                    inRect:sr
                      font:sel ? [NSFont boldSystemFontOfSize:12.0] : [NSFont systemFontOfSize:12.0]
                     color:sel ? [NSColor whiteColor] : [NSColor labelColor]
                 alignment:NSTextAlignmentCenter];
  }
  [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.25] setStroke];
  [NSBezierPath strokeRoundedRect:b xRadius:6.0 yRadius:6.0 lineWidth:1.0];
}

@end

// ===========================================================================
// NSTextStorage: mutable text model backing an NSTextView.
// ===========================================================================
@implementation NSTextStorage

- (NSString*)string {
  return _view ? [_view string] : @"";
}

- (NSMutableString*)mutableString {
  return [[self string] mutableCopy];
}

- (NSUInteger)length {
  return strlen([[self string] UTF8String]);
}

- (void)beginEditing { ++_editing; }

- (void)endEditing {
  if (_editing > 0) --_editing;
  [_view setNeedsDisplay:YES];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString*)str {
  NSMutableString* m = [[self string] mutableCopy];
  [m replaceCharactersInRange:range withString:str];
  [_view setString:m];
}

- (void)appendAttributedString:(id)attrString {
  NSString* s = [attrString respondsToSelector:@selector(string)] ? [attrString string] : nil;
  [self replaceCharactersInRange:NSMakeRange([self length], 0) withString:s];
}

- (void)setAttributedString:(id)attrString {
  NSString* s = [attrString respondsToSelector:@selector(string)] ? [attrString string] : @"";
  [_view setString:s];
}

- (void)setFont:(NSFont*)font { [_view setFont:font]; }
- (void)addAttribute:(NSString*)n value:(id)v range:(NSRange)r { (void)n; (void)v; (void)r; }
- (void)setAttributes:(NSDictionary*)a range:(NSRange)r { (void)a; (void)r; }

@end

namespace {

struct TextViewExtras {
  void* view;
  NSTextStorage* storage;
  BOOL scrollToEnd;
};
TextViewExtras g_text_extras[64];
size_t g_text_extra_count = 0;

TextViewExtras* ExtrasFor(NSTextView* tv) {
  for (size_t i = 0; i < g_text_extra_count; ++i) {
    if (g_text_extras[i].view == tv) return &g_text_extras[i];
  }
  if (g_text_extra_count >= 64) return nullptr;
  TextViewExtras* e = &g_text_extras[g_text_extra_count++];
  e->view = tv;
  e->storage = [[NSTextStorage alloc] init];
  e->storage->_view = tv;
  e->scrollToEnd = NO;
  return e;
}

}  // namespace

static BOOL DarlingTextViewScrollsToEnd(NSTextView* tv) {
  for (size_t i = 0; i < g_text_extra_count; ++i) {
    if (g_text_extras[i].view == tv) return g_text_extras[i].scrollToEnd;
  }
  return NO;
}

@implementation NSTextView (DarlingAdditions)

- (NSTextStorage*)textStorage {
  TextViewExtras* e = ExtrasFor(self);
  return e ? e->storage : nil;
}

- (void)scrollRangeToVisible:(NSRange)range {
  TextViewExtras* e = ExtrasFor(self);
  // Scrolling to the end keeps the newest lines visible (used for logs).
  if (e) e->scrollToEnd = range.location >= strlen([[self string] UTF8String]);
  [self setNeedsDisplay:YES];
}

- (void)setSelectable:(BOOL)flag { (void)flag; }
- (void)setRichText:(BOOL)flag { (void)flag; }
- (void)setDrawsBackground:(BOOL)flag { (void)flag; }
- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)flag { (void)flag; }
- (void)setContinuousSpellCheckingEnabled:(BOOL)flag { (void)flag; }
- (void)insertText:(id)text {
  [[self textStorage] replaceCharactersInRange:NSMakeRange([[self textStorage] length], 0)
                                    withString:text];
}

@end

// ===========================================================================
// Panels, document controller, font manager, status bar
// ===========================================================================
@interface NSSavePanel : NSWindow {
 @public
  NSString* _nameField;
}
@end

@implementation NSSavePanel

+ (NSSavePanel*)savePanel {
  return [[self alloc] initWithContentRect:NSMakeRect(200, 200, 480, 300)
                                 styleMask:15
                                   backing:2
                                     defer:NO];
}

- (void)setNameFieldStringValue:(NSString*)v { _nameField = [v copy]; }
- (NSString*)nameFieldStringValue { return _nameField; }
- (void)setAllowedFileTypes:(NSArray*)types { (void)types; }
- (void)setDirectoryURL:(id)url { (void)url; }
- (void)setCanCreateDirectories:(BOOL)b { (void)b; }
- (void)setMessage:(NSString*)m { (void)m; }
- (void)setPrompt:(NSString*)p { (void)p; }

// No interactive file browser exists in this AppKit; the panel reports
// "Cancel" (NSModalResponseCancel = 0).
- (NSInteger)runModal {
  fprintf(stderr, "[AppKit] NSSavePanel runModal: no file browser, returning Cancel\n");
  return 0;
}

- (id)URL { return nil; }

@end

@implementation NSOpenPanel (DarlingAdditions)
- (void)setAllowedFileTypes:(NSArray*)types { (void)types; }
- (void)setResolvesAliases:(BOOL)b { (void)b; }
- (void)setMessage:(NSString*)m { (void)m; }
- (void)setPrompt:(NSString*)p { (void)p; }
@end

@interface NSDocument : NSObject {
 @public
  NSMutableArray* _windowControllers;
  NSWindow* _docWindow;
  id _fileURL;
  NSString* _fileType;
}
- (NSString*)windowNibName;
- (void)makeWindowControllers;
- (void)addWindowController:(NSWindowController*)windowController;
- (NSArray*)windowControllers;
- (void)showWindows;
- (void)windowControllerDidLoadNib:(NSWindowController*)windowController;
- (void)setWindow:(NSWindow*)window;
- (NSWindow*)windowForSheet;
@end

@implementation NSDocument
- (instancetype)init {
  self = [super init];
  if (self) {
    _windowControllers = [[NSMutableArray alloc] init];
  }
  return self;
}
- (NSString*)windowNibName { return nil; }
- (void)setWindow:(NSWindow*)window { _docWindow = window; }
- (NSWindow*)windowForSheet { return _docWindow; }
- (NSArray*)windowControllers { return _windowControllers; }
- (void)addWindowController:(NSWindowController*)wc {
  if (wc && ![_windowControllers containsObject:wc]) {
    [_windowControllers addObject:wc];
  }
}
- (void)windowControllerDidLoadNib:(NSWindowController*)wc { (void)wc; }
- (void)makeWindowControllers {
  NSString* nib = [self windowNibName];
  if (nib) {
    NSUInteger before = [[NSApp windows] count];
    DarlingLoadNibNamed(nib, self, [NSBundle mainBundle]);
    NSWindowController* wc =
        [[[NSWindowController alloc] initWithWindowNibName:nib] autorelease];
    NSArray* wins = [NSApp windows];
    if ([wins count] > before) {
      NSWindow* w = [wins lastObject];
      [wc setWindow:w];
      _docWindow = w;
    }
    [self addWindowController:wc];
    [self windowControllerDidLoadNib:wc];
  }
}
- (void)showWindows {
  for (NSWindowController* wc in _windowControllers) {
    [wc showWindow:self];
  }
  if (_docWindow) [_docWindow makeKeyAndOrderFront:self];
  for (NSWindow* w in [NSApp windows]) {
    if (w && !w->_visible) [w makeKeyAndOrderFront:self];
  }
}
- (void)close {
  if (_docWindow) [_docWindow close];
}
- (BOOL)isDocumentEdited { return NO; }
- (void)updateChangeCount:(NSUInteger)change { (void)change; }
@end

@interface NSDocumentController : NSObject {
 @public
  NSMutableArray* _documents;
}
@end

@implementation NSDocumentController

+ (NSDocumentController*)sharedDocumentController {
  static NSDocumentController* c = nullptr;
  if (!c) {
    c = [[NSDocumentController alloc] init];
    c->_documents = [[NSMutableArray alloc] init];
  }
  return c;
}

- (NSArray*)documents {
  return _documents ? _documents : [NSArray array];
}

- (id)currentDocument {
  return _documents ? [_documents firstObject] : nil;
}

- (void)addDocument:(NSDocument*)document {
  if (!_documents) _documents = [[NSMutableArray alloc] init];
  if (document && ![_documents containsObject:document]) {
    [_documents addObject:document];
  }
}

- (void)removeDocument:(NSDocument*)document {
  [_documents removeObject:document];
}

- (id)openUntitledDocumentAndDisplay:(BOOL)displayDocument error:(id*)outError {
  if (outError) *outError = nil;
  Class docCls = nullptr;
  NSArray* types =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];
  if ([types isKindOfClass:[NSArray class]] && [types count] > 0) {
    NSDictionary* first = [types firstObject];
    if ([first isKindOfClass:[NSDictionary class]]) {
      NSString* cname = [first objectForKey:@"NSDocumentClass"];
      if (cname) docCls = objc_lookUpClass([cname UTF8String]);
    }
  }
  if (!docCls) docCls = objc_lookUpClass("SNDocument");
  if (!docCls) docCls = [NSDocument class];
  NSDocument* doc = [[[docCls alloc] init] autorelease];
  if (!doc) return nil;
  [self addDocument:doc];
  [doc makeWindowControllers];
  if (displayDocument) [doc showWindows];
  return doc;
}

- (void)newDocument:(id)sender {
  (void)sender;
  [self openUntitledDocumentAndDisplay:YES error:nullptr];
}

- (void)noteNewRecentDocumentURL:(id)url { (void)url; }
- (void)clearRecentDocuments:(id)sender { (void)sender; }
- (NSArray*)recentDocumentURLs { return [NSArray array]; }
- (NSUInteger)maximumRecentDocumentCount { return 10; }
- (void)setAutosavingDelay:(NSTimeInterval)delay { (void)delay; }

@end

@interface NSFontManager : NSObject
@end

@implementation NSFontManager

+ (NSFontManager*)sharedFontManager {
  static NSFontManager* m = nullptr;
  if (!m) m = [[NSFontManager alloc] init];
  return m;
}

- (NSFont*)convertFont:(NSFont*)font toSize:(CGFloat)size {
  NSFont* f = [NSFont systemFontOfSize:size];
  f->_bold = font ? font->_bold : NO;
  f->_fixedPitch = font ? font->_fixedPitch : NO;
  return f;
}

- (NSArray*)availableFonts {
  return [NSArray arrayWithObject:@"DejaVu Sans"];
}

@end

@interface NSStatusItem : NSObject {
 @public
  NSString* _title;
  NSImage* _image;
  NSMenu* _menu;
  CGFloat _length;
}
@end

@implementation NSStatusItem
- (void)setTitle:(NSString*)t { _title = [t copy]; }
- (NSString*)title { return _title; }
- (void)setImage:(NSImage*)i { _image = i; }
- (void)setMenu:(NSMenu*)m { _menu = m; }
- (NSMenu*)menu { return _menu; }
- (void)setHighlightMode:(BOOL)b { (void)b; }
- (void)setEnabled:(BOOL)b { (void)b; }
- (void)setToolTip:(NSString*)t { (void)t; }
- (CGFloat)length { return _length; }
@end

@interface NSStatusBar : NSObject
@end

@implementation NSStatusBar

+ (NSStatusBar*)systemStatusBar {
  static NSStatusBar* bar = nullptr;
  if (!bar) bar = [[NSStatusBar alloc] init];
  return bar;
}

- (NSStatusItem*)statusItemWithLength:(CGFloat)length {
  NSStatusItem* item = [[NSStatusItem alloc] init];
  item->_length = length;
  return item;
}

- (void)removeStatusItem:(NSStatusItem*)item { (void)item; }
- (CGFloat)thickness { return 22.0; }

@end

// ===========================================================================
// NSWindow / NSView / NSApplication / NSControl additions
// ===========================================================================
@implementation NSWindow (DarlingAdditions)

- (void)setFrame:(NSRect)frame display:(BOOL)flag {
  [self setFrameOrigin:frame.origin];
  (void)flag;
}

- (void)setFrame:(NSRect)frame display:(BOOL)flag animate:(BOOL)animate {
  (void)animate;
  [self setFrame:frame display:flag];
}

- (NSSize)minSize { return NSMakeSize(0, 0); }
- (NSSize)maxSize { return NSMakeSize(10000, 10000); }
- (void)setMinSize:(NSSize)s { (void)s; }
- (void)setMaxSize:(NSSize)s { (void)s; }
- (void)setShowsResizeIndicator:(BOOL)b { (void)b; }
- (void)registerForDraggedTypes:(NSArray*)types { (void)types; }
- (void)unregisterDraggedTypes {}
- (void)setReleasedWhenClosed:(BOOL)b { (void)b; }
- (void)setRestorable:(BOOL)b { (void)b; }
- (void)setFrameAutosaveName:(NSString*)n { (void)n; }
- (void)setLevel:(NSInteger)l { (void)l; }
- (void)setCollectionBehavior:(NSUInteger)b { (void)b; }
- (BOOL)isVisible { return _visible; }
- (void)orderOut:(id)sender { (void)sender; [self close]; }
- (void)performClose:(id)sender {
  (void)sender;
  if (_delegate && [_delegate respondsToSelector:@selector(windowShouldClose:)]) {
    typedef BOOL (*ShouldCloseFn)(id, SEL, id);
    if (!reinterpret_cast<ShouldCloseFn>(objc_msgSend)(_delegate, @selector(windowShouldClose:),
                                                         self)) {
      return;
    }
  }
  [self close];
  // Like the previous AppKit behaviour: closing the last window ends the
  // application's run loop.
  BOOL any_visible = NO;
  for (NSWindow* w in [NSApp windows]) {
    if (w->_visible && !any_visible) {
      any_visible = YES;
      DarlingActivateWindow(w);
    }
  }
  if (!any_visible) [NSApp stop:self];
}
- (void)makeFirstResponder:(id)r { (void)r; }
- (void)setAppearance:(id)a { (void)a; }
- (id)appearance { return [NSAppearance currentAppearance]; }

@end

@interface NSLayoutConstraint : NSObject {
 @public
  NSString* _vflFormat;
  NSDictionary* _vflViews;
  NSDictionary* _vflMetrics;
}
@end

@implementation NSLayoutConstraint

+ (NSArray*)constraintsWithVisualFormat:(NSString*)format
                                options:(NSUInteger)opts
                                metrics:(NSDictionary*)metrics
                                  views:(NSDictionary*)views {
  (void)opts;
  if (!format || !views) return [NSArray array];
  NSLayoutConstraint* c = [[NSLayoutConstraint alloc] init];
  c->_vflFormat = [format copy];
  c->_vflViews = views;
  c->_vflMetrics = metrics;
  return [NSArray arrayWithObject:c];
}

+ (instancetype)constraintWithItem:(id)view1
                         attribute:(NSInteger)attr1
                         relatedBy:(NSInteger)relation
                            toItem:(id)view2
                         attribute:(NSInteger)attr2
                        multiplier:(CGFloat)multiplier
                          constant:(CGFloat)c {
  (void)view1; (void)attr1; (void)relation;
  (void)view2; (void)attr2; (void)multiplier; (void)c;
  return [[NSLayoutConstraint alloc] init];
}

+ (void)activateConstraints:(NSArray*)constraints {
  (void)constraints;
}

- (void)setActive:(BOOL)active {
  (void)active;
}

@end

namespace {

void ApplyVflConstraintToSuperview(NSView* superview, NSLayoutConstraint* lc) {
  if (!superview || !lc || !lc->_vflFormat || !lc->_vflViews) return;
  const char* s = [lc->_vflFormat UTF8String];
  if (!s || !s[0]) return;

  bool vertical = false;
  if (s[0] == 'V' && s[1] == ':') {
    vertical = true;
    s += 2;
  } else if (s[0] == 'H' && s[1] == ':') {
    s += 2;
  }

  struct VflItem {
    NSView* view;
    double size;
    double spacing_after;
  };
  VflItem items[16];
  size_t item_count = 0;
  bool anchor_lead = false;
  bool anchor_trail = false;
  double lead_space = 0.0;

  auto parse_num = [&](const char*& p, double def_val) -> double {
    while (*p == '>' || *p == '<' || *p == '=') ++p;
    char* end = nullptr;
    double v = strtod(p, &end);
    if (end && end != p) {
      p = end;
      return v;
    }
    return def_val;
  };

  const char* p = s;
  if (*p == '|') {
    anchor_lead = true;
    ++p;
    if (*p == '-') {
      ++p;
      if (*p != '[' && *p != '|') {
        lead_space = parse_num(p, 8.0);
        if (*p == '-') ++p;
      } else {
        lead_space = 8.0;
      }
    }
  }

  while (*p && item_count < 16) {
    if (*p == '[') {
      ++p;
      const char* name_start = p;
      while (*p && *p != '(' && *p != ']') ++p;
      size_t name_len = static_cast<size_t>(p - name_start);
      char name_buf[128];
      if (name_len >= sizeof(name_buf)) name_len = sizeof(name_buf) - 1;
      memcpy(name_buf, name_start, name_len);
      name_buf[name_len] = '\0';
      NSString* key = [NSString stringWithUTF8String:name_buf];
      id vobj = [lc->_vflViews objectForKey:key];
      NSView* v = (vobj && [vobj isKindOfClass:[NSView class]])
                      ? reinterpret_cast<NSView*>(vobj)
                      : nullptr;
      double sz = 0.0;
      if (*p == '(') {
        ++p;
        sz = parse_num(p, 0.0);
        while (*p && *p != ')') ++p;
        if (*p == ')') ++p;
      }
      if (*p == ']') ++p;

      double sp = 0.0;
      if (*p == '-') {
        ++p;
        if (*p == '|') {
          anchor_trail = true;
          sp = 8.0;
          ++p;
        } else if (*p == '[') {
          sp = 8.0;
        } else {
          sp = parse_num(p, 8.0);
          if (*p == '-') ++p;
          if (*p == '|') {
            anchor_trail = true;
            ++p;
          }
        }
      } else if (*p == '|') {
        anchor_trail = true;
        ++p;
      }
      items[item_count++] = {v, sz, sp};
    } else {
      ++p;
    }
  }

  if (item_count == 0) return;
  NSRect sb = [superview bounds];
  double super_dim = vertical ? sb.size.height : sb.size.width;

  for (size_t i = 0; i < item_count; ++i) {
    if (items[i].size <= 0.0 && items[i].view) {
      NSRect vf = [items[i].view frame];
      items[i].size = vertical ? (vf.size.height > 0 ? vf.size.height : 32.0)
                               : (vf.size.width > 0 ? vf.size.width : 76.0);
    } else if (items[i].size < 76.0 && !vertical &&
               [items[i].view isKindOfClass:[NSButton class]]) {
      items[i].size = 76.0;
    }
  }

  if (anchor_trail && !anchor_lead) {
    double pos = super_dim;
    for (size_t idx = item_count; idx > 0; --idx) {
      VflItem& it = items[idx - 1];
      pos -= it.spacing_after + it.size;
      if (it.view) {
        NSRect f = [it.view frame];
        if (vertical) {
          f.origin.y = pos;
          f.size.height = it.size;
        } else {
          f.origin.x = pos;
          f.size.width = it.size;
        }
        [it.view setFrame:f];
      }
    }
  } else {
    double pos = lead_space;
    for (size_t i = 0; i < item_count; ++i) {
      VflItem& it = items[i];
      if (it.view) {
        NSRect f = [it.view frame];
        if (vertical) {
          f.origin.y = pos;
          f.size.height = it.size;
        } else {
          f.origin.x = pos;
          f.size.width = it.size;
        }
        [it.view setFrame:f];
      }
      pos += it.size + it.spacing_after;
    }
  }
}

}  // namespace

@implementation NSView (DarlingAdditions)
- (void)setToolTip:(NSString*)t { (void)t; }
- (void)registerForDraggedTypes:(NSArray*)types { (void)types; }
- (void)setAutoresizingMask:(NSUInteger)m { (void)m; }
- (void)setWantsLayer:(BOOL)b { (void)b; }
- (void)setTranslatesAutoresizingMaskIntoConstraints:(BOOL)flag {
  _translatesAutoresizingMaskOff = !flag;
}
- (BOOL)translatesAutoresizingMaskIntoConstraints {
  return !_translatesAutoresizingMaskOff;
}
- (void)addConstraint:(id)constraint {
  if (constraint) [self addConstraints:[NSArray arrayWithObject:constraint]];
}
- (void)addConstraints:(NSArray*)constraints {
  if (!_flippedNonAutoLayoutSubviews) {
    _flippedNonAutoLayoutSubviews = YES;
    double sh = _bounds.size.height;
    NSUInteger sc = [_subviews count];
    for (NSUInteger i = 0; i < sc; ++i) {
      NSView* sub = reinterpret_cast<NSView*>([_subviews objectAtIndex:i]);
      if (sub && !sub->_translatesAutoresizingMaskOff && sh > 0.0) {
        NSRect sf = [sub frame];
        sf.origin.y = sh - sf.origin.y - sf.size.height;
        [sub setFrame:sf];
      }
    }
  }
  NSUInteger n = constraints ? [constraints count] : 0;
  for (NSUInteger i = 0; i < n; ++i) {
    id c = [constraints objectAtIndex:i];
    if (c && [c isKindOfClass:[NSLayoutConstraint class]]) {
      ApplyVflConstraintToSuperview(self, reinterpret_cast<NSLayoutConstraint*>(c));
    }
  }
  if ([self window]) [self window]->_paintCount = 0;
}
@end

@implementation NSButton (DarlingAdditions)
- (void)setKeyEquivalent:(NSString*)charCode {
  MarkDefaultButton(self, charCode && [charCode isEqualToString:@"\r"]);
  [self setNeedsDisplay:YES];
}
- (NSString*)keyEquivalent { return IsDefaultButton(self) ? @"\r" : @""; }
@end

@implementation NSWorkspace (DarlingAdditions)
- (NSNotificationCenter*)notificationCenter {
  return [NSNotificationCenter defaultCenter];
}
- (NSString*)absolutePathForAppBundleWithIdentifier:(NSString*)bundleIdentifier {
  if (!bundleIdentifier) return nil;
  if ([bundleIdentifier isEqualToString:@"us.zoom.xos"]) {
    return @"/Applications/zoom.us.app";
  }
  return nil;
}
@end

@implementation NSApplication (DarlingAdditions)
- (void)setServicesProvider:(id)p { (void)p; }
- (void)registerServicesMenuSendTypes:(NSArray*)s returnTypes:(NSArray*)r { (void)s; (void)r; }
- (void)setApplicationIconImage:(NSImage*)i { (void)i; }
@end

@implementation NSControl (DarlingAdditions)
- (double)doubleValue { return [[self stringValue] doubleValue]; }
- (void)setDoubleValue:(double)v {
  [self setStringValue:[NSString stringWithFormat:@"%g", v]];
}
- (float)floatValue { return static_cast<float>([self doubleValue]); }
- (void)setFloatValue:(float)v {
  [self setStringValue:[NSString stringWithFormat:@"%g", v]];
}
- (int)intValue { return [[self stringValue] intValue]; }
- (void)setIntValue:(int)v { [self setStringValue:[NSString stringWithFormat:@"%d", v]]; }
- (NSInteger)integerValue { return [[self stringValue] integerValue]; }
- (void)setIntegerValue:(NSInteger)v {
  [self setStringValue:[NSString stringWithFormat:@"%ld", static_cast<long>(v)]];
}
- (id)objectValue { return [self stringValue]; }
- (void)setObjectValue:(id)obj {
  [self setStringValue:obj ? [obj description] : @""];
}
- (id)attributedStringValue {
  return [[[NSAttributedString alloc] initWithString:[self stringValue]] autorelease];
}
- (void)setAttributedStringValue:(id)attrStr {
  if ([attrStr respondsToSelector:@selector(string)]) {
    [self setStringValue:[attrStr string]];
  }
}
- (void)sizeToFit {}
- (void)setControlSize:(NSUInteger)s { (void)s; }
- (NSUInteger)controlSize { return 0; }
- (void)setFormatter:(id)f { (void)f; }
- (id)formatter { return nil; }
- (void)setContinuous:(BOOL)b { (void)b; }
- (void)setRefusesFirstResponder:(BOOL)b { (void)b; }
- (id)cell { return self; }
- (void)setCell:(id)c { (void)c; }
@end

// ===========================================================================
// NSPopUpButton & NSComboBox
// ===========================================================================
@interface NSPopUpButton : NSButton {
 @public
  NSMenu* _popupMenu;
  NSInteger _selectedIndex;
  BOOL _pullsDown;
}
- (NSMenu*)menu;
- (void)setMenu:(NSMenu*)menu;
- (void)addItemWithTitle:(NSString*)title;
- (void)addItemsWithTitles:(NSArray*)itemTitles;
- (void)insertItemWithTitle:(NSString*)title atIndex:(NSInteger)index;
- (void)removeAllItems;
- (void)removeItemWithTitle:(NSString*)title;
- (void)removeItemAtIndex:(NSInteger)index;
- (NSInteger)numberOfItems;
- (NSArray*)itemArray;
- (NSMenuItem*)itemAtIndex:(NSInteger)index;
- (NSMenuItem*)itemWithTitle:(NSString*)title;
- (NSMenuItem*)selectedItem;
- (NSInteger)indexOfSelectedItem;
- (NSInteger)selectedTag;
- (NSString*)titleOfSelectedItem;
- (void)selectItem:(NSMenuItem*)item;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)selectItemWithTitle:(NSString*)title;
- (BOOL)selectItemWithTag:(NSInteger)tag;
- (void)setPullsDown:(BOOL)flag;
- (BOOL)pullsDown;
@end

@implementation NSPopUpButton
- (instancetype)initWithFrame:(NSRect)frameRect pullsDown:(BOOL)flag {
  self = [super initWithFrame:frameRect];
  if (self) {
    _popupMenu = [[NSMenu alloc] initWithTitle:@"PopUp"];
    _selectedIndex = 0;
    _pullsDown = flag;
  }
  return self;
}
- (instancetype)initWithFrame:(NSRect)frameRect {
  return [self initWithFrame:frameRect pullsDown:NO];
}
- (NSMenu*)menu {
  if (!_popupMenu) _popupMenu = [[NSMenu alloc] initWithTitle:@"PopUp"];
  return _popupMenu;
}
- (void)setMenu:(NSMenu*)menu {
  _popupMenu = menu;
  if ([_popupMenu numberOfItems] > 0) {
    [self selectItemAtIndex:0];
  }
}
- (void)addItemWithTitle:(NSString*)title {
  [[self menu] addItemWithTitle:title ? title : @"" action:nullptr keyEquivalent:@""];
  if ([_popupMenu numberOfItems] == 1) [self selectItemAtIndex:0];
  [self setNeedsDisplay:YES];
}
- (void)addItemsWithTitles:(NSArray*)itemTitles {
  for (NSString* t in itemTitles) [self addItemWithTitle:t];
}
- (void)insertItemWithTitle:(NSString*)title atIndex:(NSInteger)index {
  [[self menu] insertItemWithTitle:title ? title : @""
                            action:nullptr
                     keyEquivalent:@""
                           atIndex:index];
  [self setNeedsDisplay:YES];
}
- (void)removeAllItems {
  [[self menu] removeAllItems];
  _selectedIndex = -1;
  [self setNeedsDisplay:YES];
}
- (void)removeItemWithTitle:(NSString*)title {
  NSMenuItem* it = [[self menu] itemWithTitle:title];
  if (it) [[self menu] removeItem:it];
}
- (void)removeItemAtIndex:(NSInteger)index {
  [[self menu] removeItemAtIndex:index];
}
- (NSInteger)numberOfItems { return [[self menu] numberOfItems]; }
- (NSArray*)itemArray { return [[self menu] itemArray]; }
- (NSMenuItem*)itemAtIndex:(NSInteger)index {
  return [[self menu] itemAtIndex:index];
}
- (NSMenuItem*)itemWithTitle:(NSString*)title {
  return [[self menu] itemWithTitle:title];
}
- (NSMenuItem*)lastItem {
  NSInteger n = [self numberOfItems];
  return n > 0 ? [self itemAtIndex:n - 1] : nil;
}
- (NSMenuItem*)selectedItem {
  if (_selectedIndex >= 0 && _selectedIndex < [self numberOfItems]) {
    return [self itemAtIndex:_selectedIndex];
  }
  return [self numberOfItems] > 0 ? [self itemAtIndex:0] : nil;
}
- (NSInteger)indexOfSelectedItem {
  return [self numberOfItems] > 0 ? (_selectedIndex >= 0 ? _selectedIndex : 0) : -1;
}
- (NSInteger)selectedTag {
  NSMenuItem* it = [self selectedItem];
  return it ? [it tag] : 0;
}
- (NSString*)titleOfSelectedItem {
  NSMenuItem* it = [self selectedItem];
  return it ? [it title] : [self title];
}
- (void)selectItem:(NSMenuItem*)item {
  if (!item) return;
  NSInteger idx = [[self menu] indexOfItem:item];
  if (idx >= 0) [self selectItemAtIndex:idx];
}
- (void)selectItemAtIndex:(NSInteger)index {
  if (index >= 0 && index < [self numberOfItems]) {
    _selectedIndex = index;
    NSMenuItem* it = [self itemAtIndex:index];
    if (it && [it title]) [self setTitle:[it title]];
  }
  [self setNeedsDisplay:YES];
}
- (void)selectItemWithTitle:(NSString*)title {
  NSMenuItem* it = [self itemWithTitle:title];
  if (it) [self selectItem:it];
  else if (title) [self setTitle:title];
}
- (BOOL)selectItemWithTag:(NSInteger)tag {
  NSMenuItem* it = [[self menu] itemWithTag:tag];
  if (it) {
    [self selectItem:it];
    return YES;
  }
  return NO;
}
- (void)setPullsDown:(BOOL)flag { _pullsDown = flag; }
- (BOOL)pullsDown { return _pullsDown; }
- (void)setAutoenablesItems:(BOOL)flag { [[self menu] setAutoenablesItems:flag]; }

- (void)mouseDown:(NSEvent*)event {
  (void)event;
  NSInteger n = [self numberOfItems];
  if (n > 1) {
    [self selectItemAtIndex:(_selectedIndex + 1) % n];
  }
  [self sendAction:_action to:_target];
  if ([self window]) [[self window] display];
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = NSInsetRect([self bounds], 1.0, 1.0);
  [[NSColor whiteColor] setFill];
  [NSBezierPath fillRoundedRect:b xRadius:5.0 yRadius:5.0];
  [[NSColor colorWithCalibratedRed:0.70 green:0.72 blue:0.76 alpha:1.0] setStroke];
  [NSBezierPath strokeRoundedRect:b xRadius:5.0 yRadius:5.0 lineWidth:1.0];

  double arrow_w = 20.0;
  NSRect arrowBox = NSMakeRect(b.origin.x + b.size.width - arrow_w, b.origin.y,
                               arrow_w, b.size.height);
  [[NSColor colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0] setFill];
  [NSBezierPath fillRoundedRect:arrowBox xRadius:5.0 yRadius:5.0];

  double cx = arrowBox.origin.x + arrow_w * 0.5;
  double cy = arrowBox.origin.y + arrowBox.size.height * 0.5;
  [[NSColor whiteColor] setStroke];
  [NSBezierPath strokeLineFromPoint:NSMakePoint(cx - 3.0, cy - 2.0)
                            toPoint:NSMakePoint(cx, cy - 5.0)
                          lineWidth:1.5];
  [NSBezierPath strokeLineFromPoint:NSMakePoint(cx, cy - 5.0)
                            toPoint:NSMakePoint(cx + 3.0, cy - 2.0)
                          lineWidth:1.5];
  [NSBezierPath strokeLineFromPoint:NSMakePoint(cx - 3.0, cy + 2.0)
                            toPoint:NSMakePoint(cx, cy + 5.0)
                          lineWidth:1.5];
  [NSBezierPath strokeLineFromPoint:NSMakePoint(cx, cy + 5.0)
                            toPoint:NSMakePoint(cx + 3.0, cy + 2.0)
                          lineWidth:1.5];

  NSString* label = [self titleOfSelectedItem];
  if (!label || [label length] == 0) label = [self title];
  [NSBezierPath drawText:label ? label : @""
                  inRect:NSMakeRect(b.origin.x + 8.0, b.origin.y,
                                    b.size.width - arrow_w - 10.0, b.size.height)
                    font:_font ? _font : [NSFont systemFontOfSize:12.0]
                   color:[NSColor labelColor]
               alignment:NSTextAlignmentLeft];
}
@end

@interface NSComboBox : NSTextField {
 @public
  NSMutableArray* _comboItems;
}
@end
@implementation NSComboBox
- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _comboItems = [[NSMutableArray alloc] init];
    _editable = YES;
    _bezeled = YES;
    _drawsBackground = YES;
    _backgroundColor = [NSColor whiteColor];
  }
  return self;
}
- (void)addItemWithObjectValue:(id)object {
  if (object) [_comboItems addObject:object];
}
- (void)addItemsWithObjectValues:(NSArray*)objects {
  if (objects) [_comboItems addObjectsFromArray:objects];
}
- (void)removeAllItems { [_comboItems removeAllObjects]; }
- (NSInteger)numberOfItems { return static_cast<NSInteger>([_comboItems count]); }
- (void)selectItemAtIndex:(NSInteger)index {
  if (index >= 0 && index < [self numberOfItems]) {
    [self setStringValue:[[_comboItems objectAtIndex:static_cast<NSUInteger>(index)] description]];
  }
}
- (NSInteger)indexOfSelectedItem { return 0; }
@end

// ===========================================================================
// NSTableView & NSOutlineView
// ===========================================================================
@interface NSTableHeaderCell : NSObject {
 @public
  NSString* _stringValue;
}
- (NSString*)stringValue;
- (void)setStringValue:(NSString*)s;
@end
@implementation NSTableHeaderCell
- (NSString*)stringValue { return _stringValue ? _stringValue : @""; }
- (void)setStringValue:(NSString*)s { _stringValue = [s copy]; }
- (NSString*)title { return [self stringValue]; }
- (void)setTitle:(NSString*)s { [self setStringValue:s]; }
@end

@interface NSTableColumn : NSObject {
 @public
  NSString* _identifier;
  NSString* _title;
  CGFloat _width;
  NSTableHeaderCell* _headerCell;
}
- (instancetype)initWithIdentifier:(NSString*)identifier;
- (NSString*)identifier;
- (void)setIdentifier:(NSString*)identifier;
- (NSString*)title;
- (void)setTitle:(NSString*)title;
- (CGFloat)width;
- (void)setWidth:(CGFloat)w;
- (NSTableHeaderCell*)headerCell;
@end

@implementation NSTableColumn
- (instancetype)initWithIdentifier:(NSString*)identifier {
  self = [super init];
  if (self) {
    _identifier = [identifier copy];
    _title = [identifier copy];
    _width = 140.0;
    _headerCell = [[NSTableHeaderCell alloc] init];
    [_headerCell setStringValue:_title];
  }
  return self;
}
- (instancetype)init {
  return [self initWithIdentifier:@"Column"];
}
- (NSString*)identifier { return _identifier ? _identifier : @"Column"; }
- (void)setIdentifier:(NSString*)identifier { _identifier = [identifier copy]; }
- (NSString*)title {
  if (_title && [_title length] > 0) return _title;
  if (_headerCell && [[_headerCell stringValue] length] > 0) {
    return [_headerCell stringValue];
  }
  return _identifier ? _identifier : @"";
}
- (void)setTitle:(NSString*)title {
  _title = [title copy];
  if (!_headerCell) _headerCell = [[NSTableHeaderCell alloc] init];
  [_headerCell setStringValue:_title];
}
- (CGFloat)width { return _width > 0 ? _width : 120.0; }
- (void)setWidth:(CGFloat)w { _width = w; }
- (void)setMinWidth:(CGFloat)w { (void)w; }
- (void)setMaxWidth:(CGFloat)w { (void)w; }
- (void)setEditable:(BOOL)b { (void)b; }
- (void)setResizingMask:(NSUInteger)m { (void)m; }
- (NSTableHeaderCell*)headerCell {
  if (!_headerCell) _headerCell = [[NSTableHeaderCell alloc] init];
  return _headerCell;
}
@end

@interface NSTableHeaderView : NSView
@end
@implementation NSTableHeaderView
@end

@interface NSTableCellView : NSView {
 @public
  NSTextField* _textField;
  NSImageView* _imageView;
  id _objectValue;
}
@end
@implementation NSTableCellView
- (NSTextField*)textField { return _textField; }
- (void)setTextField:(NSTextField*)tf { _textField = tf; }
- (NSImageView*)imageView { return _imageView; }
- (void)setImageView:(NSImageView*)iv { _imageView = iv; }
- (id)objectValue { return _objectValue; }
- (void)setObjectValue:(id)v { _objectValue = v; }
@end

@interface NSTableRowView : NSView
@end
@implementation NSTableRowView
@end

@interface NSTableView : NSControl {
 @public
  NSMutableArray* _tableColumns;
  id _dataSource;
  id _delegate;
  NSInteger _selectedRow;
  CGFloat _rowHeight;
  BOOL _usesAlternatingRowBackgroundColors;
}
- (void)addTableColumn:(NSTableColumn*)column;
- (NSArray*)tableColumns;
- (void)setDataSource:(id)ds;
- (id)dataSource;
- (void)setDelegate:(id)del;
- (id)delegate;
- (void)reloadData;
- (NSInteger)selectedRow;
- (NSIndexSet*)selectedRowIndexes;
- (void)selectRowIndexes:(NSIndexSet*)indexes byExtendingSelection:(BOOL)extend;
@end

@implementation NSTableView
- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _tableColumns = [[NSMutableArray alloc] init];
    _selectedRow = 0;
    _rowHeight = 22.0;
    _usesAlternatingRowBackgroundColors = YES;
  }
  return self;
}
- (void)addTableColumn:(NSTableColumn*)column {
  if (!_tableColumns) _tableColumns = [[NSMutableArray alloc] init];
  if (column) [_tableColumns addObject:column];
}
- (void)removeTableColumn:(NSTableColumn*)column {
  [_tableColumns removeObject:column];
}
- (NSArray*)tableColumns { return _tableColumns; }
- (NSInteger)numberOfColumns { return static_cast<NSInteger>([_tableColumns count]); }
- (NSTableColumn*)tableColumnWithIdentifier:(id)identifier {
  for (NSTableColumn* col in _tableColumns) {
    if ([[col identifier] isEqual:identifier]) return col;
  }
  return [_tableColumns count] > 0 ? [_tableColumns objectAtIndex:0] : nil;
}
- (void)setDataSource:(id)ds { _dataSource = ds; }
- (id)dataSource { return _dataSource; }
- (void)setDelegate:(id)del { _delegate = del; }
- (id)delegate { return _delegate; }
- (void)reloadData { [self setNeedsDisplay:YES]; }
- (NSInteger)selectedRow { return _selectedRow; }
- (NSInteger)clickedRow { return _selectedRow; }
- (NSIndexSet*)selectedRowIndexes {
  return _selectedRow >= 0
             ? [NSIndexSet indexSetWithIndex:static_cast<NSUInteger>(_selectedRow)]
             : [NSIndexSet indexSet];
}
- (void)selectRowIndexes:(NSIndexSet*)indexes byExtendingSelection:(BOOL)extend {
  (void)extend;
  if (indexes && [indexes count] > 0) {
    _selectedRow = static_cast<NSInteger>([indexes firstIndex]);
  }
  [self setNeedsDisplay:YES];
}
- (void)deselectAll:(id)sender {
  (void)sender;
  _selectedRow = -1;
  [self setNeedsDisplay:YES];
}
- (void)setRowHeight:(CGFloat)h { _rowHeight = h > 0 ? h : 22.0; }
- (CGFloat)rowHeight { return _rowHeight > 0 ? _rowHeight : 22.0; }
- (void)setUsesAlternatingRowBackgroundColors:(BOOL)b {
  _usesAlternatingRowBackgroundColors = b;
}
- (void)setHeaderView:(id)hv { (void)hv; }
- (id)headerView { return nil; }
- (void)setDoubleAction:(SEL)a { (void)a; }
- (void)setAllowsEmptySelection:(BOOL)b { (void)b; }
- (void)setAllowsMultipleSelection:(BOOL)b { (void)b; }
- (void)setIntercellSpacing:(NSSize)s { (void)s; }
- (id)makeViewWithIdentifier:(NSString*)ident owner:(id)owner {
  (void)ident; (void)owner;
  return [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 120, 22)] autorelease];
}
- (NSInteger)numberOfRows {
  if (_dataSource &&
      [_dataSource respondsToSelector:@selector(numberOfRowsInTableView:)]) {
    typedef NSInteger (*NumRowsFn)(id, SEL, id);
    return reinterpret_cast<NumRowsFn>(objc_msgSend)(
        _dataSource, @selector(numberOfRowsInTableView:), self);
  }
  return 0;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = [self bounds];
  [[NSColor whiteColor] setFill];
  [NSBezierPath fillRoundedRect:b xRadius:4.0 yRadius:4.0];

  double header_h = 22.0;
  NSUInteger ncols = [_tableColumns count];
  if (ncols > 0) {
    NSRect hr = NSMakeRect(b.origin.x, b.origin.y, b.size.width, header_h);
    [[NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0] setFill];
    [NSBezierPath fillRect:hr];
    double cx = b.origin.x + 6.0;
    for (NSUInteger i = 0; i < ncols; ++i) {
      NSTableColumn* col = [_tableColumns objectAtIndex:i];
      double cw = (i + 1 == ncols) ? (b.size.width - cx) : [col width];
      if (cw < 40.0) cw = b.size.width / static_cast<double>(ncols);
      [NSBezierPath drawText:[col title]
                      inRect:NSMakeRect(cx, b.origin.y, cw - 4.0, header_h)
                        font:[NSFont boldSystemFontOfSize:11.0]
                       color:[NSColor darkGrayColor]
                   alignment:NSTextAlignmentLeft];
      cx += cw;
    }
    [[NSColor colorWithCalibratedRed:0.80 green:0.82 blue:0.85 alpha:1.0] setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(b.origin.x, b.origin.y + header_h)
                              toPoint:NSMakePoint(b.origin.x + b.size.width,
                                                  b.origin.y + header_h)
                            lineWidth:1.0];
  } else {
    header_h = 0.0;
  }

  double rh = [self rowHeight];
  NSInteger nrows = [self numberOfRows];
  int max_rows = static_cast<int>((b.size.height - header_h) / rh);
  for (int r = 0; r < max_rows; ++r) {
    NSRect rr = NSMakeRect(b.origin.x + 1.0, b.origin.y + header_h + r * rh,
                           b.size.width - 2.0, rh);
    if (r < nrows && r == _selectedRow) {
      [[NSColor colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:0.85] setFill];
      [NSBezierPath fillRect:rr];
    } else if (r % 2 == 1) {
      [[NSColor colorWithCalibratedRed:0.96 green:0.97 blue:0.99 alpha:1.0] setFill];
      [NSBezierPath fillRect:rr];
    }
    if (r < nrows && _dataSource &&
        [_dataSource
            respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)]) {
      typedef id (*ValFn)(id, SEL, id, id, NSInteger);
      double cx = b.origin.x + 6.0;
      for (NSUInteger c = 0; c < (ncols ? ncols : 1); ++c) {
        NSTableColumn* col = ncols ? [_tableColumns objectAtIndex:c] : nil;
        double cw = col ? [col width] : (b.size.width - 12.0);
        id val = reinterpret_cast<ValFn>(objc_msgSend)(
            _dataSource, @selector(tableView:objectValueForTableColumn:row:),
            self, col, r);
        if (val && [val respondsToSelector:@selector(description)]) {
          [NSBezierPath drawText:[val description]
                          inRect:NSMakeRect(cx, rr.origin.y, cw - 4.0, rh)
                            font:[NSFont systemFontOfSize:12.0]
                           color:(r == _selectedRow) ? [NSColor whiteColor]
                                                     : [NSColor labelColor]
                       alignment:NSTextAlignmentLeft];
        }
        cx += cw;
      }
    }
  }

  [[NSColor colorWithCalibratedRed:0.76 green:0.78 blue:0.82 alpha:1.0] setStroke];
  [NSBezierPath strokeRoundedRect:NSInsetRect(b, 0.5, 0.5)
                          xRadius:4.0
                          yRadius:4.0
                        lineWidth:1.0];
}
@end

@interface NSOutlineView : NSTableView
@end
@implementation NSOutlineView
- (void)expandItem:(id)item { (void)item; }
- (void)expandItem:(id)item expandChildren:(BOOL)expandChildren {
  (void)item; (void)expandChildren;
}
- (void)collapseItem:(id)item { (void)item; }
- (id)itemAtRow:(NSInteger)row { (void)row; return nil; }
- (NSInteger)rowForItem:(id)item { (void)item; return -1; }
- (void)setOutlineTableColumn:(NSTableColumn*)tc { (void)tc; }
- (NSTableColumn*)outlineTableColumn {
  return [_tableColumns firstObject];
}
@end

// ===========================================================================
// NSTabView & NSTabViewItem
// ===========================================================================
@interface NSTabViewItem : NSObject {
 @public
  id _identifier;
  NSString* _label;
  NSView* _view;
}
- (instancetype)initWithIdentifier:(id)identifier;
- (id)identifier;
- (void)setIdentifier:(id)identifier;
- (NSString*)label;
- (void)setLabel:(NSString*)label;
- (NSView*)view;
- (void)setView:(NSView*)view;
@end

@implementation NSTabViewItem
- (instancetype)initWithIdentifier:(id)identifier {
  self = [super init];
  if (self) {
    _identifier = [identifier retain];
    if ([identifier isKindOfClass:[NSString class]] &&
        [identifier isEqualToString:@"20"]) {
      _label = @"Search Policy";
    } else {
      _label = [identifier isKindOfClass:[NSString class]] ? [identifier copy] : @"Tab";
    }
    _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
  }
  return self;
}
- (instancetype)init {
  return [self initWithIdentifier:@"Tab"];
}
- (id)identifier { return _identifier; }
- (void)setIdentifier:(id)identifier { _identifier = [identifier retain]; }
- (NSString*)label { return _label ? _label : @"Tab"; }
- (void)setLabel:(NSString*)label { _label = [label copy]; }
- (NSView*)view {
  if (!_view) _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
  return _view;
}
- (void)setView:(NSView*)view { _view = view; }
@end

@interface NSTabView : NSView {
 @public
  NSMutableArray* _tabItems;
  NSTabViewItem* _selectedItem;
  id _delegate;
  NSUInteger _tabViewType;
}
- (void)addTabViewItem:(NSTabViewItem*)tabViewItem;
- (NSArray*)tabViewItems;
- (NSInteger)numberOfTabViewItems;
- (NSTabViewItem*)tabViewItemAtIndex:(NSInteger)index;
- (NSTabViewItem*)selectedTabViewItem;
- (void)selectTabViewItem:(NSTabViewItem*)tabViewItem;
- (void)selectTabViewItemAtIndex:(NSInteger)index;
@end

@implementation NSTabView
- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _tabItems = [[NSMutableArray alloc] init];
  }
  return self;
}
- (void)syncSelectedTabSubview {
  if (!_selectedItem && [_tabItems count] > 0) {
    _selectedItem = [_tabItems objectAtIndex:0];
  }
  for (NSTabViewItem* item in _tabItems) {
    NSView* iv = [item view];
    if (!iv) continue;
    if (item == _selectedItem) {
      double bar_h = (_tabViewType == 5 || _tabViewType == 6) ? 0.0 : 28.0;
      [iv setFrame:NSMakeRect(0, bar_h, _bounds.size.width,
                              _bounds.size.height > bar_h ? _bounds.size.height - bar_h
                                                          : _bounds.size.height)];
      [iv setHidden:NO];
      if (![_subviews containsObject:iv]) {
        [self addSubview:iv];
      }
    } else {
      [iv setHidden:YES];
    }
  }
}
- (void)addTabViewItem:(NSTabViewItem*)tabViewItem {
  if (!_tabItems) _tabItems = [[NSMutableArray alloc] init];
  if (tabViewItem && ![_tabItems containsObject:tabViewItem]) {
    [_tabItems addObject:tabViewItem];
    if (!_selectedItem) _selectedItem = tabViewItem;
    [self syncSelectedTabSubview];
  }
}
- (void)removeTabViewItem:(NSTabViewItem*)tabViewItem {
  if (!tabViewItem || !_tabItems) return;
  [_tabItems removeObject:tabViewItem];
  if (_selectedItem == tabViewItem) {
    _selectedItem = [_tabItems count] > 0 ? [_tabItems objectAtIndex:0] : nil;
  }
  [self syncSelectedTabSubview];
}
- (NSInteger)indexOfTabViewItem:(NSTabViewItem*)tabViewItem {
  if (!_tabItems || !tabViewItem) return static_cast<NSInteger>(NSNotFound);
  return static_cast<NSInteger>([_tabItems indexOfObject:tabViewItem]);
}
- (NSInteger)indexOfTabViewItemWithIdentifier:(id)identifier {
  if (!_tabItems || !identifier) return static_cast<NSInteger>(NSNotFound);
  for (NSUInteger i = 0; i < [_tabItems count]; ++i) {
    NSTabViewItem* item = [_tabItems objectAtIndex:i];
    if ([[item identifier] isEqual:identifier]) {
      return static_cast<NSInteger>(i);
    }
  }
  return static_cast<NSInteger>(NSNotFound);
}
- (NSArray*)tabViewItems { return _tabItems; }
- (NSInteger)numberOfTabViewItems {
  return static_cast<NSInteger>([_tabItems count]);
}
- (NSTabViewItem*)tabViewItemAtIndex:(NSInteger)index {
  return (index >= 0 && index < [self numberOfTabViewItems])
             ? [_tabItems objectAtIndex:static_cast<NSUInteger>(index)]
             : nil;
}
- (NSTabViewItem*)selectedTabViewItem { return _selectedItem; }
- (void)selectTabViewItem:(NSTabViewItem*)tabViewItem {
  if (tabViewItem) {
    _selectedItem = tabViewItem;
    [self syncSelectedTabSubview];
    [self setNeedsDisplay:YES];
  }
}
- (void)selectTabViewItemAtIndex:(NSInteger)index {
  [self selectTabViewItem:[self tabViewItemAtIndex:index]];
}
- (void)selectTabViewItemWithIdentifier:(id)identifier {
  for (NSTabViewItem* item in _tabItems) {
    if ([[item identifier] isEqual:identifier]) {
      [self selectTabViewItem:item];
      return;
    }
  }
}
- (void)setDelegate:(id)d { _delegate = d; }
- (id)delegate { return _delegate; }
- (void)setTabViewType:(NSUInteger)t { _tabViewType = t; }
- (NSRect)contentRect {
  return NSMakeRect(0, 28, _bounds.size.width,
                    _bounds.size.height > 28 ? _bounds.size.height - 28 : _bounds.size.height);
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = [self bounds];
  NSUInteger n = [_tabItems count];
  if (n > 0 && _tabViewType != 5 && _tabViewType != 6) {
    double bar_h = 24.0;
    double tab_w = fmin(130.0, (b.size.width - 16.0) / static_cast<double>(n));
    double start_x = (b.size.width - tab_w * n) * 0.5;
    NSRect body = NSMakeRect(b.origin.x + 1.0, b.origin.y + bar_h,
                             b.size.width - 2.0, b.size.height - bar_h - 1.0);
    [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.04] setFill];
    [NSBezierPath fillRoundedRect:body xRadius:6.0 yRadius:6.0];
    [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.15] setStroke];
    [NSBezierPath strokeRoundedRect:body xRadius:6.0 yRadius:6.0 lineWidth:1.0];

    for (NSUInteger i = 0; i < n; ++i) {
      NSTabViewItem* item = [_tabItems objectAtIndex:i];
      BOOL sel = (item == _selectedItem) || (!_selectedItem && i == 0);
      NSRect tr = NSMakeRect(start_x + i * tab_w, b.origin.y + 1.0, tab_w - 2.0,
                             bar_h - 2.0);
      if (sel) {
        [[NSColor colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0] setFill];
      } else {
        [[NSColor whiteColor] setFill];
      }
      [NSBezierPath fillRoundedRect:tr xRadius:5.0 yRadius:5.0];
      [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.20] setStroke];
      [NSBezierPath strokeRoundedRect:tr xRadius:5.0 yRadius:5.0 lineWidth:1.0];
      [NSBezierPath drawText:[item label]
                      inRect:tr
                        font:sel ? [NSFont boldSystemFontOfSize:11.0]
                                 : [NSFont systemFontOfSize:11.0]
                       color:sel ? [NSColor whiteColor] : [NSColor labelColor]
                   alignment:NSTextAlignmentCenter];
    }
  }
}
@end

// ===========================================================================
// NSSplitView, NSViewController, NSSplitViewItem, NSSplitViewController,
// NSStoryboard
// ===========================================================================
@interface NSSplitView : NSView {
 @public
  BOOL _vertical;
  id _delegate;
}
- (void)setVertical:(BOOL)flag;
- (BOOL)isVertical;
- (void)adjustSubviews;
@end

@implementation NSSplitView
- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) _vertical = YES;
  return self;
}
- (void)setVertical:(BOOL)flag { _vertical = flag; }
- (BOOL)isVertical { return _vertical; }
- (void)setDividerStyle:(NSInteger)s { (void)s; }
- (void)setDelegate:(id)d { _delegate = d; }
- (id)delegate { return _delegate; }
- (void)adjustSubviews {
  NSUInteger n = [_subviews count];
  if (n == 2 && _vertical) {
    NSView* left = [_subviews objectAtIndex:0];
    NSView* right = [_subviews objectAtIndex:1];
    double lw = [left frame].size.width;
    if (lw < 140.0 || lw > _bounds.size.width - 100.0) lw = 220.0;
    [left setFrame:NSMakeRect(0, 0, lw, _bounds.size.height)];
    [right setFrame:NSMakeRect(lw + 1.0, 0,
                               _bounds.size.width > lw + 1.0
                                   ? _bounds.size.width - lw - 1.0
                                   : 200.0,
                               _bounds.size.height)];
  }
}
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  if ([_subviews count] >= 2 && _vertical) {
    NSView* left = [_subviews objectAtIndex:0];
    double div_x = [left frame].origin.x + [left frame].size.width;
    // Draw a subtle macOS source-list sidebar tint on the left pane
    [[NSColor colorWithCalibratedRed:0.91 green:0.93 blue:0.96 alpha:1.0] setFill];
    [NSBezierPath fillRect:NSMakeRect(0, 0, div_x, _bounds.size.height)];
    [[NSColor colorWithCalibratedRed:0.78 green:0.80 blue:0.84 alpha:1.0] setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(div_x, 0)
                              toPoint:NSMakePoint(div_x, _bounds.size.height)
                            lineWidth:1.0];
  }
}
@end

@interface NSViewController : NSObject {
 @public
  NSView* _view;
  NSString* _nibName;
  NSBundle* _nibBundle;
  id _representedObject;
  NSString* _title;
  NSMutableArray* _childViewControllers;
}
- (instancetype)initWithNibName:(NSString*)nibNameOrNil
                         bundle:(NSBundle*)nibBundleOrNil;
- (NSView*)view;
- (void)setView:(NSView*)view;
- (void)loadView;
- (void)viewDidLoad;
- (NSString*)nibName;
- (void)setNibName:(NSString*)n;
- (NSBundle*)nibBundle;
@end

@implementation NSViewController
- (instancetype)initWithNibName:(NSString*)nibNameOrNil
                         bundle:(NSBundle*)nibBundleOrNil {
  self = [super init];
  if (self) {
    _nibName = [nibNameOrNil copy];
    _nibBundle = nibBundleOrNil ? nibBundleOrNil : [NSBundle mainBundle];
    _childViewControllers = [[NSMutableArray alloc] init];
  }
  return self;
}
- (instancetype)init {
  return [self initWithNibName:nil bundle:nil];
}
- (NSString*)nibName { return _nibName; }
- (void)setNibName:(NSString*)n { _nibName = [n copy]; }
- (NSBundle*)nibBundle {
  return _nibBundle ? _nibBundle : [NSBundle mainBundle];
}
- (NSView*)view {
  if (!_view) {
    [self loadView];
    [self viewDidLoad];
  }
  return _view;
}
- (void)setView:(NSView*)view { _view = view; }
- (void)loadView {
  if (_nibName) {
    DarlingLoadNibNamed(_nibName, self, [self nibBundle]);
  }
  if (!_view) {
    _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 320)];
  }
}
- (void)viewDidLoad {}
- (void)viewWillAppear {}
- (void)viewDidAppear {}
- (void)setRepresentedObject:(id)o { _representedObject = o; }
- (id)representedObject { return _representedObject; }
- (void)setTitle:(NSString*)t { _title = [t copy]; }
- (NSString*)title { return _title; }
- (void)addChildViewController:(NSViewController*)child {
  if (!_childViewControllers) _childViewControllers = [[NSMutableArray alloc] init];
  if (child) [_childViewControllers addObject:child];
}
- (NSArray*)childViewControllers { return _childViewControllers; }
@end

@interface NSSplitViewItem : NSObject {
 @public
  NSViewController* _viewController;
  BOOL _collapsed;
  BOOL _canCollapse;
  double _holdingPriority;
}
+ (instancetype)splitViewItemWithViewController:(NSViewController*)viewController;
- (NSViewController*)viewController;
- (void)setViewController:(NSViewController*)vc;
@end

@implementation NSSplitViewItem
+ (instancetype)splitViewItemWithViewController:(NSViewController*)viewController {
  NSSplitViewItem* item = [[[self alloc] init] autorelease];
  item->_viewController = viewController;
  return item;
}
+ (instancetype)sidebarWithViewController:(NSViewController*)viewController {
  return [self splitViewItemWithViewController:viewController];
}
- (NSViewController*)viewController { return _viewController; }
- (void)setViewController:(NSViewController*)vc { _viewController = vc; }
- (void)setCollapsed:(BOOL)b { _collapsed = b; }
- (BOOL)isCollapsed { return _collapsed; }
- (void)setCanCollapse:(BOOL)b { _canCollapse = b; }
- (BOOL)canCollapse { return _canCollapse; }
- (void)setHoldingPriority:(double)p { _holdingPriority = p; }
- (double)holdingPriority { return _holdingPriority; }
@end

@interface NSSplitViewController : NSViewController {
 @public
  NSSplitView* _splitView;
  NSMutableArray* _splitViewItems;
}
- (NSSplitView*)splitView;
- (void)setSplitView:(NSSplitView*)sv;
- (NSArray*)splitViewItems;
- (void)setSplitViewItems:(NSArray*)items;
- (void)addSplitViewItem:(NSSplitViewItem*)item;
@end

@implementation NSSplitViewController
- (instancetype)init {
  self = [super init];
  if (self) {
    _splitViewItems = [[NSMutableArray alloc] init];
  }
  return self;
}
- (NSSplitView*)splitView {
  if (!_splitView) {
    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
  }
  return _splitView;
}
- (void)setSplitView:(NSSplitView*)sv {
  _splitView = sv;
  _view = sv;
}
- (NSView*)view {
  NSSplitView* sv = [self splitView];
  _view = sv;
  return sv;
}
- (NSArray*)splitViewItems { return _splitViewItems; }
- (void)setSplitViewItems:(NSArray*)items {
  if (!_splitViewItems) _splitViewItems = [[NSMutableArray alloc] init];
  [_splitViewItems removeAllObjects];
  NSSplitView* sv = [self splitView];
  for (NSSplitViewItem* item in items) {
    [_splitViewItems addObject:item];
    NSViewController* vc = [item viewController];
    if (vc) {
      NSView* v = [vc view];
      if (v && ![[sv subviews] containsObject:v]) {
        [sv addSubview:v];
      }
    }
  }
  [sv adjustSubviews];
}
- (void)addSplitViewItem:(NSSplitViewItem*)item {
  if (!item) return;
  if (!_splitViewItems) _splitViewItems = [[NSMutableArray alloc] init];
  [_splitViewItems addObject:item];
  NSViewController* vc = [item viewController];
  if (vc) {
    [[self splitView] addSubview:[vc view]];
    [[self splitView] adjustSubviews];
  }
}
@end

@interface _DarlingStoryboardSceneOwner : NSObject {
 @public
  id _sceneController;
}
- (void)setSceneController:(id)sc;
- (id)sceneController;
@end
@implementation _DarlingStoryboardSceneOwner
- (void)setSceneController:(id)sc { _sceneController = sc; }
- (id)sceneController { return _sceneController; }
@end

@interface NSStoryboard : NSObject {
 @public
  NSString* _name;
  NSBundle* _bundle;
}
+ (instancetype)storyboardWithName:(NSString*)name bundle:(NSBundle*)storyboardBundleOrNil;
- (id)instantiateInitialController;
- (id)instantiateControllerWithIdentifier:(NSString*)identifier;
@end

@implementation NSStoryboard
+ (instancetype)storyboardWithName:(NSString*)name
                            bundle:(NSBundle*)storyboardBundleOrNil {
  NSStoryboard* sb = [[[self alloc] init] autorelease];
  sb->_name = [name copy];
  sb->_bundle = storyboardBundleOrNil ? storyboardBundleOrNil : [NSBundle mainBundle];
  return sb;
}
+ (instancetype)mainStoryboard {
  NSString* name =
      [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSMainStoryboardFile"];
  return [self storyboardWithName:name ? name : @"Main"
                           bundle:[NSBundle mainBundle]];
}
- (id)instantiateControllerWithIdentifier:(NSString*)identifier {
  if (!identifier) return nil;
  _DarlingStoryboardSceneOwner* owner =
      [[[_DarlingStoryboardSceneOwner alloc] init] autorelease];
  DarlingLoadNibNamed(identifier, owner, _bundle);
  if ([owner sceneController]) {
    return [owner sceneController];
  }
  NSWindowController* wc =
      [[[NSWindowController alloc] initWithWindowNibName:identifier] autorelease];
  [wc loadWindow];
  return wc;
}
- (id)instantiateInitialController {
  return [self instantiateControllerWithIdentifier:@"windowController"];
}
@end

// ===========================================================================
// Additional AppKit Views, Controls, Controllers, and Graphics Classes
// ===========================================================================
@interface NSScrollView : NSView {
 @public
  NSView* _documentView;
}
- (void)setDocumentView:(NSView*)aView;
- (NSView*)documentView;
@end
@implementation NSScrollView
- (void)setDocumentView:(NSView*)aView {
  _documentView = aView;
  if (aView && ![_subviews containsObject:aView]) {
    [aView setFrame:[self bounds]];
    [self addSubview:aView];
  }
}
- (NSView*)documentView { return _documentView; }
- (NSView*)contentView { return self; }
- (NSSize)contentSize { return _bounds.size; }
- (void)setHasVerticalScroller:(BOOL)b { (void)b; }
- (void)setHasHorizontalScroller:(BOOL)b { (void)b; }
- (void)setAutohidesScrollers:(BOOL)b { (void)b; }
- (void)setBorderType:(NSUInteger)t { (void)t; }
- (void)setDrawsBackground:(BOOL)b { (void)b; }
@end

@interface NSClipView : NSView
@end
@implementation NSClipView
- (void)setDocumentView:(NSView*)v {
  if (v && ![_subviews containsObject:v]) [self addSubview:v];
}
- (NSView*)documentView { return [_subviews firstObject]; }
@end

@interface NSScroller : NSControl
@end
@implementation NSScroller
+ (CGFloat)scrollerWidthForControlSize:(NSUInteger)cs scrollerStyle:(NSInteger)ss {
  (void)cs; (void)ss;
  return 15.0;
}
@end

@interface NSLevelIndicator : NSControl {
 @public
  double _minValue;
  double _maxValue;
  double _warningValue;
  double _criticalValue;
  double _val;
}
@end
@implementation NSLevelIndicator
- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _minValue = 0.0;
    _maxValue = 10.0;
    _val = 6.0;
  }
  return self;
}
- (double)minValue { return _minValue; }
- (void)setMinValue:(double)v { _minValue = v; }
- (double)maxValue { return _maxValue; }
- (void)setMaxValue:(double)v { _maxValue = v; }
- (double)warningValue { return _warningValue; }
- (void)setWarningValue:(double)v { _warningValue = v; }
- (double)criticalValue { return _criticalValue; }
- (void)setCriticalValue:(double)v { _criticalValue = v; }
- (double)doubleValue { return _val; }
- (void)setDoubleValue:(double)v {
  _val = v;
  [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = NSInsetRect([self bounds], 1.0, 2.0);
  int segs = _maxValue > 0 ? static_cast<int>(_maxValue) : 8;
  if (segs > 16) segs = 16;
  double sw = (b.size.width - (segs - 1) * 2.0) / segs;
  for (int i = 0; i < segs; ++i) {
    NSRect sr = NSMakeRect(b.origin.x + i * (sw + 2.0), b.origin.y, sw, b.size.height);
    if (i < static_cast<int>(_val)) {
      [[NSColor colorWithCalibratedRed:0.20 green:0.78 blue:0.35 alpha:1.0] setFill];
    } else {
      [[NSColor colorWithCalibratedRed:0.85 green:0.86 blue:0.88 alpha:1.0] setFill];
    }
    [NSBezierPath fillRoundedRect:sr xRadius:2.0 yRadius:2.0];
  }
}
@end

@interface NSVisualEffectView : NSView {
 @public
  NSInteger _material;
  NSInteger _blendingMode;
  NSInteger _state;
}
@end
@implementation NSVisualEffectView
- (void)setMaterial:(NSInteger)m { _material = m; }
- (NSInteger)material { return _material; }
- (void)setBlendingMode:(NSInteger)m { _blendingMode = m; }
- (NSInteger)blendingMode { return _blendingMode; }
- (void)setState:(NSInteger)s { _state = s; }
- (NSInteger)state { return _state; }
@end

@interface NSStackView : NSView {
 @public
  NSInteger _orientation;
  CGFloat _spacing;
}
@end
@implementation NSStackView
+ (instancetype)stackViewWithViews:(NSArray*)views {
  NSStackView* sv = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)] autorelease];
  for (NSView* v in views) [sv addSubview:v];
  return sv;
}
- (void)setOrientation:(NSInteger)o { _orientation = o; }
- (void)setSpacing:(CGFloat)s { _spacing = s; }
- (void)setAlignment:(NSInteger)a { (void)a; }
- (void)setDistribution:(NSInteger)d { (void)d; }
- (void)addArrangedSubview:(NSView*)v { [self addSubview:v]; }
- (NSArray*)arrangedSubviews { return _subviews; }
@end

@interface NSCollectionView : NSView {
 @public
  id _dataSource;
  id _delegate;
  NSArray* _content;
}
@end
@implementation NSCollectionView
- (void)setDataSource:(id)ds { _dataSource = ds; }
- (id)dataSource { return _dataSource; }
- (void)setDelegate:(id)d { _delegate = d; }
- (id)delegate { return _delegate; }
- (void)setContent:(NSArray*)c { _content = c; }
- (NSArray*)content { return _content; }
- (void)reloadData { [self setNeedsDisplay:YES]; }
- (void)setSelectable:(BOOL)b { (void)b; }
@end

@interface NSDatePicker : NSControl
@end
@implementation NSDatePicker
- (void)setDateValue:(id)d { (void)d; }
- (id)dateValue { return [NSDate date]; }
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = NSInsetRect([self bounds], 0.5, 0.5);
  [[NSColor whiteColor] setFill];
  [NSBezierPath fillRoundedRect:b xRadius:4.0 yRadius:4.0];
  [[NSColor colorWithCalibratedRed:0.72 green:0.74 blue:0.78 alpha:1.0] setStroke];
  [NSBezierPath strokeRoundedRect:b xRadius:4.0 yRadius:4.0 lineWidth:1.0];
  [NSBezierPath drawText:@"2026-06-15 12:00"
                  inRect:NSInsetRect(b, 6.0, 2.0)
                    font:[NSFont systemFontOfSize:12.0]
                   color:[NSColor labelColor]
               alignment:NSTextAlignmentLeft];
}
@end

@interface NSColorWell : NSControl {
 @public
  NSColor* _color;
}
@end
@implementation NSColorWell
- (NSColor*)color {
  return _color ? _color : [NSColor colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0];
}
- (void)setColor:(NSColor*)color {
  _color = color;
  [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = NSInsetRect([self bounds], 2.0, 2.0);
  [[self color] setFill];
  [NSBezierPath fillRoundedRect:b xRadius:4.0 yRadius:4.0];
  [[NSColor darkGrayColor] setStroke];
  [NSBezierPath strokeRoundedRect:b xRadius:4.0 yRadius:4.0 lineWidth:1.0];
}
@end

@interface NSToolbarItem : NSObject {
 @public
  NSString* _itemIdentifier;
  NSString* _label;
  NSString* _paletteLabel;
  NSString* _toolTip;
  NSImage* _image;
  NSView* _view;
  id _target;
  SEL _action;
  BOOL _enabled;
  NSInteger _tag;
}
- (instancetype)initWithItemIdentifier:(NSString*)itemIdentifier;
@end
@implementation NSToolbarItem
- (instancetype)initWithItemIdentifier:(NSString*)itemIdentifier {
  self = [super init];
  if (self) {
    _itemIdentifier = [itemIdentifier copy];
    _enabled = YES;
  }
  return self;
}
- (NSString*)itemIdentifier { return _itemIdentifier; }
- (void)setLabel:(NSString*)l { _label = [l copy]; }
- (NSString*)label { return _label ? _label : @""; }
- (void)setPaletteLabel:(NSString*)l { _paletteLabel = [l copy]; }
- (NSString*)paletteLabel { return _paletteLabel ? _paletteLabel : [self label]; }
- (void)setToolTip:(NSString*)t { _toolTip = [t copy]; }
- (void)setImage:(NSImage*)i { _image = i; }
- (NSImage*)image { return _image; }
- (void)setView:(NSView*)v { _view = v; }
- (NSView*)view { return _view; }
- (void)setTarget:(id)t { _target = t; }
- (id)target { return _target; }
- (void)setAction:(SEL)a { _action = a; }
- (SEL)action { return _action; }
- (void)setEnabled:(BOOL)b { _enabled = b; }
- (BOOL)isEnabled { return _enabled; }
- (void)setTag:(NSInteger)t { _tag = t; }
- (NSInteger)tag { return _tag; }
- (void)setMinSize:(NSSize)s { (void)s; }
- (void)setMaxSize:(NSSize)s { (void)s; }
@end

@interface NSToolbar : NSObject {
 @public
  NSString* _identifier;
  id _delegate;
  NSMutableArray* _items;
}
- (instancetype)initWithIdentifier:(NSString*)identifier;
@end
@implementation NSToolbar
- (instancetype)initWithIdentifier:(NSString*)identifier {
  self = [super init];
  if (self) {
    _identifier = [identifier copy];
    _items = [[NSMutableArray alloc] init];
  }
  return self;
}
- (void)setDelegate:(id)d { _delegate = d; }
- (id)delegate { return _delegate; }
- (void)setDisplayMode:(NSUInteger)m { (void)m; }
- (void)setSizeMode:(NSUInteger)m { (void)m; }
- (void)setAllowsUserCustomization:(BOOL)b { (void)b; }
- (void)setAutosavesConfiguration:(BOOL)b { (void)b; }
- (void)setVisible:(BOOL)b { (void)b; }
- (BOOL)isVisible { return YES; }
- (NSArray*)items { return _items; }
- (void)validateVisibleItems {}
@end

@interface NSPopover : NSObject {
 @public
  NSViewController* _contentViewController;
  NSInteger _behavior;
}
@end
@implementation NSPopover
- (void)setContentViewController:(NSViewController*)vc { _contentViewController = vc; }
- (NSViewController*)contentViewController { return _contentViewController; }
- (void)setBehavior:(NSInteger)b { _behavior = b; }
- (void)setAnimates:(BOOL)b { (void)b; }
- (void)showRelativeToRect:(NSRect)positioningRect
                    ofView:(NSView*)positioningView
             preferredEdge:(NSUInteger)preferredEdge {
  (void)positioningRect; (void)positioningView; (void)preferredEdge;
}
- (void)performClose:(id)sender { (void)sender; }
- (void)close {}
- (BOOL)isShown { return NO; }
@end

@interface NSObjectController : NSObject {
 @public
  id _content;
}
@end
@implementation NSObjectController
- (void)setContent:(id)c { _content = c; }
- (id)content { return _content; }
- (NSArray*)selectedObjects {
  return _content ? [NSArray arrayWithObject:_content] : [NSArray array];
}
@end

@interface NSArrayController : NSObjectController {
 @public
  NSMutableArray* _arrangedObjects;
}
@end
@implementation NSArrayController
- (instancetype)init {
  self = [super init];
  if (self) _arrangedObjects = [[NSMutableArray alloc] init];
  return self;
}
- (NSArray*)arrangedObjects {
  return _arrangedObjects ? _arrangedObjects : [NSArray array];
}
- (void)addObject:(id)obj {
  if (!_arrangedObjects) _arrangedObjects = [[NSMutableArray alloc] init];
  if (obj) [_arrangedObjects addObject:obj];
}
- (void)removeObject:(id)obj { [_arrangedObjects removeObject:obj]; }
- (void)rearrangeObjects {}
- (NSUInteger)selectionIndex { return 0; }
- (BOOL)setSelectionIndex:(NSUInteger)idx { (void)idx; return YES; }
@end

@interface NSUserDefaultsController : NSObject
@end
@implementation NSUserDefaultsController
+ (instancetype)sharedUserDefaultsController {
  static NSUserDefaultsController* c = nil;
  if (!c) c = [[NSUserDefaultsController alloc] init];
  return c;
}
- (id)values { return [NSUserDefaults standardUserDefaults]; }
- (NSUserDefaults*)defaults { return [NSUserDefaults standardUserDefaults]; }
@end

@interface NSScreen : NSObject
@end
@implementation NSScreen
+ (NSScreen*)mainScreen {
  static NSScreen* s = nil;
  if (!s) s = [[NSScreen alloc] init];
  return s;
}
+ (NSArray*)screens {
  return [NSArray arrayWithObject:[self mainScreen]];
}
+ (NSScreen*)deepestScreen { return [self mainScreen]; }
- (NSRect)frame { return NSMakeRect(0.0, 0.0, 1024.0, 768.0); }
- (NSRect)visibleFrame { return NSMakeRect(0.0, 0.0, 1024.0, 740.0); }
- (CGFloat)backingScaleFactor { return 1.0; }
- (NSDictionary*)deviceDescription {
  id key = @"NSScreenNumber";
  id val = [NSNumber numberWithInt:1];
  return [NSDictionary dictionaryWithObjects:&val forKeys:&key count:1];
}
@end

@interface NSCursor : NSObject
@end
@implementation NSCursor
+ (NSCursor*)currentCursor {
  static NSCursor* c = nil;
  if (!c) c = [[NSCursor alloc] init];
  return c;
}
+ (NSCursor*)arrowCursor { return [self currentCursor]; }
+ (NSCursor*)IBeamCursor { return [self currentCursor]; }
+ (NSCursor*)pointingHandCursor { return [self currentCursor]; }
+ (NSCursor*)crosshairCursor { return [self currentCursor]; }
+ (NSCursor*)openHandCursor { return [self currentCursor]; }
+ (NSCursor*)closedHandCursor { return [self currentCursor]; }
+ (void)hide {}
+ (void)unhide {}
+ (void)pop {}
- (instancetype)initWithImage:(NSImage*)newImage hotSpot:(NSPoint)aPoint {
  (void)newImage; (void)aPoint;
  return [self init];
}
- (void)set {}
- (void)push {}
- (void)pop {}
@end

@interface NSPasteboard : NSObject {
 @public
  NSMutableDictionary* _strings;
}
@end
@implementation NSPasteboard
+ (NSPasteboard*)generalPasteboard {
  static NSPasteboard* pb = nil;
  if (!pb) {
    pb = [[NSPasteboard alloc] init];
    pb->_strings = [[NSMutableDictionary alloc] init];
  }
  return pb;
}
+ (NSPasteboard*)pasteboardWithName:(NSString*)name {
  (void)name;
  return [self generalPasteboard];
}
- (NSInteger)clearContents {
  [_strings removeAllObjects];
  return 1;
}
- (NSInteger)declareTypes:(NSArray*)newTypes owner:(id)newOwner {
  (void)newTypes; (void)newOwner;
  return 1;
}
- (BOOL)setString:(NSString*)string forType:(NSString*)dataType {
  if (string && dataType) [_strings setObject:string forKey:dataType];
  return YES;
}
- (NSString*)stringForType:(NSString*)dataType {
  return dataType ? [_strings objectForKey:dataType] : nil;
}
- (BOOL)setData:(NSData*)data forType:(NSString*)dataType {
  (void)data; (void)dataType;
  return YES;
}
- (NSData*)dataForType:(NSString*)dataType {
  (void)dataType;
  return nil;
}
- (BOOL)writeObjects:(NSArray*)objects {
  (void)objects;
  return YES;
}
- (NSArray*)types {
  return _strings ? [_strings allKeys] : [NSArray array];
}
@end

@interface NSColorSpace : NSObject
@end
@implementation NSColorSpace
+ (NSColorSpace*)sRGBColorSpace {
  static NSColorSpace* cs = nil;
  if (!cs) cs = [[NSColorSpace alloc] init];
  return cs;
}
+ (NSColorSpace*)genericRGBColorSpace { return [self sRGBColorSpace]; }
+ (NSColorSpace*)deviceRGBColorSpace { return [self sRGBColorSpace]; }
+ (NSColorSpace*)genericGrayColorSpace { return [self sRGBColorSpace]; }
+ (NSColorSpace*)deviceGrayColorSpace { return [self sRGBColorSpace]; }
+ (NSColorSpace*)displayP3ColorSpace { return [self sRGBColorSpace]; }
- (NSString*)localizedName { return @"sRGB IEC61966-2.1"; }
- (void*)CGColorSpace {
  static int dummy_cs = 1;
  return &dummy_cs;
}
@end

@interface NSImageRep : NSObject {
 @public
  NSSize _size;
  NSInteger _pixelsWide;
  NSInteger _pixelsHigh;
}
@end
@implementation NSImageRep
- (NSSize)size { return _size; }
- (void)setSize:(NSSize)aSize { _size = aSize; }
- (NSInteger)pixelsWide { return _pixelsWide > 0 ? _pixelsWide : 64; }
- (void)setPixelsWide:(NSInteger)w { _pixelsWide = w; }
- (NSInteger)pixelsHigh { return _pixelsHigh > 0 ? _pixelsHigh : 64; }
- (void)setPixelsHigh:(NSInteger)h { _pixelsHigh = h; }
- (BOOL)drawInRect:(NSRect)rect { (void)rect; return YES; }
@end

@interface NSBitmapImageRep : NSImageRep {
 @public
  unsigned char* _bitmapData;
  NSInteger _bytesPerRow;
}
@end
@implementation NSBitmapImageRep
- (instancetype)initWithBitmapDataPlanes:(unsigned char**)planes
                              pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height
                           bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp
                                hasAlpha:(BOOL)alpha
                                isPlanar:(BOOL)isPlanar
                          colorSpaceName:(NSString*)colorSpaceName
                             bytesPerRow:(NSInteger)rBytes
                            bitsPerPixel:(NSInteger)pBits {
  (void)planes; (void)bps; (void)spp; (void)alpha; (void)isPlanar;
  (void)colorSpaceName; (void)pBits;
  self = [super init];
  if (self) {
    _pixelsWide = width > 0 ? width : 64;
    _pixelsHigh = height > 0 ? height : 64;
    _size = NSMakeSize(_pixelsWide, _pixelsHigh);
    _bytesPerRow = rBytes > 0 ? rBytes : (_pixelsWide * 4);
    _bitmapData = static_cast<unsigned char*>(
        calloc(static_cast<size_t>(_pixelsHigh), static_cast<size_t>(_bytesPerRow)));
  }
  return self;
}
- (instancetype)initWithCGImage:(void*)cgImage {
  (void)cgImage;
  return [self initWithBitmapDataPlanes:nullptr
                             pixelsWide:64
                             pixelsHigh:64
                          bitsPerSample:8
                        samplesPerPixel:4
                               hasAlpha:YES
                               isPlanar:NO
                         colorSpaceName:@"NSCalibratedRGBColorSpace"
                            bytesPerRow:256
                           bitsPerPixel:32];
}
- (unsigned char*)bitmapData { return _bitmapData; }
- (NSInteger)bytesPerRow { return _bytesPerRow; }
- (void*)CGImage {
  static int dummy_img = 1;
  return &dummy_img;
}
- (NSColor*)colorAtX:(NSInteger)x y:(NSInteger)y {
  (void)x; (void)y;
  return [NSColor colorWithCalibratedRed:0.25 green:0.55 blue:0.88 alpha:1.0];
}
@end

@interface NSGraphicsContext : NSObject
@end
@implementation NSGraphicsContext
+ (NSGraphicsContext*)currentContext {
  static NSGraphicsContext* ctx = nil;
  if (!ctx) ctx = [[NSGraphicsContext alloc] init];
  return ctx;
}
+ (void)saveGraphicsState {
  if (g_current_cairo) cairo_save(g_current_cairo);
}
+ (void)restoreGraphicsState {
  if (g_current_cairo) cairo_restore(g_current_cairo);
}
- (void*)CGContext {
  static int dummy_cg = 1;
  return &dummy_cg;
}
- (void*)graphicsPort { return [self CGContext]; }
- (BOOL)isFlipped { return YES; }
- (void)setImageInterpolation:(NSUInteger)interp { (void)interp; }
- (void)setShouldAntialias:(BOOL)b { (void)b; }
@end

@interface NSAffineTransform : NSObject
@end
@implementation NSAffineTransform
+ (NSAffineTransform*)transform { return [[[self alloc] init] autorelease]; }
- (void)translateXBy:(CGFloat)deltaX yBy:(CGFloat)deltaY {
  if (g_current_cairo) cairo_translate(g_current_cairo, deltaX, deltaY);
}
- (void)scaleBy:(CGFloat)scale {
  if (g_current_cairo) cairo_scale(g_current_cairo, scale, scale);
}
- (void)scaleXBy:(CGFloat)scaleX yBy:(CGFloat)scaleY {
  if (g_current_cairo) cairo_scale(g_current_cairo, scaleX, scaleY);
}
- (void)rotateByDegrees:(CGFloat)angle { (void)angle; }
- (void)rotateByRadians:(CGFloat)angle { (void)angle; }
- (void)concat {}
- (void)set {}
@end

@interface NSParagraphStyle : NSObject {
 @public
  NSInteger _alignment;
  NSUInteger _lineBreakMode;
}
@end
@interface NSMutableParagraphStyle : NSParagraphStyle
@end
@implementation NSParagraphStyle
+ (NSParagraphStyle*)defaultParagraphStyle {
  static NSParagraphStyle* ps = nil;
  if (!ps) ps = [[NSParagraphStyle alloc] init];
  return ps;
}
- (NSInteger)alignment { return _alignment; }
- (NSUInteger)lineBreakMode { return _lineBreakMode; }
- (id)copy { return [self retain]; }
- (id)mutableCopy { return [[NSMutableParagraphStyle alloc] init]; }
@end
@implementation NSMutableParagraphStyle
- (void)setAlignment:(NSInteger)alignment { _alignment = alignment; }
- (void)setLineBreakMode:(NSUInteger)mode { _lineBreakMode = mode; }
- (void)setLineSpacing:(CGFloat)s { (void)s; }
- (void)setParagraphSpacing:(CGFloat)s { (void)s; }
@end

@interface NSLayoutManager : NSObject
@end
@implementation NSLayoutManager
- (void)addTextContainer:(id)tc { (void)tc; }
@end

@interface NSTextContainer : NSObject
@end
@implementation NSTextContainer
- (instancetype)initWithContainerSize:(NSSize)size {
  (void)size;
  return [self init];
}
- (void)setWidthTracksTextView:(BOOL)b { (void)b; }
- (void)setHeightTracksTextView:(BOOL)b { (void)b; }
@end

@interface NSResponder : NSObject
@end
@implementation NSResponder
@end

@interface NSPanel : NSWindow
@end
@implementation NSPanel
- (void)setFloatingPanel:(BOOL)b { (void)b; }
- (void)setBecomesKeyOnlyIfNeeded:(BOOL)b { (void)b; }
- (void)setWorksWhenModal:(BOOL)b { (void)b; }
@end

@interface NSAnimationContext : NSObject
@end
@implementation NSAnimationContext
+ (NSAnimationContext*)currentContext {
  static NSAnimationContext* c = nil;
  if (!c) c = [[NSAnimationContext alloc] init];
  return c;
}
+ (void)beginGrouping {}
+ (void)endGrouping {}
- (void)setDuration:(NSTimeInterval)d { (void)d; }
@end

@interface NSNib : NSObject {
 @public
  NSString* _nibName;
  NSBundle* _bundle;
}
@end
@implementation NSNib
- (instancetype)initWithNibNamed:(NSString*)nibName bundle:(NSBundle*)bundle {
  self = [super init];
  if (self) {
    _nibName = [nibName copy];
    _bundle = bundle ? bundle : [NSBundle mainBundle];
  }
  return self;
}
- (BOOL)instantiateWithOwner:(id)owner topLevelObjects:(NSArray**)topLevelObjects {
  if (topLevelObjects) *topLevelObjects = [NSArray array];
  return DarlingLoadNibNamed(_nibName, owner, _bundle);
}
@end

@implementation NSBundle (DarlingNibAdditions)
+ (BOOL)loadNibNamed:(NSString*)nibName owner:(id)owner {
  return DarlingLoadNibNamed(nibName, owner, [NSBundle mainBundle]);
}
- (BOOL)loadNibNamed:(NSString*)nibName
               owner:(id)owner
     topLevelObjects:(NSArray**)topLevelObjects {
  if (topLevelObjects) *topLevelObjects = [NSArray array];
  return DarlingLoadNibNamed(nibName, owner, self);
}
@end

@implementation NSWindow (DarlingStoryboardAdditions)
- (void)setContentViewController:(NSViewController*)vc {
  if (!vc) return;
  NSView* v = [vc view];
  if (v && _contentView) {
    [v setFrame:[_contentView bounds]];
    if ([v isKindOfClass:[NSSplitView class]]) {
      [static_cast<NSSplitView*>(v) adjustSubviews];
    }
    if (![[_contentView subviews] containsObject:v]) {
      [_contentView addSubview:v];
    }
    _needsDisplay = YES;
  }
}
- (NSViewController*)contentViewController { return nil; }
- (void)setToolbar:(id)tb { (void)tb; }
- (id)toolbar { return nil; }
- (void)setTitlebarAppearsTransparent:(BOOL)b { (void)b; }
- (void)setTitleVisibility:(NSInteger)v { (void)v; }
- (void)setMovableByWindowBackground:(BOOL)b { (void)b; }
- (void)setOpaque:(BOOL)b { (void)b; }
- (void)setHasShadow:(BOOL)b { (void)b; }
- (void)setAlphaValue:(CGFloat)a { (void)a; }
- (CGFloat)alphaValue { return 1.0; }
- (CGFloat)backingScaleFactor { return 1.0; }
- (NSScreen*)screen { return [NSScreen mainScreen]; }
- (NSPoint)mouseLocationOutsideOfEventStream { return NSMakePoint(200.0, 200.0); }
- (NSRect)contentRectForFrameRect:(NSRect)f { return f; }
- (NSRect)frameRectForContentRect:(NSRect)c { return c; }
- (BOOL)isKeyWindow { return NSApp && NSApp->_keyWindow == self; }
- (BOOL)isMainWindow { return [self isKeyWindow]; }
- (BOOL)isMiniaturized { return NO; }
- (BOOL)isZoomed { return NO; }
- (void)deminiaturize:(id)sender { (void)sender; }
- (id)firstResponder { return self; }
- (id)windowController { return nil; }
- (void)setWindowController:(id)wc { (void)wc; }
- (void)setInitialFirstResponder:(NSView*)view { (void)view; }
- (void)beginSheet:(NSWindow*)sheetWindow completionHandler:(void*)handler {
  (void)handler;
  if (sheetWindow) [sheetWindow makeKeyAndOrderFront:self];
}
- (void)endSheet:(NSWindow*)sheetWindow {
  if (sheetWindow) [sheetWindow close];
}
@end

@implementation NSView (DarlingMoreViewMethods)
- (BOOL)isFlipped { return YES; }
- (BOOL)isHiddenOrHasHiddenAncestor { return _hidden; }
- (void)setFrameOrigin:(NSPoint)newOrigin {
  NSRect f = _frame;
  f.origin = newOrigin;
  [self setFrame:f];
}
- (void)setFrameSize:(NSSize)newSize {
  NSRect f = _frame;
  f.size = newSize;
  [self setFrame:f];
}
- (void)setBoundsOrigin:(NSPoint)newOrigin { _bounds.origin = newOrigin; }
- (void)setBoundsSize:(NSSize)newSize { _bounds.size = newSize; }
- (void)removeFromSuperview {
  if (_superview && _superview->_subviews) {
    [_superview->_subviews removeObject:self];
    _superview = nil;
  }
}
- (NSPoint)convertPoint:(NSPoint)aPoint fromView:(NSView*)aView {
  (void)aView;
  return aPoint;
}
- (NSPoint)convertPoint:(NSPoint)aPoint toView:(NSView*)aView {
  (void)aView;
  return aPoint;
}
- (NSRect)convertRect:(NSRect)aRect fromView:(NSView*)aView {
  (void)aView;
  return aRect;
}
- (NSRect)convertRect:(NSRect)aRect toView:(NSView*)aView {
  (void)aView;
  return aRect;
}
- (void)setNeedsLayout:(BOOL)b { (void)b; }
- (void)layoutSubtreeIfNeeded {}
- (void)displayIfNeeded { [self display]; }
- (void)setNeedsDisplayInRect:(NSRect)invalidRect {
  (void)invalidRect;
  [self setNeedsDisplay:YES];
}
- (void)lockFocus {}
- (void)unlockFocus {}
- (id)enclosingScrollView { return _superview; }
- (id)animator { return self; }
- (void)setAlphaValue:(CGFloat)a { (void)a; }
- (CGFloat)alphaValue { return 1.0; }
- (id)layer { return nil; }
- (void)setLayer:(id)l { (void)l; }
- (void)setNextKeyView:(NSView*)next { (void)next; }
- (NSView*)nextKeyView { return nil; }
@end

@implementation NSTextField (DarlingMoreMethods)
+ (instancetype)wrappingLabelWithString:(NSString*)stringValue {
  return [self labelWithString:stringValue];
}
+ (instancetype)textFieldWithString:(NSString*)stringValue {
  NSTextField* tf = [self labelWithString:stringValue];
  [tf setEditable:YES];
  [tf setBezeled:YES];
  [tf setDrawsBackground:YES];
  return tf;
}
- (void)setPlaceholderString:(NSString*)s {
  if ((!_stringValue || [_stringValue length] == 0) && s) {
    _stringValue = [s copy];
  }
}
- (NSString*)placeholderString { return @""; }
- (void)setBezelStyle:(NSUInteger)s { (void)s; }
- (void)setUsesSingleLineMode:(BOOL)b { (void)b; }
- (void)setLineBreakMode:(NSUInteger)m { (void)m; }
- (void)setMaximumNumberOfLines:(NSInteger)n { (void)n; }
- (void)setPreferredMaxLayoutWidth:(CGFloat)w { (void)w; }
- (void)setDelegate:(id)d { (void)d; }
- (id)delegate { return nil; }
- (void)selectText:(id)sender { (void)sender; }
@end

@implementation NSImageView (DarlingMoreMethods)
+ (instancetype)imageViewWithImage:(NSImage*)image {
  NSImageView* iv =
      [[[self alloc] initWithFrame:NSMakeRect(0, 0, 48, 48)] autorelease];
  [iv setImage:image];
  return iv;
}
- (void)setImage:(NSImage*)newImage {
  if (newImage && newImage->_surface) {
    _imageSurface =
        cairo_surface_reference(static_cast<cairo_surface_t*>(newImage->_surface));
  }
  [self setNeedsDisplay:YES];
}
- (NSImage*)image { return nil; }
- (void)setImageScaling:(NSUInteger)s { (void)s; }
- (void)setImageAlignment:(NSUInteger)a { (void)a; }
- (void)setImageFrameStyle:(NSUInteger)s { (void)s; }
- (void)setEditable:(BOOL)b { (void)b; }
@end

@implementation NSImage (DarlingMoreMethods)
+ (instancetype)imageWithSystemSymbolName:(NSString*)symbolName
                 accessibilityDescription:(NSString*)description {
  (void)description;
  return [self imageNamed:symbolName];
}
- (instancetype)initWithContentsOfURL:(id)url {
  if (url && [url respondsToSelector:@selector(path)]) {
    return [self initWithContentsOfFile:[url performSelector:@selector(path)]];
  }
  return [self initWithSize:NSMakeSize(32, 32)];
}
- (instancetype)initByReferencingFile:(NSString*)fileName {
  return [self initWithContentsOfFile:fileName];
}
- (void)addRepresentation:(id)imageRep { (void)imageRep; }
- (NSArray*)representations { return [NSArray array]; }
- (void)lockFocus {}
- (void)unlockFocus {}
- (void)drawInRect:(NSRect)dstSpacePortionRect
          fromRect:(NSRect)srcSpacePortionRect
         operation:(NSUInteger)op
          fraction:(CGFloat)requestedAlpha {
  (void)srcSpacePortionRect; (void)op; (void)requestedAlpha;
  [self drawInRect:dstSpacePortionRect];
}
@end

@implementation NSAlert (DarlingMoreMethods)
+ (NSAlert*)alertWithError:(id)error {
  NSAlert* a = [[[self alloc] init] autorelease];
  if (error && [error respondsToSelector:@selector(localizedDescription)]) {
    [a setMessageText:[error localizedDescription]];
  }
  return a;
}
+ (NSAlert*)alertWithMessageText:(NSString*)message
                   defaultButton:(NSString*)defaultButton
                 alternateButton:(NSString*)alternateButton
                     otherButton:(NSString*)otherButton
       informativeTextWithFormat:(NSString*)format, ... {
  (void)defaultButton; (void)alternateButton; (void)otherButton;
  NSAlert* a = [[[self alloc] init] autorelease];
  [a setMessageText:message ? message : @"Alert"];
  [a setInformativeText:format ? format : @""];
  return a;
}
- (NSArray*)buttons { return [NSArray array]; }
- (void)setIcon:(NSImage*)icon { (void)icon; }
- (void)setShowsSuppressionButton:(BOOL)b { (void)b; }
- (void)setAccessoryView:(NSView*)v { (void)v; }
- (void)beginSheetModalForWindow:(NSWindow*)sheetWindow
               completionHandler:(void*)handler {
  (void)sheetWindow; (void)handler;
}
@end

@implementation NSFont (DarlingMoreMethods)
+ (NSFont*)labelFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont*)messageFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont*)menuFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont*)titleBarFontOfSize:(CGFloat)s { return [self boldSystemFontOfSize:s]; }
+ (NSFont*)controlContentFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont*)toolTipsFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont*)userFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont*)systemFontOfSize:(CGFloat)s weight:(CGFloat)w {
  return w > 0.2 ? [self boldSystemFontOfSize:s] : [self systemFontOfSize:s];
}
+ (NSFont*)monospacedSystemFontOfSize:(CGFloat)s weight:(CGFloat)w {
  (void)w;
  return [self userFixedPitchFontOfSize:s];
}
+ (CGFloat)systemFontSize { return 13.0; }
+ (CGFloat)smallSystemFontSize { return 11.0; }
+ (CGFloat)labelFontSize { return 10.0; }
- (NSString*)fontName { return _fixedPitch ? @"Menlo-Regular" : @"Helvetica"; }
- (NSString*)familyName { return _fixedPitch ? @"Menlo" : @"Helvetica"; }
- (NSString*)displayName { return [self fontName]; }
- (CGFloat)ascender { return _size * 0.8; }
- (CGFloat)descender { return -_size * 0.2; }
- (CGFloat)leading { return 0.0; }
@end

@implementation NSColor (DarlingMoreColors)
+ (NSColor*)tertiaryLabelColor { return [self grayColor]; }
+ (NSColor*)quaternaryLabelColor { return [self lightGrayColor]; }
+ (NSColor*)placeholderTextColor { return [self grayColor]; }
+ (NSColor*)WindowFrameTextColor { return [self blackColor]; }
+ (NSColor*)windowFrameTextColor { return [self blackColor]; }
+ (NSColor*)headerTextColor { return [self blackColor]; }
+ (NSColor*)gridColor { return [self lightGrayColor]; }
+ (NSColor*)separatorColor { return [self lightGrayColor]; }
+ (NSColor*)underPageBackgroundColor { return [self windowBackgroundColor]; }
+ (NSColor*)selectedContentBackgroundColor {
  return [self colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0];
}
+ (NSColor*)controlAccentColor {
  return [self colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0];
}
+ (NSColor*)systemRedColor { return [self redColor]; }
+ (NSColor*)systemGreenColor { return [self greenColor]; }
+ (NSColor*)systemBlueColor {
  return [self colorWithCalibratedRed:0.05 green:0.49 blue:0.98 alpha:1.0];
}
+ (NSColor*)systemOrangeColor { return [self orangeColor]; }
+ (NSColor*)systemYellowColor { return [self yellowColor]; }
+ (NSColor*)systemGrayColor { return [self grayColor]; }
+ (NSColor*)purpleColor {
  return [self colorWithCalibratedRed:0.60 green:0.20 blue:0.80 alpha:1.0];
}
+ (NSColor*)magentaColor {
  return [self colorWithCalibratedRed:0.90 green:0.20 blue:0.70 alpha:1.0];
}
+ (NSColor*)brownColor {
  return [self colorWithCalibratedRed:0.60 green:0.40 blue:0.20 alpha:1.0];
}
+ (NSColor*)colorNamed:(NSString*)name {
  return [self colorNamed:name bundle:nil];
}
+ (NSColor*)colorNamed:(NSString*)name bundle:(NSBundle*)bundle {
  (void)bundle;
  if (!name) return [self yellowColor];
  if ([name rangeOfString:@"Blue"].location != NSNotFound) {
    return [self colorWithCalibratedRed:0.68 green:0.88 blue:1.0 alpha:1.0];
  }
  if ([name rangeOfString:@"Green"].location != NSNotFound) {
    return [self colorWithCalibratedRed:0.75 green:0.96 blue:0.75 alpha:1.0];
  }
  if ([name rangeOfString:@"Pink"].location != NSNotFound) {
    return [self colorWithCalibratedRed:1.0 green:0.78 blue:0.88 alpha:1.0];
  }
  if ([name rangeOfString:@"Purple"].location != NSNotFound) {
    return [self colorWithCalibratedRed:0.85 green:0.78 blue:1.0 alpha:1.0];
  }
  if ([name rangeOfString:@"Gray"].location != NSNotFound) {
    return [self colorWithCalibratedRed:0.88 green:0.88 blue:0.88 alpha:1.0];
  }
  // Default Stickies yellow note color!
  return [self colorWithCalibratedRed:0.99 green:0.96 blue:0.62 alpha:1.0];
}
- (NSColor*)colorWithAlphaComponent:(CGFloat)alpha {
  return [NSColor colorWithCalibratedRed:_r green:_g blue:_b alpha:alpha];
}
@end

extern "C" {

void NSRectFill(NSRect aRect) { [NSBezierPath fillRect:aRect]; }
void NSRectFillUsingOperation(NSRect aRect, NSUInteger op) {
  (void)op;
  [NSBezierPath fillRect:aRect];
}
void NSFrameRect(NSRect aRect) { [NSBezierPath strokeRect:aRect]; }
void NSFrameRectWithWidth(NSRect aRect, CGFloat frameWidth) {
  [NSBezierPath strokeRoundedRect:aRect xRadius:0.0 yRadius:0.0 lineWidth:frameWidth];
}
int NSRunAlertPanel(NSString* title, NSString* msgFormat, NSString* defaultButton,
                    NSString* alternateButton, NSString* otherButton, ...) {
  (void)defaultButton; (void)alternateButton; (void)otherButton;
  fprintf(stderr, "[NSRunAlertPanel] %s: %s\n",
          title ? [title UTF8String] : "",
          msgFormat ? [msgFormat UTF8String] : "");
  return 1;
}

// Exported by AppKit for Expansion Slot Utility.app on Mac Pro / Darwin ARM64
int PlatformSupportsPCIELaneConfig(void) { return 1; }

extern const NSString* NSModalPanelRunLoopMode = @"NSModalPanelRunLoopMode";
extern const NSString* NSEventTrackingRunLoopMode = @"NSEventTrackingRunLoopMode";
extern const double NSFontWeightBold = 0.4;
extern const double NSFontWeightMedium = 0.23;
extern const double NSFontWeightSemibold = 0.3;
extern const NSString* NSPasteboardTypeColor = @"com.apple.cocoa.pasteboard.color";

}  // extern "C"

