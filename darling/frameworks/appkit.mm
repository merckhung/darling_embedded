// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded AppKit & CoreGraphics Framework implementation
// Native ARM64 Mach-O Cocoa GUI backed by X11 (libX11) and Cairo (libcairo).

#include <AppKit/AppKit.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/shape.h>
#include <X11/keysym.h>
#include <cairo/cairo-xlib.h>
#include <cairo/cairo.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern "C" void _DarlingFireDueTimers(void);
@class NSButton;
@class NSString;
static void DarlingSetButtonDefaultsKey(NSButton* button, NSString* key);
static NSString* DarlingButtonDefaultsKey(NSButton* button);
@class NSTextView;
static BOOL DarlingTextViewScrollsToEnd(NSTextView* tv);
// Global menu bar integration (appkit_menubar.mm).
static void DarlingPublishMenusToWindow(Display* dpy, Window w);
static void DarlingPublishMenus(void);
static void DarlingPerformMenuPath(const long* path, int len);
static bool DarlingPerformKeyEquivalent(KeySym ks, unsigned int state);
static void DarlingActivateWindow(NSWindow* w);
static void DarlingActivateApplication(void);

@interface NSWindow (DarlingWindowActions)
- (void)performClose:(id)sender;
- (void)performMiniaturize:(id)sender;
- (void)miniaturize:(id)sender;
@end
@interface NSApplication (DarlingApplicationActions)
- (void)hide:(id)sender;
@end

NSApplication* NSApp = nullptr;

namespace {

constexpr int kAquaTitlebarHeight = 28;
constexpr int kMenuBarHeight = 24;  // global menu bar drawn by darling-shell
constexpr double kPi = 3.14159265358979323846;

// Mac OS X user-interface fonts: Inter stands in for the system font and
// DejaVu Sans Mono (Menlo's ancestor) for fixed-pitch text.
const char* UIFontFamily(bool fixed_pitch) {
  return fixed_pitch ? "DejaVu Sans Mono" : "Inter";
}

// Per-window chrome state (key/active appearance, traffic-light hover).
struct WindowChrome {
  void* window;
  bool active;
  bool hover;
  bool hide_title;
  bool minimized;
};
WindowChrome g_chrome[64];
size_t g_chrome_count = 0;

WindowChrome* ChromeFor(void* window) {
  for (size_t i = 0; i < g_chrome_count; ++i) {
    if (g_chrome[i].window == window) return &g_chrome[i];
  }
  if (g_chrome_count < 64) {
    g_chrome[g_chrome_count] = {window, true, false, false, false};
    return &g_chrome[g_chrome_count++];
  }
  static WindowChrome fallback;
  fallback = {window, true, false, false, false};
  return &fallback;
}

int TolerantXErrorHandler(Display*, XErrorEvent* e) {
  fprintf(stderr, "[AppKit] ignored X error %d (request %d)\n", e->error_code, e->request_code);
  return 0;
}

// Window dragging by the title bar (there is no window manager).
void* g_drag_window = nullptr;
int g_drag_dx = 0, g_drag_dy = 0;

// Buttons whose key equivalent is Return are drawn as the blue default button.
void* g_default_buttons[64];
size_t g_default_button_count = 0;

bool IsDefaultButton(void* button) {
  for (size_t i = 0; i < g_default_button_count; ++i) {
    if (g_default_buttons[i] == button) return true;
  }
  return false;
}

void MarkDefaultButton(void* button, bool is_default) {
  for (size_t i = 0; i < g_default_button_count; ++i) {
    if (g_default_buttons[i] == button) {
      if (!is_default) g_default_buttons[i] = g_default_buttons[--g_default_button_count];
      return;
    }
  }
  if (is_default && g_default_button_count < 64) {
    g_default_buttons[g_default_button_count++] = button;
  }
}

cairo_t* g_current_cairo = nullptr;

// Buttons whose "value" is bound to NSUserDefaults (from nib bindings).
struct ButtonDefaultsBinding {
  void* button;
  NSString* key;
};
ButtonDefaultsBinding g_button_bindings[64];
size_t g_button_binding_count = 0;
double g_fill_r = 0.0, g_fill_g = 0.0, g_fill_b = 0.0, g_fill_a = 1.0;
double g_stroke_r = 0.0, g_stroke_g = 0.0, g_stroke_b = 0.0, g_stroke_a = 1.0;

void AppendRoundedRectPath(cairo_t* cr, NSRect r, double radius) {
  if (!cr) return;
  double x = r.origin.x;
  double y = r.origin.y;
  double w = r.size.width;
  double h = r.size.height;
  if (w <= 0.0 || h <= 0.0) return;
  if (radius > w * 0.5) radius = w * 0.5;
  if (radius > h * 0.5) radius = h * 0.5;
  if (radius <= 0.5) {
    cairo_rectangle(cr, x, y, w, h);
    return;
  }
  cairo_new_sub_path(cr);
  cairo_arc(cr, x + w - radius, y + radius, radius, -0.5 * kPi, 0.0);
  cairo_arc(cr, x + w - radius, y + h - radius, radius, 0.0, 0.5 * kPi);
  cairo_arc(cr, x + radius, y + h - radius, radius, 0.5 * kPi, kPi);
  cairo_arc(cr, x + radius, y + radius, radius, kPi, 1.5 * kPi);
  cairo_close_path(cr);
}

void DrawMacOSAquaChrome(cairo_t* cr, int width, int total_height,
                         const char* title, bool active, bool hover,
                         bool hide_title) {
  // Window background base (NSColor windowBackgroundColor).
  cairo_set_source_rgb(cr, 0.925, 0.925, 0.925);
  cairo_rectangle(cr, 0, 0, width, total_height);
  cairo_fill(cr);

  // Unified title bar: a soft light-gray gradient when key, flat when not.
  cairo_pattern_t* bar_grad =
      cairo_pattern_create_linear(0, 0, 0, kAquaTitlebarHeight);
  if (active) {
    cairo_pattern_add_color_stop_rgb(bar_grad, 0.0, 0.955, 0.955, 0.955);
    cairo_pattern_add_color_stop_rgb(bar_grad, 1.0, 0.905, 0.905, 0.905);
  } else {
    cairo_pattern_add_color_stop_rgb(bar_grad, 0.0, 0.965, 0.965, 0.965);
    cairo_pattern_add_color_stop_rgb(bar_grad, 1.0, 0.955, 0.955, 0.955);
  }
  cairo_set_source(cr, bar_grad);
  cairo_rectangle(cr, 0, 0, width, kAquaTitlebarHeight);
  cairo_fill(cr);
  cairo_pattern_destroy(bar_grad);

  cairo_set_line_width(cr, 1.0);
  cairo_set_source_rgba(cr, 1, 1, 1, 0.8);
  cairo_move_to(cr, 10, 1.5);
  cairo_line_to(cr, width - 10, 1.5);
  cairo_stroke(cr);
  cairo_set_source_rgba(cr, 0, 0, 0, active ? 0.16 : 0.10);
  cairo_move_to(cr, 0, kAquaTitlebarHeight - 0.5);
  cairo_line_to(cr, width, kAquaTitlebarHeight - 0.5);
  cairo_stroke(cr);

  // Traffic-light buttons (close, minimize, zoom); gray when inactive,
  // with x / - / zoom glyphs while the pointer hovers over them.
  static const double kFill[3][3] = {{1.0, 0.373, 0.341}, {0.996, 0.737, 0.180},
                                     {0.157, 0.784, 0.251}};
  static const double kEdge[3][3] = {{0.878, 0.267, 0.243}, {0.871, 0.631, 0.137},
                                     {0.102, 0.671, 0.161}};
  static const double kGlyph[3][3] = {{0.30, 0.0, 0.0}, {0.60, 0.34, 0.0},
                                      {0.0, 0.39, 0.0}};
  for (int i = 0; i < 3; ++i) {
    double cx = 20.0 + i * 20.0, cy = 14.0;
    bool lit = active || hover;
    cairo_arc(cr, cx, cy, 6.0, 0.0, 2.0 * kPi);
    if (lit) {
      cairo_set_source_rgb(cr, kFill[i][0], kFill[i][1], kFill[i][2]);
    } else {
      cairo_set_source_rgb(cr, 0.84, 0.84, 0.85);
    }
    cairo_fill_preserve(cr);
    if (lit) {
      cairo_set_source_rgb(cr, kEdge[i][0], kEdge[i][1], kEdge[i][2]);
    } else {
      cairo_set_source_rgb(cr, 0.76, 0.76, 0.77);
    }
    cairo_set_line_width(cr, 0.8);
    cairo_stroke(cr);
    if (!hover) continue;
    cairo_set_source_rgb(cr, kGlyph[i][0], kGlyph[i][1], kGlyph[i][2]);
    cairo_set_line_width(cr, 1.2);
    if (i == 0) {
      cairo_move_to(cr, cx - 2.6, cy - 2.6);
      cairo_line_to(cr, cx + 2.6, cy + 2.6);
      cairo_move_to(cr, cx + 2.6, cy - 2.6);
      cairo_line_to(cr, cx - 2.6, cy + 2.6);
      cairo_stroke(cr);
    } else if (i == 1) {
      cairo_move_to(cr, cx - 3.2, cy);
      cairo_line_to(cr, cx + 3.2, cy);
      cairo_stroke(cr);
    } else {
      cairo_move_to(cr, cx - 2.8, cy - 1.2);
      cairo_line_to(cr, cx - 2.8, cy - 2.8);
      cairo_line_to(cr, cx + 1.2, cy - 2.8);
      cairo_close_path(cr);
      cairo_move_to(cr, cx + 2.8, cy + 1.2);
      cairo_line_to(cr, cx + 2.8, cy + 2.8);
      cairo_line_to(cr, cx - 1.2, cy + 2.8);
      cairo_close_path(cr);
      cairo_fill(cr);
    }
  }

  // Centered window title.
  if (!hide_title) {
    const char* safe_title = (title && title[0]) ? title : "";
    cairo_select_font_face(cr, "Inter SemiBold", CAIRO_FONT_SLANT_NORMAL,
                           CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, 13.0);
    cairo_text_extents_t ext;
    cairo_text_extents(cr, safe_title, &ext);
    double tx = (width - ext.x_advance) * 0.5;
    if (tx < 78.0) tx = 78.0;
    double ty = 18.5;
    cairo_set_source_rgba(cr, 0, 0, 0, active ? 0.85 : 0.30);
    cairo_move_to(cr, tx, ty);
    cairo_show_text(cr, safe_title);
  }
}

// Window outline drawn after the content (rounded like the X shape).
void DrawWindowOutline(cairo_t* cr, int width, int total_height) {
  AppendRoundedRectPath(cr, NSMakeRect(0.5, 0.5, width - 1.0, total_height - 1.0), 10.0);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.30);
  cairo_set_line_width(cr, 1.0);
  cairo_stroke(cr);
}

// Rounds the window's corners with the X SHAPE extension.
void ApplyRoundedWindowShape(Display* dpy, Window w, int width, int height) {
  XRectangle rects[64];
  int n = 0;
  const int r = 10;
  if (width < 2 * r || height < 2 * r) return;
  for (int y = 0; y < r; ++y) {
    double dy = r - y - 0.5;
    int inset = static_cast<int>(r - sqrt(static_cast<double>(r) * r - dy * dy) + 0.5);
    rects[n++] = {static_cast<short>(inset), static_cast<short>(y),
                  static_cast<unsigned short>(width - 2 * inset), 1};
    rects[n++] = {static_cast<short>(inset), static_cast<short>(height - 1 - y),
                  static_cast<unsigned short>(width - 2 * inset), 1};
  }
  rects[n++] = {0, static_cast<short>(r), static_cast<unsigned short>(width),
                static_cast<unsigned short>(height - 2 * r)};
  XShapeCombineRectangles(dpy, w, ShapeBounding, 0, 0, rects, n, ShapeSet, Unsorted);
}

void RenderViewRecursive(cairo_t* cr, NSView* view) {
  if (!view || [view isHidden]) return;
  cairo_save(cr);
  NSRect f = [view frame];
  cairo_translate(cr, f.origin.x, f.origin.y);
  cairo_rectangle(cr, 0.0, 0.0, f.size.width, f.size.height);
  cairo_clip(cr);

  NSColor* bg = [view backgroundColor];
  if (bg && [bg alphaComponent] > 0.001) {
    cairo_set_source_rgba(cr, [bg redComponent], [bg greenComponent],
                          [bg blueComponent], [bg alphaComponent]);
    cairo_rectangle(cr, 0.0, 0.0, f.size.width, f.size.height);
    cairo_fill(cr);
  }

  g_current_cairo = cr;
  [view drawRect:[view bounds]];

  NSArray* subs = [view subviews];
  NSUInteger count = subs ? [subs count] : 0;
  for (NSUInteger i = 0; i < count; ++i) {
    NSView* child = reinterpret_cast<NSView*>([subs objectAtIndex:i]);
    RenderViewRecursive(cr, child);
  }
  cairo_restore(cr);
}

NSView* HitTestViewRecursive(NSView* view, NSPoint pt_in_parent,
                             NSPoint* out_local) {
  if (!view || [view isHidden]) return nullptr;
  NSRect f = [view frame];
  if (!NSPointInRect(pt_in_parent, f)) return nullptr;
  NSPoint local = NSMakePoint(pt_in_parent.x - f.origin.x,
                              pt_in_parent.y - f.origin.y);
  NSArray* subs = [view subviews];
  NSUInteger count = subs ? [subs count] : 0;
  for (NSUInteger i = count; i > 0; --i) {
    NSView* child = reinterpret_cast<NSView*>([subs objectAtIndex:i - 1]);
    NSView* hit = HitTestViewRecursive(child, local, out_local);
    if (hit) return hit;
  }
  if (out_local) *out_local = local;
  return view;
}

void ReportWindowButtonsRecursive(Display* dpy, Window xwin, NSView* view,
                                  double offset_x, double offset_y,
                                  const char* win_title) {
  if (!view || [view isHidden]) return;
  NSRect f = [view frame];
  double cur_x = offset_x + f.origin.x;
  double cur_y = offset_y + f.origin.y;
  if ([view isKindOfClass:[NSButton class]]) {
    auto* btn = reinterpret_cast<NSButton*>(view);
    const char* btitle = [[btn title] UTF8String];
    int cx = static_cast<int>(cur_x + f.size.width * 0.5);
    int cy = static_cast<int>(kAquaTitlebarHeight + cur_y + f.size.height * 0.5);
    int rx = cx, ry = cy;
    Window child = None;
    if (dpy && xwin) {
      XTranslateCoordinates(dpy, xwin, DefaultRootWindow(dpy), cx, cy, &rx, &ry,
                            &child);
    }
    printf("DARLING_BUTTON_POS:%s:%s:%d:%d\n",
           win_title ? win_title : "Window", btitle ? btitle : "Button", rx,
           ry);
    fflush(stdout);
  }
  NSArray* subs = [view subviews];
  NSUInteger count = subs ? [subs count] : 0;
  for (NSUInteger i = 0; i < count; ++i) {
    NSView* sub = reinterpret_cast<NSView*>([subs objectAtIndex:i]);
    ReportWindowButtonsRecursive(dpy, xwin, sub, cur_x, cur_y, win_title);
  }
}

void ApplyBorderlessMotifHints(Display* dpy, Window w) {
  struct MotifWmHints {
    unsigned long flags;
    unsigned long functions;
    unsigned long decorations;
    long input_mode;
    unsigned long status;
  };
  Atom prop = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
  MotifWmHints hints = {2UL, 0UL, 0UL, 0L, 0UL};
  XChangeProperty(dpy, w, prop, prop, 32, PropModeReplace,
                  reinterpret_cast<const unsigned char*>(&hints), 5);
}

}  // namespace

static void DarlingSetButtonDefaultsKey(NSButton* button, NSString* key) {
  for (size_t i = 0; i < g_button_binding_count; ++i) {
    if (g_button_bindings[i].button == button) {
      g_button_bindings[i].key = [key copy];
      return;
    }
  }
  if (g_button_binding_count < 64) {
    g_button_bindings[g_button_binding_count++] = {button, [key copy]};
  }
}

static NSString* DarlingButtonDefaultsKey(NSButton* button) {
  for (size_t i = 0; i < g_button_binding_count; ++i) {
    if (g_button_bindings[i].button == button) return g_button_bindings[i].key;
  }
  return nil;
}

@implementation NSColor

+ (NSColor*)colorWithCalibratedRed:(CGFloat)red
                             green:(CGFloat)green
                              blue:(CGFloat)blue
                             alpha:(CGFloat)alpha {
  NSColor* c = [[NSColor alloc] init];
  c->_r = red;
  c->_g = green;
  c->_b = blue;
  c->_a = alpha;
  return c;
}

+ (NSColor*)colorWithSRGBRed:(CGFloat)red
                       green:(CGFloat)green
                        blue:(CGFloat)blue
                       alpha:(CGFloat)alpha {
  return [self colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

+ (NSColor*)whiteColor {
  return [self colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0];
}
+ (NSColor*)blackColor {
  return [self colorWithCalibratedRed:0.08 green:0.09 blue:0.11 alpha:1.0];
}
+ (NSColor*)clearColor {
  return [self colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.0];
}
+ (NSColor*)grayColor {
  return [self colorWithCalibratedRed:0.50 green:0.52 blue:0.56 alpha:1.0];
}
+ (NSColor*)lightGrayColor {
  return [self colorWithCalibratedRed:0.84 green:0.85 blue:0.88 alpha:1.0];
}
+ (NSColor*)darkGrayColor {
  return [self colorWithCalibratedRed:0.25 green:0.27 blue:0.30 alpha:1.0];
}
+ (NSColor*)redColor {
  return [self colorWithCalibratedRed:0.90 green:0.22 blue:0.21 alpha:1.0];
}
+ (NSColor*)greenColor {
  return [self colorWithCalibratedRed:0.16 green:0.72 blue:0.28 alpha:1.0];
}
+ (NSColor*)blueColor {
  return [self colorWithCalibratedRed:0.04 green:0.48 blue:1.00 alpha:1.0];
}
+ (NSColor*)cyanColor {
  return [self colorWithCalibratedRed:0.15 green:0.78 blue:0.85 alpha:1.0];
}
+ (NSColor*)yellowColor {
  return [self colorWithCalibratedRed:0.98 green:0.76 blue:0.14 alpha:1.0];
}
+ (NSColor*)orangeColor {
  return [self colorWithCalibratedRed:1.00 green:0.58 blue:0.00 alpha:1.0];
}
+ (NSColor*)windowBackgroundColor {
  return [self colorWithCalibratedRed:0.925 green:0.925 blue:0.925 alpha:1.0];
}
+ (NSColor*)controlBackgroundColor {
  return [self colorWithCalibratedRed:1.00 green:1.00 blue:1.00 alpha:1.0];
}
+ (NSColor*)labelColor {
  return [self colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.85];
}
+ (NSColor*)controlTextColor {
  return [self colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.85];
}

- (CGFloat)redComponent {
  return _r;
}
- (CGFloat)greenComponent {
  return _g;
}
- (CGFloat)blueComponent {
  return _b;
}
- (CGFloat)alphaComponent {
  return _a;
}

- (void)set {
  [self setFill];
  [self setStroke];
}

- (void)setFill {
  g_fill_r = _r;
  g_fill_g = _g;
  g_fill_b = _b;
  g_fill_a = _a;
  if (g_current_cairo) {
    cairo_set_source_rgba(g_current_cairo, _r, _g, _b, _a);
  }
}

- (void)setStroke {
  g_stroke_r = _r;
  g_stroke_g = _g;
  g_stroke_b = _b;
  g_stroke_a = _a;
  if (g_current_cairo) {
    cairo_set_source_rgba(g_current_cairo, _r, _g, _b, _a);
  }
}

@end

@implementation NSFont

+ (NSFont*)systemFontOfSize:(CGFloat)fontSize {
  NSFont* f = [[NSFont alloc] init];
  f->_size = (fontSize > 6.0) ? fontSize : 13.0;
  f->_bold = NO;
  return f;
}

+ (NSFont*)boldSystemFontOfSize:(CGFloat)fontSize {
  NSFont* f = [[NSFont alloc] init];
  f->_size = (fontSize > 6.0) ? fontSize : 13.0;
  f->_bold = YES;
  return f;
}

+ (NSFont*)monospacedDigitSystemFontOfSize:(CGFloat)fontSize
                                    weight:(CGFloat)weight {
  NSFont* f = [[NSFont alloc] init];
  f->_size = (fontSize > 6.0) ? fontSize : 13.0;
  f->_bold = (weight > 0.2) ? YES : NO;
  return f;
}

+ (NSFont*)userFixedPitchFontOfSize:(CGFloat)fontSize {
  NSFont* f = [self systemFontOfSize:fontSize];
  f->_fixedPitch = YES;
  return f;
}

// Maps macOS font names onto the families shipped in the guest:
// fixed-pitch families (Monaco, Menlo, Courier, SF Mono, ...) use
// DejaVu Sans Mono; everything else uses Inter.
+ (NSFont*)fontWithName:(NSString*)fontName size:(CGFloat)fontSize {
  NSFont* f = [self systemFontOfSize:fontSize > 0 ? fontSize : 13.0];
  const char* n = fontName ? [fontName UTF8String] : "";
  f->_bold = strstr(n, "Bold") != nullptr;
  f->_fixedPitch = strstr(n, "Monaco") || strstr(n, "Menlo") || strstr(n, "Courier") ||
                   strstr(n, "Mono") || strstr(n, "Andale");
  return f;
}

- (BOOL)isFixedPitch {
  return _fixedPitch;
}

- (CGFloat)pointSize {
  return _size;
}

- (BOOL)isBold {
  return _bold;
}

@end

@implementation NSBezierPath

+ (NSBezierPath*)bezierPath {
  return [[[self alloc] init] autorelease];
}

+ (NSBezierPath*)bezierPathWithRect:(NSRect)rect {
  (void)rect;
  return [[[self alloc] init] autorelease];
}

+ (NSBezierPath*)bezierPathWithRoundedRect:(NSRect)rect
                                   xRadius:(CGFloat)xRadius
                                   yRadius:(CGFloat)yRadius {
  (void)rect; (void)xRadius; (void)yRadius;
  return [[[self alloc] init] autorelease];
}

- (void)fill {}
- (void)stroke {}
- (void)addClip {}
- (void)setLineWidth:(CGFloat)w { (void)w; }

+ (void)fillRect:(NSRect)rect {
  if (!g_current_cairo) return;
  cairo_set_source_rgba(g_current_cairo, g_fill_r, g_fill_g, g_fill_b, g_fill_a);
  cairo_rectangle(g_current_cairo, rect.origin.x, rect.origin.y,
                  rect.size.width, rect.size.height);
  cairo_fill(g_current_cairo);
}

+ (void)strokeRect:(NSRect)rect {
  if (!g_current_cairo) return;
  cairo_set_source_rgba(g_current_cairo, g_stroke_r, g_stroke_g, g_stroke_b,
                        g_stroke_a);
  cairo_set_line_width(g_current_cairo, 1.0);
  cairo_rectangle(g_current_cairo, rect.origin.x + 0.5, rect.origin.y + 0.5,
                  rect.size.width - 1.0, rect.size.height - 1.0);
  cairo_stroke(g_current_cairo);
}

+ (void)fillRoundedRect:(NSRect)rect
                xRadius:(CGFloat)xRad
                yRadius:(CGFloat)yRad {
  (void)yRad;
  if (!g_current_cairo) return;
  cairo_set_source_rgba(g_current_cairo, g_fill_r, g_fill_g, g_fill_b, g_fill_a);
  AppendRoundedRectPath(g_current_cairo, rect, xRad);
  cairo_fill(g_current_cairo);
}

+ (void)strokeRoundedRect:(NSRect)rect
                  xRadius:(CGFloat)xRad
                  yRadius:(CGFloat)yRad
                lineWidth:(CGFloat)lineWidth {
  (void)yRad;
  if (!g_current_cairo) return;
  cairo_set_source_rgba(g_current_cairo, g_stroke_r, g_stroke_g, g_stroke_b,
                        g_stroke_a);
  cairo_set_line_width(g_current_cairo, lineWidth > 0.0 ? lineWidth : 1.0);
  AppendRoundedRectPath(g_current_cairo, rect, xRad);
  cairo_stroke(g_current_cairo);
}

+ (void)strokeLineFromPoint:(NSPoint)point1
                    toPoint:(NSPoint)point2
                  lineWidth:(CGFloat)lineWidth {
  if (!g_current_cairo) return;
  cairo_set_source_rgba(g_current_cairo, g_stroke_r, g_stroke_g, g_stroke_b,
                        g_stroke_a);
  cairo_set_line_width(g_current_cairo, lineWidth > 0.0 ? lineWidth : 1.0);
  cairo_move_to(g_current_cairo, point1.x, point1.y);
  cairo_line_to(g_current_cairo, point2.x, point2.y);
  cairo_stroke(g_current_cairo);
}

+ (void)drawText:(NSString*)text
          inRect:(NSRect)rect
            font:(NSFont*)font
           color:(NSColor*)color
       alignment:(NSInteger)alignment {
  if (!g_current_cairo || !text) return;
  if (cairo_status(g_current_cairo) != CAIRO_STATUS_SUCCESS) return;
  const char* raw = [text UTF8String];
  if (!raw || !raw[0]) return;

  char clean_buf[1024];
  size_t w = 0;
  for (size_t r = 0; raw[r] != '\0' && w + 4 < sizeof(clean_buf); ++r) {
    unsigned char c = static_cast<unsigned char>(raw[r]);
    if (c >= 0xF0) {
      // Supplementary-plane characters (emoji, SF Symbols) have no glyph.
      if (raw[r + 1]) r++;
      if (raw[r + 1]) r++;
      if (raw[r + 1]) r++;
      clean_buf[w++] = ' ';
    } else if (c >= 0xE0) {
      // Keep BMP characters (ellipsis, bullets, key symbols) except the
      // private-use area U+E000..U+F8FF (Apple logo, SF Symbols).
      unsigned char c1 = static_cast<unsigned char>(raw[r + 1]);
      bool private_use = (c == 0xEE) || (c == 0xEF && c1 < 0xA4);
      if (private_use || !raw[r + 1] || !raw[r + 2]) {
        if (raw[r + 1]) r++;
        if (raw[r + 1]) r++;
        clean_buf[w++] = ' ';
      } else {
        clean_buf[w++] = raw[r];
        clean_buf[w++] = raw[r + 1];
        clean_buf[w++] = raw[r + 2];
        r += 2;
      }
    } else {
      clean_buf[w++] = static_cast<char>(c);
    }
  }
  clean_buf[w] = '\0';
  if (!clean_buf[0]) return;
  const char* cstr = clean_buf;
  double fsize = font ? [font pointSize] : 13.0;
  bool bold = font ? ([font isBold] == YES) : false;
  cairo_select_font_face(g_current_cairo, UIFontFamily(font && [font isFixedPitch]),
                         CAIRO_FONT_SLANT_NORMAL,
                         bold ? CAIRO_FONT_WEIGHT_BOLD
                              : CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(g_current_cairo, fsize);

  if (color) {
    cairo_set_source_rgba(g_current_cairo, [color redComponent],
                          [color greenComponent], [color blueComponent],
                          [color alphaComponent]);
  } else {
    cairo_set_source_rgb(g_current_cairo, 0.1, 0.1, 0.12);
  }

  if (!strchr(cstr, '\n')) {
    cairo_text_extents_t ext;
    cairo_text_extents(g_current_cairo, cstr, &ext);
    double tx = rect.origin.x + 4.0;
    if (alignment == NSTextAlignmentCenter) {
      tx = rect.origin.x + (rect.size.width - ext.width) * 0.5 - ext.x_bearing;
    } else if (alignment == NSTextAlignmentRight) {
      tx = rect.origin.x + rect.size.width - ext.width - ext.x_bearing - 6.0;
    }
    double ty =
        rect.origin.y + (rect.size.height - ext.height) * 0.5 - ext.y_bearing;
    cairo_move_to(g_current_cairo, tx, ty);
    cairo_show_text(g_current_cairo, cstr);
    return;
  }

  cairo_font_extents_t fext;
  cairo_font_extents(g_current_cairo, &fext);
  double line_height = fext.height > 0.0 ? fext.height : fsize * 1.25;

  const char* p = cstr;
  int line_idx = 0;
  while (*p) {
    const char* next = strchr(p, '\n');
    size_t len = next ? static_cast<size_t>(next - p) : strlen(p);
    char linebuf[512];
    if (len >= sizeof(linebuf)) len = sizeof(linebuf) - 1;
    memcpy(linebuf, p, len);
    linebuf[len] = '\0';

    cairo_text_extents_t ext;
    cairo_text_extents(g_current_cairo, linebuf, &ext);
    double tx = rect.origin.x + 4.0;
    if (alignment == NSTextAlignmentCenter) {
      tx = rect.origin.x + (rect.size.width - ext.width) * 0.5 - ext.x_bearing;
    } else if (alignment == NSTextAlignmentRight) {
      tx = rect.origin.x + rect.size.width - ext.width - ext.x_bearing - 6.0;
    }
    double ty = rect.origin.y + fext.ascent + line_idx * line_height;
    if (ty <= rect.origin.y + rect.size.height + fext.descent) {
      cairo_move_to(g_current_cairo, tx, ty);
      cairo_show_text(g_current_cairo, linebuf);
    }

    line_idx++;
    if (!next) break;
    p = next + 1;
  }
}

@end

@implementation NSEvent

- (NSPoint)locationInWindow {
  return _locationInWindow;
}

- (unsigned int)keyCode {
  return _keyCode;
}

- (NSString*)characters {
  return _characters ? _characters : @"";
}

@end

@implementation NSView

- (instancetype)init {
  return [self initWithFrame:NSMakeRect(0.0, 0.0, 0.0, 0.0)];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super init];
  if (self) {
    _frame = frameRect;
    _bounds = NSMakeRect(0.0, 0.0, frameRect.size.width, frameRect.size.height);
    _subviews = [[NSMutableArray alloc] init];
    _backgroundColor = nullptr;
    _hidden = NO;
    _needsDisplay = YES;
    _tag = 0;
  }
  return self;
}

- (NSRect)frame {
  return _frame;
}

- (void)setFrame:(NSRect)frameRect {
  _frame = frameRect;
  _bounds = NSMakeRect(0.0, 0.0, frameRect.size.width, frameRect.size.height);
  [self setNeedsDisplay:YES];
}

- (NSRect)bounds {
  return _bounds;
}

- (NSWindow*)window {
  if (_window) return _window;
  return _superview ? [_superview window] : nullptr;
}

- (NSView*)superview {
  return _superview;
}

- (NSArray*)subviews {
  return _subviews;
}

- (void)addSubview:(NSView*)aView {
  if (!aView) return;
  aView->_superview = self;
  aView->_window = [self window];
  [_subviews addObject:aView];
  [self setNeedsDisplay:YES];
}

- (void)setBackgroundColor:(NSColor*)color {
  _backgroundColor = color;
  [self setNeedsDisplay:YES];
}

- (NSColor*)backgroundColor {
  return _backgroundColor;
}

- (void)setHidden:(BOOL)flag {
  _hidden = flag;
  [self setNeedsDisplay:YES];
}

- (BOOL)isHidden {
  return _hidden;
}

- (void)setNeedsDisplay:(BOOL)flag {
  _needsDisplay = flag;
  NSWindow* win = [self window];
  if (win && flag) {
    win->_needsDisplay = YES;
  }
}

- (void)display {
  NSWindow* win = [self window];
  if (win) [win display];
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
}

- (void)mouseDown:(NSEvent*)event {
  (void)event;
}

- (void)mouseUp:(NSEvent*)event {
  (void)event;
}

- (void)keyDown:(NSEvent*)event {
  (void)event;
}

- (NSInteger)tag {
  return _tag;
}

- (void)setTag:(NSInteger)tag {
  _tag = tag;
}

@end

@implementation NSControl

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _stringValue = @"";
    _font = [NSFont systemFontOfSize:13.0];
    _alignment = NSTextAlignmentLeft;
    _enabled = YES;
  }
  return self;
}

- (id)target {
  return _target;
}
- (void)setTarget:(id)target {
  _target = target;
}
- (SEL)action {
  return _action;
}
- (void)setAction:(SEL)action {
  _action = action;
}

- (NSString*)stringValue {
  return _stringValue ? _stringValue : @"";
}

- (void)setStringValue:(NSString*)string {
  _stringValue = string ? string : @"";
  [self setNeedsDisplay:YES];
}

- (NSFont*)font {
  return _font;
}

- (void)setFont:(NSFont*)fontObj {
  _font = fontObj;
  [self setNeedsDisplay:YES];
}

- (NSInteger)alignment {
  return _alignment;
}

- (void)setAlignment:(NSInteger)mode {
  _alignment = mode;
  [self setNeedsDisplay:YES];
}

- (BOOL)isEnabled {
  return _enabled;
}

- (void)setEnabled:(BOOL)flag {
  _enabled = flag;
  [self setNeedsDisplay:YES];
}

- (BOOL)sendAction:(SEL)theAction to:(id)theTarget {
  if (!_enabled || !theAction) return NO;
  if (!theTarget) {
    // nil target: walk a simplified responder chain (window controller /
    // delegate of the key window is not tracked; NSApp, then its delegate).
    if (NSApp && [NSApp respondsToSelector:theAction]) {
      theTarget = NSApp;
    } else if (NSApp && [NSApp delegate] &&
               [[NSApp delegate] respondsToSelector:theAction]) {
      theTarget = [NSApp delegate];
    } else {
      fprintf(stderr, "[AppKit] no responder for action %s\n",
              sel_getName(theAction));
      return NO;
    }
  }
  typedef void (*ActionMsgFn)(id, SEL, id);
  reinterpret_cast<ActionMsgFn>(objc_msgSend)(theTarget, theAction, self);
  return YES;
}

@end

@implementation NSTextField

+ (instancetype)labelWithString:(NSString*)stringValue {
  NSTextField* tf = [[NSTextField alloc]
      initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 22.0)];
  [tf setStringValue:stringValue];
  [tf setEditable:NO];
  [tf setSelectable:NO];
  [tf setBezeled:NO];
  [tf setDrawsBackground:NO];
  return tf;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _textColor = [NSColor blackColor];
    _editable = NO;
    _selectable = NO;
    _bezeled = NO;
    _drawsBackground = NO;
  }
  return self;
}

- (void)setTextColor:(NSColor*)color {
  _textColor = color;
  [self setNeedsDisplay:YES];
}

- (NSColor*)textColor {
  return _textColor;
}

- (void)setEditable:(BOOL)flag {
  _editable = flag;
}
- (BOOL)isEditable {
  return _editable;
}
- (void)setSelectable:(BOOL)flag {
  _selectable = flag;
}
- (BOOL)isSelectable {
  return _selectable;
}
- (void)setBezeled:(BOOL)flag {
  _bezeled = flag;
  [self setNeedsDisplay:YES];
}
- (BOOL)isBezeled {
  return _bezeled;
}
- (void)setBordered:(BOOL)flag {
  [self setBezeled:flag];
}
- (BOOL)isBordered {
  return [self isBezeled];
}
- (void)setDrawsBackground:(BOOL)flag {
  _drawsBackground = flag;
  [self setNeedsDisplay:YES];
}
- (BOOL)drawsBackground {
  return _drawsBackground;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  NSRect b = [self bounds];
  if (_bezeled && g_current_cairo) {
    // Mac OS X text field: white well with a hairline border that is a
    // little darker along the top edge.
    cairo_t* cr = g_current_cairo;
    NSRect well = NSInsetRect(b, 0.5, 0.5);
    AppendRoundedRectPath(cr, well, 2.5);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
    cairo_set_line_width(cr, 1.0);
    cairo_stroke(cr);
    cairo_move_to(cr, well.origin.x + 2, well.origin.y + 0.5);
    cairo_line_to(cr, well.origin.x + well.size.width - 2, well.origin.y + 0.5);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.10);
    cairo_stroke(cr);
  } else if (_drawsBackground && _backgroundColor) {
    [_backgroundColor setFill];
    [NSBezierPath fillRoundedRect:b xRadius:5.0 yRadius:5.0];
  }
  [NSBezierPath drawText:[self stringValue]
                  inRect:NSInsetRect(b, _bezeled ? 2.0 : 0.0, 1.0)
                    font:_font ? _font : [NSFont systemFontOfSize:13.0]
                   color:_textColor ? _textColor : [NSColor labelColor]
               alignment:_alignment];
}

@end

@implementation NSTextView

- (void)setTextColor:(NSColor*)color {
  if (color != _textColor) {
    [_textColor release];
    _textColor = [color retain];
    [self setNeedsDisplay:YES];
  }
}

- (NSColor*)textColor {
  return _textColor ? _textColor : [NSColor blackColor];
}

- (void)setString:(NSString*)string {
  if (string != _string) {
    [_string release];
    _string = [string copy];
    [self setNeedsDisplay:YES];
  }
}

- (NSString*)string {
  return _string ? _string : @"";
}

- (void)setFont:(NSFont*)font {
  if (font != _font) {
    [_font release];
    _font = [font retain];
    [self setNeedsDisplay:YES];
  }
}

- (NSFont*)font {
  return _font ? _font : [NSFont systemFontOfSize:11.0];
}

- (void)setEditable:(BOOL)flag {
  _editable = flag;
}

- (BOOL)isEditable {
  return _editable;
}

- (BOOL)readRTFDFromFile:(NSString*)path {
  // Minimal RTF reader: extracts the plain text of an RTF document by
  // skipping control words, ignorable destinations and font/colour tables.
  if (!path) return NO;
  FILE* fp = fopen([path UTF8String], "rb");
  if (!fp) return NO;
  fseek(fp, 0, SEEK_END);
  long fsz = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (fsz <= 5 || fsz > 4 * 1024 * 1024) {
    fclose(fp);
    return NO;
  }
  size_t n = static_cast<size_t>(fsz);
  char* rtf = static_cast<char*>(malloc(n + 1));
  char* text = static_cast<char*>(malloc(n * 2 + 1));
  if (!rtf || !text) {
    free(rtf);
    free(text);
    fclose(fp);
    return NO;
  }
  n = fread(rtf, 1, n, fp);
  fclose(fp);
  rtf[n] = '\0';
  if (strncmp(rtf, "{\\rtf", 5) != 0) {
    free(rtf);
    free(text);
    return NO;
  }

  size_t out = 0;
  bool skip_stack[128];
  int depth = 0;
  bool skipping = false;
  for (size_t i = 0; i < n; ++i) {
    char c = rtf[i];
    if (c == '{') {
      if (depth < 128) skip_stack[depth] = skipping;
      ++depth;
      continue;
    }
    if (c == '}') {
      if (depth > 0) {
        --depth;
        if (depth < 128) skipping = skip_stack[depth];
      }
      continue;
    }
    if (c == '\\') {
      if (i + 1 >= n) break;
      char nx = rtf[i + 1];
      if (nx == '\\' || nx == '{' || nx == '}') {
        if (!skipping) text[out++] = nx;
        ++i;
        continue;
      }
      if (nx == '*') {  // ignorable destination
        skipping = true;
        ++i;
        continue;
      }
      if (nx == '\'') {  // \'hh hex-escaped byte (Latin-1)
        if (i + 3 < n) {
          char hex[3] = {rtf[i + 2], rtf[i + 3], '\0'};
          unsigned v = static_cast<unsigned>(strtoul(hex, nullptr, 16));
          if (!skipping) {
            if (v < 0x80) {
              text[out++] = static_cast<char>(v);
            } else {
              text[out++] = static_cast<char>(0xC0 | (v >> 6));
              text[out++] = static_cast<char>(0x80 | (v & 0x3F));
            }
          }
        }
        i += 3;
        continue;
      }
      if (nx == '\n' || nx == '\r') {
        if (!skipping) text[out++] = '\n';
        ++i;
        continue;
      }
      size_t j = i + 1;
      while (j < n && ((rtf[j] >= 'a' && rtf[j] <= 'z') ||
                       (rtf[j] >= 'A' && rtf[j] <= 'Z'))) {
        ++j;
      }
      size_t wlen = j - i - 1;
      const char* word = rtf + i + 1;
      if (j < n && (rtf[j] == '-' || (rtf[j] >= '0' && rtf[j] <= '9'))) {
        ++j;
        while (j < n && rtf[j] >= '0' && rtf[j] <= '9') ++j;
      }
      if (j < n && rtf[j] == ' ') ++j;
      i = j - 1;
      auto is = [&](const char* w) {
        return wlen == strlen(w) && strncmp(word, w, wlen) == 0;
      };
      if (is("fonttbl") || is("colortbl") || is("stylesheet") || is("info") ||
          is("expandedcolortbl") || is("pict")) {
        skipping = true;
      } else if (!skipping && (is("par") || is("line"))) {
        text[out++] = '\n';
      } else if (!skipping && is("tab")) {
        text[out++] = '\t';
      }
      continue;
    }
    if (c == '\n' || c == '\r') continue;
    if (!skipping) text[out++] = c;
  }
  while (out > 0 && (text[out - 1] == '\n' || text[out - 1] == ' ')) --out;
  text[out] = '\0';
  [self setString:[NSString stringWithUTF8String:text]];
  free(rtf);
  free(text);
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  if (_backgroundColor) {
    [_backgroundColor setFill];
    [NSBezierPath fillRoundedRect:_bounds xRadius:4.0 yRadius:4.0];
  }
  NSString* text = [self string];
  if ([text length] > 0 && g_current_cairo) {
    // Word-wrap to the view width (NSTextView lays text out in a container
    // that tracks the view's width).
    NSRect r = NSInsetRect(_bounds, 6.0, 6.0);
    NSFont* font = [self font];
    cairo_select_font_face(g_current_cairo, UIFontFamily([font isFixedPitch]),
                           CAIRO_FONT_SLANT_NORMAL,
                           [font isBold] ? CAIRO_FONT_WEIGHT_BOLD
                                         : CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(g_current_cairo, [font pointSize]);
    const char* src = [text UTF8String];
    size_t n = strlen(src);
    char* out = static_cast<char*>(malloc(n * 2 + 2));
    char* line = static_cast<char*>(malloc(n + 2));
    char* cand = static_cast<char*>(malloc(n + 2));
    size_t o = 0, line_len = 0;
    for (size_t i = 0; out && line && cand && i <= n;) {
      size_t j = i;
      while (j < n && src[j] != ' ' && src[j] != '\n') ++j;
      size_t wlen = j - i;
      size_t clen = 0;
      if (line_len) {
        memcpy(cand, line, line_len);
        cand[line_len] = ' ';
        clen = line_len + 1;
      }
      memcpy(cand + clen, src + i, wlen);
      clen += wlen;
      cand[clen] = '\0';
      cairo_text_extents_t ext;
      cairo_text_extents(g_current_cairo, cand, &ext);
      if (line_len && ext.x_advance > r.size.width - 8.0) {
        memcpy(out + o, line, line_len);
        o += line_len;
        out[o++] = '\n';
        memcpy(line, src + i, wlen);
        line_len = wlen;
      } else {
        memcpy(line, cand, clen);
        line_len = clen;
      }
      if (j >= n || src[j] == '\n') {
        memcpy(out + o, line, line_len);
        o += line_len;
        line_len = 0;
        if (j >= n) break;
        out[o++] = '\n';
      }
      i = j + 1;
    }
    free(cand);
    if (out) {
      out[o] = '\0';
      // When the owner scrolled to the end, show the last lines that fit.
      if (DarlingTextViewScrollsToEnd(self)) {
        cairo_font_extents_t fe;
        cairo_font_extents(g_current_cairo, &fe);
        double lh = fe.height > 0 ? fe.height : [font pointSize] * 1.25;
        size_t fit = static_cast<size_t>(r.size.height / lh);
        size_t lines = 1;
        for (size_t k = 0; k < o; ++k) lines += out[k] == '\n';
        size_t skip = lines > fit ? lines - fit : 0;
        char* start = out;
        while (skip && *start) {
          if (*start++ == '\n') --skip;
        }
        memmove(out, start, strlen(start) + 1);
        o = strlen(out);
      }
      [NSBezierPath drawText:[NSString stringWithUTF8String:out]
                      inRect:r
                        font:font
                       color:[self textColor]
                   alignment:NSTextAlignmentLeft];
    }
    free(out);
    free(line);
  }
}

- (void)dealloc {
  [_textColor release];
  [_string release];
  [_font release];
  [super dealloc];
}

@end

@implementation NSButton

+ (instancetype)buttonWithTitle:(NSString*)title
                         target:(id)target
                         action:(SEL)action {
  NSButton* btn =
      [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 30.0)];
  [btn setTitle:title];
  [btn setTarget:target];
  [btn setAction:action];
  return btn;
}

- (instancetype)init {
  return [self initWithFrame:NSMakeRect(0.0, 0.0, 76.0, 32.0)];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _title = @"Button";
    _bezelStyle = NSBezelStyleRounded;
    _highlighted = NO;
    _tintColor = nullptr;
    _alignment = NSTextAlignmentCenter;
    _font = [NSFont boldSystemFontOfSize:13.0];
  }
  return self;
}

- (NSString*)title {
  return _title ? _title : @"";
}

- (void)setTitle:(NSString*)title {
  _title = title ? title : @"";
  _stringValue = _title;
  [self setNeedsDisplay:YES];
  // Re-report button positions (DARLING_BUTTON_POS) on the next paints.
  NSWindow* win = [self window];
  if (win) win->_paintCount = 0;
}

- (void)setBezelStyle:(NSInteger)bezelStyle {
  _bezelStyle = bezelStyle;
  [self setNeedsDisplay:YES];
}

- (NSInteger)bezelStyle {
  return _bezelStyle;
}

- (void)setTintColor:(NSColor*)color {
  _tintColor = color;
  [self setNeedsDisplay:YES];
}

- (NSColor*)tintColor {
  return _tintColor;
}

- (void)performClick:(id)sender {
  (void)sender;
  const char* t = [_title UTF8String];
  printf("DARLING_BUTTON_CLICK:%s\n", t ? t : "Button");
  fflush(stdout);
  if (_buttonType == NSButtonTypeSwitch || _buttonType == NSButtonTypeRadio ||
      _buttonType == NSButtonTypePushOnPushOff ||
      _buttonType == NSButtonTypeToggle || _buttonType == NSButtonTypeOnOff) {
    _state = _state ? 0 : 1;
    NSString* key = DarlingButtonDefaultsKey(self);
    if (key) {
      [[NSUserDefaults standardUserDefaults]
          setObject:[NSNumber numberWithBool:_state ? YES : NO]
             forKey:key];
      printf("DARLING_DEFAULTS_SET:%s=%ld\n", [key UTF8String],
             static_cast<long>(_state));
      fflush(stdout);
    }
  }
  [self sendAction:_action to:_target];
  [self setNeedsDisplay:YES];
  if ([self window]) {
    [[self window] display];
  }
}

- (void)mouseDown:(NSEvent*)event {
  (void)event;
  _highlighted = YES;
  [self setNeedsDisplay:YES];
  if ([self window]) [[self window] display];
}

- (void)mouseUp:(NSEvent*)event {
  (void)event;
  bool was_highlighted = (_highlighted == YES);
  _highlighted = NO;
  if (was_highlighted) {
    [self performClick:self];
  } else {
    [self setNeedsDisplay:YES];
    if ([self window]) [[self window] display];
  }
}

- (void)setButtonType:(NSButtonType)type {
  _buttonType = type;
  if (type == NSButtonTypeSwitch || type == NSButtonTypeRadio) {
    _alignment = NSTextAlignmentLeft;
  }
  [self setNeedsDisplay:YES];
}

- (NSInteger)state {
  return _state;
}

- (void)setState:(NSInteger)value {
  _state = value;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  cairo_t* cr = g_current_cairo;
  if (!cr) return;
  NSRect bounds = [self bounds];
  NSFont* font = _font ? _font : [NSFont systemFontOfSize:13.0];
  if (_buttonType == NSButtonTypeSwitch || _buttonType == NSButtonTypeRadio) {
    // Mac OS X checkbox / radio button: white control that turns blue when on.
    bool radio = _buttonType == NSButtonTypeRadio;
    double box = 14.0;
    NSRect r = NSMakeRect(2.0, floor((bounds.size.height - box) * 0.5), box, box);
    double radius = radio ? box * 0.5 : 3.5;
    AppendRoundedRectPath(cr, NSMakeRect(r.origin.x, r.origin.y + 0.5, r.size.width, r.size.height), radius);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.08);
    cairo_fill(cr);
    AppendRoundedRectPath(cr, r, radius);
    if (_state) {
      cairo_pattern_t* g = cairo_pattern_create_linear(0, r.origin.y, 0, r.origin.y + box);
      cairo_pattern_add_color_stop_rgb(g, 0, _highlighted ? 0.10 : 0.21, _highlighted ? 0.45 : 0.56,
                                       _highlighted ? 0.90 : 1.0);
      cairo_pattern_add_color_stop_rgb(g, 1, _highlighted ? 0.0 : 0.02, _highlighted ? 0.36 : 0.45,
                                       _highlighted ? 0.80 : 0.96);
      cairo_set_source(cr, g);
      cairo_fill_preserve(cr);
      cairo_pattern_destroy(g);
      cairo_set_source_rgba(cr, 0, 0.2, 0.6, 0.45);
    } else {
      double fill = _highlighted ? 0.88 : 1.0;
      cairo_set_source_rgb(cr, fill, fill, fill);
      cairo_fill_preserve(cr);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.30);
    }
    cairo_set_line_width(cr, 0.8);
    cairo_stroke(cr);
    if (_state && radio) {
      cairo_arc(cr, r.origin.x + box / 2, r.origin.y + box / 2, 2.6, 0, 2 * kPi);
      cairo_set_source_rgb(cr, 1, 1, 1);
      cairo_fill(cr);
    } else if (_state) {
      cairo_set_source_rgb(cr, 1, 1, 1);
      cairo_set_line_width(cr, 1.9);
      cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
      cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
      cairo_move_to(cr, r.origin.x + 3.6, r.origin.y + 7.4);
      cairo_line_to(cr, r.origin.x + 6.1, r.origin.y + 10.0);
      cairo_line_to(cr, r.origin.x + 10.6, r.origin.y + 4.2);
      cairo_stroke(cr);
      cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);
    }
    NSColor* text = _enabled ? [NSColor labelColor]
                             : [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0.30];
    [NSBezierPath drawText:[self title]
                    inRect:NSMakeRect(box + 2.0, 0.0, bounds.size.width - box - 2.0,
                                      bounds.size.height)
                      font:font
                     color:text
                 alignment:NSTextAlignmentLeft];
    return;
  }
  if (_bezelStyle == 5) {  // NSBezelStyleDisclosure: a chevron, no bezel.
    double cx = bounds.size.width * 0.5;
    double cy = bounds.size.height * 0.5;
    cairo_set_source_rgba(cr, 0, 0, 0, 0.6);
    cairo_set_line_width(cr, 1.8);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    if (_state) {  // Expanded: pointing down.
      cairo_move_to(cr, cx - 4.0, cy - 2.0);
      cairo_line_to(cr, cx, cy + 2.5);
      cairo_line_to(cr, cx + 4.0, cy - 2.0);
    } else {  // Collapsed: pointing right.
      cairo_move_to(cr, cx - 2.0, cy - 4.0);
      cairo_line_to(cr, cx + 2.5, cy);
      cairo_line_to(cr, cx - 2.0, cy + 4.0);
    }
    cairo_stroke(cr);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);
    return;
  }

  // Push buttons. A rounded push button (bezel style 1) occupies a 32 pt tall
  // frame in Interface Builder but its visible bezel is about 21 pt tall and
  // inset by 6 pt horizontally, like on Mac OS X. Square styles fill the frame.
  bool square = _bezelStyle == 2 || _bezelStyle == 6 || _bezelStyle == 8 ||
                _bezelStyle == 10 || _bezelStyle == 15;
  NSRect b = NSInsetRect(bounds, 1.0, 1.0);
  double radius = square ? 3.0 : 5.5;
  if (!square && bounds.size.height >= 26.0 && bounds.size.width >= 40.0) {
    double h = 21.0;
    b = NSMakeRect(6.0, floor((bounds.size.height - h) * 0.5) - 0.5, bounds.size.width - 12.0, h);
  }
  bool is_default = IsDefaultButton(self) && !_tintColor;
  // Bezel shadow.
  AppendRoundedRectPath(cr, NSMakeRect(b.origin.x, b.origin.y + 0.6, b.size.width, b.size.height), radius);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.10);
  cairo_fill(cr);
  AppendRoundedRectPath(cr, b, radius);
  NSColor* textCol = [NSColor labelColor];
  if (!_enabled) {
    cairo_set_source_rgba(cr, 1, 1, 1, 0.6);
    cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.12);
    textCol = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0.28];
  } else if (_tintColor) {
    double k = _highlighted ? 0.80 : 1.0;
    cairo_set_source_rgb(cr, [_tintColor redComponent] * k, [_tintColor greenComponent] * k,
                         [_tintColor blueComponent] * k);
    cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
    double lum = 0.299 * [_tintColor redComponent] + 0.587 * [_tintColor greenComponent] +
                 0.114 * [_tintColor blueComponent];
    textCol = lum > 0.68 ? [NSColor labelColor] : [NSColor whiteColor];
  } else if (is_default) {
    cairo_pattern_t* g = cairo_pattern_create_linear(0, b.origin.y, 0, b.origin.y + b.size.height);
    cairo_pattern_add_color_stop_rgb(g, 0, 0.20, 0.56, 1.0);
    cairo_pattern_add_color_stop_rgb(g, 1, 0.02, 0.43, 0.95);
    cairo_set_source(cr, g);
    cairo_fill_preserve(cr);
    cairo_pattern_destroy(g);
    if (_highlighted) {
      cairo_set_source_rgba(cr, 0, 0, 0, 0.18);
      cairo_fill_preserve(cr);
    }
    cairo_set_source_rgba(cr, 0, 0.25, 0.7, 0.55);
    textCol = [NSColor whiteColor];
  } else {
    double f = _highlighted ? 0.86 : 1.0;
    cairo_set_source_rgb(cr, f, f, f * 1.003 > 1.0 ? 1.0 : f * 1.003);
    cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.20);
  }
  cairo_set_line_width(cr, 0.8);
  cairo_stroke(cr);
  NSFont* button_font = [font isBold] ? [NSFont systemFontOfSize:[font pointSize]] : font;
  [NSBezierPath drawText:[self title]
                  inRect:b
                    font:button_font
                   color:textCol
               alignment:NSTextAlignmentCenter];
}
@end


@implementation NSBox

- (void)setTitle:(NSString*)title {
  _boxTitle = [title copy];
  [self setNeedsDisplay:YES];
}

- (NSString*)title {
  return _boxTitle ? _boxTitle : @"";
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  if (_transparent) return;
  NSRect b = NSInsetRect([self bounds], 0.5, 0.5);
  [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.06] setFill];
  [NSBezierPath fillRoundedRect:b xRadius:5.0 yRadius:5.0];
  [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.18] setStroke];
  [NSBezierPath strokeRoundedRect:b xRadius:5.0 yRadius:5.0 lineWidth:1.0];
  if (_boxTitle && [_boxTitle length] > 0) {
    [NSBezierPath drawText:_boxTitle
                    inRect:NSMakeRect(10.0, 4.0, b.size.width - 20.0, 18.0)
                      font:[NSFont boldSystemFontOfSize:12.0]
                     color:[NSColor colorWithCalibratedRed:0.18
                                                     green:0.20
                                                      blue:0.24
                                                     alpha:1.0]
                 alignment:NSTextAlignmentLeft];
  }
}

@end

namespace {

struct IcnsReadCtx {
  const uint8_t* data;
  size_t len;
  size_t pos;
};

cairo_status_t ReadIcnsPng(void* closure, unsigned char* out, unsigned int length) {
  auto* c = static_cast<IcnsReadCtx*>(closure);
  if (c->pos + length > c->len) return CAIRO_STATUS_READ_ERROR;
  memcpy(out, c->data + c->pos, length);
  c->pos += length;
  return CAIRO_STATUS_SUCCESS;
}

}  // namespace

@implementation NSImageView

// Loads the largest PNG-encoded representation from an Apple .icns file
// (modern icns elements such as ic07..ic14 embed PNG data).
- (BOOL)loadImageFromIcnsFile:(NSString*)path {
  FILE* fp = path ? fopen([path UTF8String], "rb") : nullptr;
  if (!fp) return NO;
  fseek(fp, 0, SEEK_END);
  long sz = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (sz < 8 || sz > 32 * 1024 * 1024) {
    fclose(fp);
    return NO;
  }
  uint8_t* buf = static_cast<uint8_t*>(malloc(static_cast<size_t>(sz)));
  size_t n = buf ? fread(buf, 1, static_cast<size_t>(sz), fp) : 0;
  fclose(fp);
  if (!buf || n != static_cast<size_t>(sz) || memcmp(buf, "icns", 4) != 0) {
    free(buf);
    return NO;
  }
  static const uint8_t kPng[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
  cairo_surface_t* best = nullptr;
  int best_w = 0;
  size_t pos = 8;
  while (pos + 8 <= n) {
    uint32_t elen = (static_cast<uint32_t>(buf[pos + 4]) << 24) |
                    (static_cast<uint32_t>(buf[pos + 5]) << 16) |
                    (static_cast<uint32_t>(buf[pos + 6]) << 8) | buf[pos + 7];
    if (elen < 8 || pos + elen > n) break;
    const uint8_t* payload = buf + pos + 8;
    size_t plen = elen - 8;
    if (plen > 8 && memcmp(payload, kPng, 8) == 0) {
      IcnsReadCtx ctx = {payload, plen, 0};
      cairo_surface_t* s = cairo_image_surface_create_from_png_stream(ReadIcnsPng, &ctx);
      if (cairo_surface_status(s) == CAIRO_STATUS_SUCCESS &&
          cairo_image_surface_get_width(s) > best_w &&
          cairo_image_surface_get_width(s) <= 512) {
        if (best) cairo_surface_destroy(best);
        best = s;
        best_w = cairo_image_surface_get_width(s);
      } else {
        cairo_surface_destroy(s);
      }
    }
    pos += elen;
  }
  free(buf);
  if (!best) return NO;
  if (_imageSurface) cairo_surface_destroy(static_cast<cairo_surface_t*>(_imageSurface));
  _imageSurface = best;
  [self setNeedsDisplay:YES];
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  if (!_imageSurface || !g_current_cairo) return;
  auto* img = static_cast<cairo_surface_t*>(_imageSurface);
  NSRect b = [self bounds];
  double iw = cairo_image_surface_get_width(img);
  double ih = cairo_image_surface_get_height(img);
  double scale = fmin(b.size.width / iw, b.size.height / ih);
  cairo_save(g_current_cairo);
  cairo_translate(g_current_cairo, (b.size.width - iw * scale) * 0.5,
                  (b.size.height - ih * scale) * 0.5);
  cairo_scale(g_current_cairo, scale, scale);
  cairo_set_source_surface(g_current_cairo, img, 0, 0);
  cairo_paint(g_current_cairo);
  cairo_restore(g_current_cairo);
}

@end

@implementation NSWindow

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSUInteger)style
                            backing:(NSUInteger)backingStoreType
                              defer:(BOOL)flag {
  (void)flag;
  self = [super init];
  if (self) {
    _frame = contentRect;
    _styleMask = style;
    _backingType = backingStoreType;
    _title = @"Mac OS X Window";
    _backgroundColor = [NSColor windowBackgroundColor];
    _contentView = [[NSView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, contentRect.size.width,
                                 contentRect.size.height)];
    _contentView->_window = self;
    _visible = NO;
    _needsDisplay = YES;
    _x11Window = 0;
    _cairoSurface = nullptr;
    _cairoContext = nullptr;
    _backbuffer = nullptr;
    _surfaceW = static_cast<int>(contentRect.size.width);
    _surfaceH =
        static_cast<int>(contentRect.size.height) + kAquaTitlebarHeight;
    _paintCount = 0;
    [[NSApplication sharedApplication]->_windows addObject:self];
  }
  return self;
}

- (void)setTitle:(NSString*)string {
  _title = string ? string : @"";
  if (_x11Window && NSApp && NSApp->_x11Display) {
    auto* dpy = static_cast<Display*>(NSApp->_x11Display);
    const char* t = [_title UTF8String];
    XStoreName(dpy, _x11Window, t ? t : "Mac OS X");
    _paintCount = 0;
  }
  _needsDisplay = YES;
}

- (NSString*)title {
  return _title;
}

- (NSView*)contentView {
  return _contentView;
}

- (void)setContentView:(NSView*)aView {
  _contentView = aView;
  if (_contentView) {
    _contentView->_window = self;
  }
  _needsDisplay = YES;
}

- (void)setBackgroundColor:(NSColor*)color {
  _backgroundColor = color;
  _needsDisplay = YES;
}

- (NSColor*)backgroundColor {
  return _backgroundColor;
}

- (NSRect)frame {
  return _frame;
}

- (void)setFrameOrigin:(NSPoint)point {
  if (_x11Window && point.y < kMenuBarHeight + 4) point.y = kMenuBarHeight + 4;
  _frame.origin = point;
  if (_x11Window && NSApp && NSApp->_x11Display) {
    auto* dpy = static_cast<Display*>(NSApp->_x11Display);
    XMoveWindow(dpy, _x11Window, static_cast<int>(point.x),
                static_cast<int>(point.y));
  }
}

- (void)center {
  int sw = 1024, sh = 768;
  if (NSApp && NSApp->_x11Display) {
    auto* dpy = static_cast<Display*>(NSApp->_x11Display);
    int scr = DefaultScreen(dpy);
    sw = DisplayWidth(dpy, scr);
    sh = DisplayHeight(dpy, scr);
  }
  double nx = (sw - _frame.size.width) * 0.5;
  double ny = (sh - (_frame.size.height + kAquaTitlebarHeight)) * 0.5;
  [self setFrameOrigin:NSMakePoint(nx, ny)];
}

- (void)makeKeyAndOrderFront:(id)sender {
  fprintf(stderr, "[AppKit] NSWindow makeKeyAndOrderFront on %p (title: %s)\n",
          self, _title ? [_title UTF8String] : "<null>");
  [self orderFront:sender];
  if (NSApp) {
    NSApp->_keyWindow = self;
    if (_x11Window) DarlingActivateWindow(self);
  }
}

- (void)orderFront:(id)sender {
  (void)sender;
  NSApplication* app = [NSApplication sharedApplication];
  if (!app->_x11Display) {
    for (int retry = 0; retry < 400 && !app->_x11Display; ++retry) {
      app->_x11Display = XOpenDisplay(":0");
      if (!app->_x11Display) usleep(50000);
    }
    if (app->_x11Display) XSetErrorHandler(TolerantXErrorHandler);
  }
  auto* dpy = static_cast<Display*>(app->_x11Display);
  if (!dpy) {
    fprintf(stderr, "[Darling AppKit] Warning: X11 display :0 unavailable\n");
    return;
  }
  int screen = DefaultScreen(dpy);
  app->_x11Screen = screen;

  if (!_x11Window) {
    int x = static_cast<int>(_frame.origin.x);
    int y = static_cast<int>(_frame.origin.y);
    _surfaceW = static_cast<int>(_frame.size.width);
    _surfaceH =
        static_cast<int>(_frame.size.height) + kAquaTitlebarHeight;
    // Keep windows below the global menu bar and on screen, as Mac OS X's
    // -constrainFrameRect:toScreen: does.
    int screen_h = DisplayHeight(dpy, screen);
    if (y + _surfaceH > screen_h - 4) y = screen_h - 4 - _surfaceH;
    if (y < kMenuBarHeight + 4) y = kMenuBarHeight + 4;
    _frame.origin.y = y;

    _x11Window = XCreateSimpleWindow(
        dpy, RootWindow(dpy, screen), x, y,
        static_cast<unsigned int>(_surfaceW),
        static_cast<unsigned int>(_surfaceH), 0, BlackPixel(dpy, screen),
        WhitePixel(dpy, screen));

    ApplyBorderlessMotifHints(dpy, _x11Window);
    ApplyRoundedWindowShape(dpy, _x11Window, _surfaceW, _surfaceH);

    XWMHints wm_hints;
    memset(&wm_hints, 0, sizeof(wm_hints));
    wm_hints.flags = InputHint | StateHint;
    wm_hints.input = True;
    wm_hints.initial_state = NormalState;
    XSetWMHints(dpy, _x11Window, &wm_hints);
    Atom wm_delete = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(dpy, _x11Window, &wm_delete, 1);

    // WM_CLASS: executable name / application name (CFBundleName).
    {
      NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
      id bname = info ? [info objectForKey:@"CFBundleName"] : nil;
      const char* prog = getprogname();
      XClassHint class_hint;
      class_hint.res_name = const_cast<char*>(prog ? prog : "cocoa-app");
      class_hint.res_class = const_cast<char*>(
          bname ? [bname UTF8String] : (prog ? prog : "Cocoa"));
      XSetClassHint(dpy, _x11Window, &class_hint);
      const char* bpath = [[[NSBundle mainBundle] bundlePath] UTF8String];
      if (bpath) {
        XChangeProperty(dpy, _x11Window, XInternAtom(dpy, "_DARLING_BUNDLE_PATH", False),
                        XInternAtom(dpy, "UTF8_STRING", False), 8, PropModeReplace,
                        reinterpret_cast<const unsigned char*>(bpath),
                        static_cast<int>(strlen(bpath)));
      }
    }

    XSizeHints hints;
    memset(&hints, 0, sizeof(hints));
    hints.flags = PPosition | PSize | PMinSize | PMaxSize;
    hints.x = x;
    hints.y = y;
    hints.width = _surfaceW;
    hints.height = _surfaceH;
    hints.min_width = _surfaceW;
    hints.min_height = _surfaceH;
    hints.max_width = _surfaceW;
    hints.max_height = _surfaceH;
    XSetWMNormalHints(dpy, _x11Window, &hints);

    const char* t = [_title UTF8String];
    XStoreName(dpy, _x11Window, t ? t : "Mac OS X");

    Atom utf8 = XInternAtom(dpy, "UTF8_STRING", False);
    Atom net_wm_name = XInternAtom(dpy, "_NET_WM_NAME", False);
    if (t) {
      XChangeProperty(dpy, _x11Window, net_wm_name, utf8, 8, PropModeReplace,
                      reinterpret_cast<const unsigned char*>(t),
                      static_cast<int>(strlen(t)));
    }

    unsigned long pid = static_cast<unsigned long>(getpid());
    Atom net_wm_pid = XInternAtom(dpy, "_NET_WM_PID", False);
    XChangeProperty(dpy, _x11Window, net_wm_pid, XA_CARDINAL, 32,
                    PropModeReplace,
                    reinterpret_cast<const unsigned char*>(&pid), 1);

    XSelectInput(dpy, _x11Window,
                 ExposureMask | ButtonPressMask | ButtonReleaseMask |
                     KeyPressMask | StructureNotifyMask | PointerMotionMask |
                     LeaveWindowMask | FocusChangeMask);
    DarlingPublishMenusToWindow(dpy, _x11Window);

    _cairoSurface = cairo_xlib_surface_create(
        dpy, _x11Window, DefaultVisual(dpy, screen), _surfaceW, _surfaceH);
    _backbuffer = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, _surfaceW,
                                             _surfaceH);
    _cairoContext = cairo_create(static_cast<cairo_surface_t*>(_backbuffer));

    XMapRaised(dpy, _x11Window);
    XMoveWindow(dpy, _x11Window, x, y);
    XSync(dpy, False);
    _visible = YES;
    DarlingActivateWindow(self);
  }

  _visible = YES;
  [self display];
}

- (void)close {
  _visible = NO;
  if (_x11Window && NSApp && NSApp->_x11Display) {
    auto* dpy = static_cast<Display*>(NSApp->_x11Display);
    XUnmapWindow(dpy, _x11Window);
    XFlush(dpy);
  }
}

- (void)display {
  if (!_visible || !_backbuffer) return;
  auto* xsurf = static_cast<cairo_surface_t*>(_cairoSurface);
  auto* bsurf = static_cast<cairo_surface_t*>(_backbuffer);

  cairo_t* cr = cairo_create(bsurf);
  if (!cr || cairo_status(cr) != CAIRO_STATUS_SUCCESS) {
    if (cr) cairo_destroy(cr);
    return;
  }

  WindowChrome* chrome = ChromeFor(self);
  DrawMacOSAquaChrome(cr, _surfaceW, _surfaceH, [_title UTF8String], chrome->active,
                      chrome->hover, chrome->hide_title);

  // Content area background below the 28px Mac OS X Aqua titlebar
  if (_backgroundColor) {
    cairo_set_source_rgba(cr, [_backgroundColor redComponent],
                          [_backgroundColor greenComponent],
                          [_backgroundColor blueComponent],
                          [_backgroundColor alphaComponent]);
    cairo_rectangle(cr, 1.0, kAquaTitlebarHeight, _surfaceW - 2.0,
                    _surfaceH - kAquaTitlebarHeight - 1.0);
    cairo_fill(cr);
  }

  if (_contentView) {
    cairo_save(cr);
    cairo_translate(cr, 0.0, kAquaTitlebarHeight);
    RenderViewRecursive(cr, _contentView);
    cairo_restore(cr);
  }
  DrawWindowOutline(cr, _surfaceW, _surfaceH);
  cairo_destroy(cr);
  cairo_surface_flush(bsurf);

  // Direct blit from Cairo backbuffer to X11 window drawable via core XPutImage
  if (NSApp && NSApp->_x11Display && _x11Window) {
    auto* dpy = static_cast<Display*>(NSApp->_x11Display);
    int screen = NSApp->_x11Screen;
    unsigned char* data = cairo_image_surface_get_data(bsurf);
    int stride = cairo_image_surface_get_stride(bsurf);
    int depth = DefaultDepth(dpy, screen);
    Visual* vis = DefaultVisual(dpy, screen);
    XImage* img = XCreateImage(dpy, vis, depth, ZPixmap, 0,
                               reinterpret_cast<char*>(data),
                               static_cast<unsigned int>(_surfaceW),
                               static_cast<unsigned int>(_surfaceH),
                               32, stride);
    if (img) {
      GC gc = XCreateGC(dpy, _x11Window, 0, nullptr);
      XPutImage(dpy, _x11Window, gc, img, 0, 0, 0, 0,
                static_cast<unsigned int>(_surfaceW),
                static_cast<unsigned int>(_surfaceH));
      XFreeGC(dpy, gc);
      img->data = nullptr;
      XDestroyImage(img);
    }
  }

  // Also blit Cairo Xlib surface if available
  if (xsurf) {
    cairo_t* xcr = cairo_create(xsurf);
    cairo_set_source_surface(xcr, bsurf, 0.0, 0.0);
    cairo_paint(xcr);
    cairo_destroy(xcr);
    cairo_surface_flush(xsurf);
  }

  if (NSApp && NSApp->_x11Display) {
    auto* dpy = static_cast<Display*>(NSApp->_x11Display);
    XSync(dpy, False);
    _paintCount++;
    if (_paintCount <= 5) {
      int rx = static_cast<int>(_frame.origin.x);
      int ry = static_cast<int>(_frame.origin.y);
      Window child = None;
      XTranslateCoordinates(dpy, _x11Window, DefaultRootWindow(dpy), 0, 0, &rx,
                            &ry, &child);
      const char* t = [_title UTF8String];
      printf("DARLING_WINDOW_READY:%s:%lu:%d:%d:%d:%d\n",
             t ? t : "Window", _x11Window, rx, ry, _surfaceW, _surfaceH);
      fflush(stdout);
      ReportWindowButtonsRecursive(dpy, _x11Window, _contentView, 0.0, 0.0, t);
    }
  }
  _needsDisplay = NO;
}

- (void)setDelegate:(id)delegate {
  _delegate = delegate;
}

- (id)delegate {
  return _delegate;
}

- (unsigned long)windowNumber {
  return _x11Window;
}

@end

static bool g_in_event_loop = false;

@implementation NSApplication

+ (NSApplication*)sharedApplication {
  if (!NSApp) {
    NSApp = [[NSApplication alloc] init];
  }
  return NSApp;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _windows = [[NSMutableArray alloc] init];
    _timers = [[NSMutableArray alloc] init];
    _running = NO;
    _activationPolicy = NSApplicationActivationPolicyRegular;
    _x11Display = nullptr;
    _x11Screen = 0;
  }
  return self;
}

- (void)setDelegate:(id)anObject {
  _delegate = anObject;
}

- (id)delegate {
  return _delegate;
}

- (BOOL)setActivationPolicy:(NSInteger)activationPolicy {
  _activationPolicy = activationPolicy;
  return YES;
}

- (void)activateIgnoringOtherApps:(BOOL)flag {
  (void)flag;
  if (_keyWindow && _x11Display && _keyWindow->_x11Window) {
    auto* dpy = static_cast<Display*>(_x11Display);
    XRaiseWindow(dpy, _keyWindow->_x11Window);
    XFlush(dpy);
  }
}

- (NSArray*)windows {
  return _windows;
}

- (NSWindow*)keyWindow {
  return _keyWindow;
}

- (void)stop:(id)sender {
  (void)sender;
  _running = NO;
}

- (void)terminate:(id)sender {
  if (!g_in_event_loop) {
    fprintf(stderr,
            "[AppKit] Ignoring premature [NSApp terminate:] during startup\n");
    return;
  }
  // NSTerminateNow == 1, NSTerminateCancel == 0, NSTerminateLater == 2.
  if (_delegate &&
      [_delegate respondsToSelector:@selector(applicationShouldTerminate:)]) {
    typedef NSUInteger (*ShouldFn)(id, SEL, id);
    NSUInteger reply = reinterpret_cast<ShouldFn>(objc_msgSend)(
        _delegate, @selector(applicationShouldTerminate:), self);
    if (reply == 0) return;
  }
  if (_delegate &&
      [_delegate respondsToSelector:@selector(applicationWillTerminate:)]) {
    [_delegate performSelector:@selector(applicationWillTerminate:)
                    withObject:nil];
  }
  (void)sender;
  printf("DARLING_APP_TERMINATE:pid=%d\n", getpid());
  fflush(stdout);
  _running = NO;
  exit(0);
}

- (void)arrangeInFront:(id)sender {
  (void)sender;
}

- (void)sendEvent:(NSEvent*)theEvent {
  (void)theEvent;
}

static NSString* DarlingFindNibPath(NSString* name, NSBundle* bundle);
static BOOL DarlingLoadNibNamed(NSString* name, id owner, NSBundle* bundle);

- (void)run {
  _running = YES;
  if (!_x11Display) {
    for (int retry = 0; retry < 400 && !_x11Display; ++retry) {
      _x11Display = XOpenDisplay(":0");
      if (!_x11Display) usleep(50000);
    }
    if (_x11Display) XSetErrorHandler(TolerantXErrorHandler);
  }

  if (_delegate &&
      [_delegate respondsToSelector:@selector(applicationWillFinishLaunching:)]) {
    [_delegate performSelector:@selector(applicationWillFinishLaunching:)
                    withObject:nullptr];
  }

  if (_delegate &&
      [_delegate respondsToSelector:@selector(showProgress)]) {
    fprintf(stderr, "[AppKit] calling showProgress on delegate %p\n", _delegate);
    [_delegate performSelector:@selector(showProgress)];
  } else if (_delegate &&
      [_delegate respondsToSelector:@selector(applicationDidFinishLaunching:)]) {
    fprintf(stderr, "[AppKit] calling applicationDidFinishLaunching on delegate %p\n", _delegate);
    [_delegate performSelector:@selector(applicationDidFinishLaunching:)
                    withObject:nullptr];
    fprintf(stderr, "[AppKit] returned from applicationDidFinishLaunching\n");
  } else {
    fprintf(stderr, "[AppKit] delegate %p does not respond to applicationDidFinishLaunching\n", _delegate);
  }

  if (DarlingFindNibPath(@"FileTransferClientWindow", [NSBundle mainBundle])) {
    DarlingLoadNibNamed(@"FileTransferClientWindow", _delegate,
                        [NSBundle mainBundle]);
  }

  BOOL any_visible = NO;
  for (NSUInteger i = 0; i < [_windows count]; ++i) {
    NSWindow* w = reinterpret_cast<NSWindow*>([_windows objectAtIndex:i]);
    if (w && w->_visible) any_visible = YES;
  }
  if (!any_visible) {
    if (_delegate &&
        [_delegate respondsToSelector:@selector(initiateInstallRequestForTool:)]) {
      [_delegate performSelector:@selector(initiateInstallRequestForTool:)
                      withObject:@"Command Line Developer Tools"];
    } else if (_delegate &&
               [_delegate respondsToSelector:@selector(openAllDocuments)]) {
      [_delegate performSelector:@selector(openAllDocuments)];
    } else if (Class su_cls = objc_lookUpClass("SUStatusController")) {
      id sc = [[su_cls alloc] initWithWindowNibName:@"SUStatus"];
      if ([sc respondsToSelector:@selector(beginActionWithTitle:maxProgressValue:statusText:)]) {
        typedef void (*BeginFn)(id, SEL, id, double, id);
        reinterpret_cast<BeginFn>(objc_msgSend)(
            sc, @selector(beginActionWithTitle:maxProgressValue:statusText:),
            @"Updating Application...", 100.0,
            @"Installing update via Darling AppKit...");
      }
      [sc showWindow:self];
    } else if (DarlingFindNibPath(@"ESUWindow", [NSBundle mainBundle])) {
      DarlingLoadNibNamed(@"ESUWindow", _delegate, [NSBundle mainBundle]);
    } else if (DarlingFindNibPath(@"MainWindow", [NSBundle mainBundle])) {
      DarlingLoadNibNamed(@"MainWindow", _delegate, [NSBundle mainBundle]);
    }
    for (NSUInteger i = 0; i < [_windows count]; ++i) {
      NSWindow* w = reinterpret_cast<NSWindow*>([_windows objectAtIndex:i]);
      if (w && w->_visible) any_visible = YES;
    }
    if (!any_visible && [_windows count] > 0) {
      NSWindow* first = reinterpret_cast<NSWindow*>([_windows objectAtIndex:0]);
      if (first) [first makeKeyAndOrderFront:self];
    }
  }

  NSUInteger win_count = [_windows count];
  for (NSUInteger i = 0; i < win_count; ++i) {
    NSWindow* w = reinterpret_cast<NSWindow*>([_windows objectAtIndex:i]);
    if (w && w->_visible) [w display];
  }

  auto* dpy = static_cast<Display*>(_x11Display);
  NSView* active_mouse_view = nullptr;
  g_in_event_loop = true;

  while (_running) {
    _DarlingFireDueTimers();
    _DarlingPollRunLoopSources();

    if (dpy) {
      while (XPending(dpy) > 0) {
        XEvent xev;
        XNextEvent(dpy, &xev);

        NSWindow* target_win = nullptr;
        NSUInteger nwin = [_windows count];
        for (NSUInteger i = 0; i < nwin; ++i) {
          NSWindow* w = reinterpret_cast<NSWindow*>([_windows objectAtIndex:i]);
          if (w && w->_x11Window == xev.xany.window) {
            target_win = w;
            break;
          }
        }
        if (!target_win) continue;

        if (xev.type == Expose) {
          if (xev.xexpose.count == 0) {
            [target_win display];
          }
        } else if (xev.type == ConfigureNotify) {
          if (xev.xconfigure.send_event) {
            target_win->_frame.origin = NSMakePoint(xev.xconfigure.x, xev.xconfigure.y);
          }
          [target_win display];
        } else if (xev.type == FocusIn || xev.type == FocusOut) {
          // Focus moves caused by pointer-root focus or by the menu bar's
          // keyboard grab do not change the key window.
          const XFocusChangeEvent& fe = xev.xfocus;
          if (fe.mode == NotifyGrab || fe.mode == NotifyUngrab ||
              fe.detail == NotifyPointer || fe.detail == NotifyInferior ||
              fe.detail == NotifyPointerRoot || fe.detail == NotifyDetailNone) {
            continue;
          }
          bool active = xev.type == FocusIn;
          if (active) {
            _keyWindow = target_win;
            for (NSWindow* other in _windows) {
              WindowChrome* c = ChromeFor(other);
              bool on = other == target_win;
              if (c->active != on) {
                c->active = on;
                if (other->_visible && other->_x11Window) other->_needsDisplay = YES;
              }
            }
            DarlingPublishMenus();
          } else {
            WindowChrome* chrome = ChromeFor(target_win);
            if (chrome->active) {
              chrome->active = false;
              [target_win display];
            }
          }
        } else if (xev.type == MotionNotify || xev.type == LeaveNotify) {
          if (xev.type == MotionNotify && g_drag_window == target_win) {
            while (XCheckTypedWindowEvent(dpy, target_win->_x11Window, MotionNotify, &xev)) {
            }
            int nx = xev.xmotion.x_root - g_drag_dx;
            int ny = xev.xmotion.y_root - g_drag_dy;
            if (ny < kMenuBarHeight) ny = kMenuBarHeight;
            XMoveWindow(dpy, target_win->_x11Window, nx, ny);
            target_win->_frame.origin = NSMakePoint(nx, ny);
            continue;
          }
          int mx = xev.type == MotionNotify ? xev.xmotion.x : -1;
          int my = xev.type == MotionNotify ? xev.xmotion.y : -1;
          bool hover = mx >= 10 && mx <= 70 && my >= 4 && my <= 24;
          WindowChrome* chrome = ChromeFor(target_win);
          if (chrome->hover != hover) {
            chrome->hover = hover;
            [target_win display];
          }
        } else if (xev.type == ClientMessage) {
          Atom menu_action = XInternAtom(dpy, "_DARLING_MENU_ACTION", False);
          Atom wm_protocols = XInternAtom(dpy, "WM_PROTOCOLS", False);
          if (xev.xclient.message_type == menu_action) {
            long len = xev.xclient.data.l[0];
            if (len > 0 && len <= 4) {
              DarlingPerformMenuPath(&xev.xclient.data.l[1], static_cast<int>(len));
            }
          } else if (xev.xclient.message_type ==
                     XInternAtom(dpy, "_DARLING_ACTIVATE_APP", False)) {
            DarlingActivateApplication();
          } else if (xev.xclient.message_type == wm_protocols &&
                     static_cast<Atom>(xev.xclient.data.l[0]) ==
                         XInternAtom(dpy, "WM_DELETE_WINDOW", False)) {
            [target_win performClose:self];
          }
        } else if (xev.type == ButtonPress && xev.xbutton.button == Button1) {
          int wx = xev.xbutton.x;
          int wy = xev.xbutton.y;
          // Click-to-front: the clicked window becomes the key window.
          if (_keyWindow != target_win || !ChromeFor(target_win)->active) {
            DarlingActivateWindow(target_win);
          } else {
            XRaiseWindow(dpy, target_win->_x11Window);
          }
          if (wy < kAquaTitlebarHeight) {
            if (wx >= 12 && wx <= 28 && wy >= 6 && wy <= 22) {
              // Red: close the window.
              [target_win performClose:self];
            } else if (wx >= 32 && wx <= 48 && wy >= 6 && wy <= 22) {
              // Yellow: minimize (restored from the Dock).
              [target_win performMiniaturize:self];
            } else if (wx >= 52 && wx <= 68 && wy >= 6 && wy <= 22) {
              // Green: zoom (windows have a fixed layout; no-op).
            } else {
              // Drag the window by its title bar.
              int rx = 0, ry = 0;
              Window child = 0;
              XTranslateCoordinates(dpy, target_win->_x11Window, DefaultRootWindow(dpy), 0, 0,
                                    &rx, &ry, &child);
              g_drag_window = target_win;
              g_drag_dx = xev.xbutton.x_root - rx;
              g_drag_dy = xev.xbutton.y_root - ry;
              XGrabPointer(dpy, target_win->_x11Window, False,
                           ButtonReleaseMask | PointerMotionMask, GrabModeAsync, GrabModeAsync,
                           None, None, xev.xbutton.time);
            }
          } else if (target_win->_contentView) {
            NSPoint content_pt = NSMakePoint(wx, wy - kAquaTitlebarHeight);
            NSPoint local_pt = NSMakePoint(0, 0);
            NSView* hit = HitTestViewRecursive(target_win->_contentView,
                                               content_pt, &local_pt);
            if (hit) {
              active_mouse_view = hit;
              NSEvent* nsev = [[NSEvent alloc] init];
              nsev->_locationInWindow = content_pt;
              [hit mouseDown:nsev];
            }
          }
        } else if (xev.type == ButtonRelease && xev.xbutton.button == Button1) {
          if (g_drag_window) {
            g_drag_window = nullptr;
            XUngrabPointer(dpy, xev.xbutton.time);
            continue;
          }
          if (active_mouse_view) {
            NSEvent* nsev = [[NSEvent alloc] init];
            nsev->_locationInWindow =
                NSMakePoint(xev.xbutton.x, xev.xbutton.y - kAquaTitlebarHeight);
            NSView* view_to_release = active_mouse_view;
            active_mouse_view = nullptr;
            [view_to_release mouseUp:nsev];
          }
        } else if (xev.type == KeyPress) {
          char keybuf[16] = {0};
          KeySym ks = 0;
          int len = XLookupString(&xev.xkey, keybuf, sizeof(keybuf) - 1, &ks,
                                  nullptr);
          keybuf[len > 0 ? len : 0] = '\0';
          if (DarlingPerformKeyEquivalent(XLookupKeysym(&xev.xkey, 0), xev.xkey.state)) {
            continue;
          }
          NSEvent* nsev = [[NSEvent alloc] init];
          nsev->_keyCode = xev.xkey.keycode;
          nsev->_characters = [NSString stringWithUTF8String:keybuf];
          if (target_win->_contentView) {
            [target_win->_contentView keyDown:nsev];
          }
        }
      }
    }

    NSUInteger nwin = [_windows count];
    for (NSUInteger i = 0; i < nwin; ++i) {
      NSWindow* w = reinterpret_cast<NSWindow*>([_windows objectAtIndex:i]);
      if (w && w->_visible && w->_needsDisplay) {
        [w display];
      }
    }

    usleep(16000);
  }
}

@end

@implementation NSAlert {
  NSString* _message;
  NSString* _informative;
  NSMutableArray* _buttons;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _buttons = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)setAlertStyle:(NSUInteger)style {
  (void)style;
}

- (void)setMessageText:(NSString*)messageText {
  [_message release];
  _message = [messageText copy];
}

- (void)setInformativeText:(NSString*)informativeText {
  [_informative release];
  _informative = [informativeText copy];
}

- (void)addButtonWithTitle:(NSString*)title {
  if (title) [_buttons addObject:title];
}

- (NSInteger)runModal {
  fprintf(stderr, "[Darling AppKit] NSAlert: %s - %s\n",
          _message ? [_message UTF8String] : "",
          _informative ? [_informative UTF8String] : "");
  return 1000;
}

- (void)dealloc {
  [_message release];
  [_informative release];
  [_buttons release];
  [super dealloc];
}

@end

@implementation NSOpenPanel

+ (NSOpenPanel*)openPanel {
  auto* p = [[self alloc] initWithContentRect:NSMakeRect(200, 200, 480, 360)
                                    styleMask:15
                                      backing:2
                                        defer:NO];
  [p setTitle:@"Open"];
  return [p autorelease];
}

- (void)setCanChooseFiles:(BOOL)flag { (void)flag; }
- (void)setCanChooseDirectories:(BOOL)flag { (void)flag; }
- (void)setAllowsMultipleSelection:(BOOL)flag { (void)flag; }

- (NSInteger)runModal {
  return 1;
}

- (NSArray*)URLs {
  return [NSArray array];
}

@end

@implementation NSWorkspace

+ (NSWorkspace*)sharedWorkspace {
  static NSWorkspace* ws = nullptr;
  if (!ws) {
    ws = [[NSWorkspace alloc] init];
  }
  return ws;
}

- (BOOL)openFile:(NSString*)fullPath {
  return [self openFile:fullPath withApplication:nullptr];
}

- (BOOL)openFile:(NSString*)fullPath withApplication:(NSString*)appName {
  return [self openFile:fullPath withApplication:appName andDeactivate:NO];
}

- (BOOL)openFile:(NSString*)fullPath
    withApplication:(NSString*)appName
      andDeactivate:(BOOL)flag {
  (void)appName; (void)flag;
  if (!fullPath) return NO;
  fprintf(stderr, "[Darling AppKit] NSWorkspace openFile: %s\n",
          [fullPath UTF8String]);
  return YES;
}

@end

namespace {

struct ControllerEntry {
  void* controller;
  NSWindow* window;
  NSString* nibName;
};

constexpr size_t kMaxControllers = 64;
static ControllerEntry g_controllers[kMaxControllers];
static size_t g_controller_count = 0;
static pthread_mutex_t g_controller_lock = PTHREAD_MUTEX_INITIALIZER;

static NSWindow* GetControllerWindow(id controller) {
  if (!controller) return nil;
  pthread_mutex_lock(&g_controller_lock);
  NSWindow* win = nil;
  for (size_t i = 0; i < g_controller_count; ++i) {
    if (g_controllers[i].controller == reinterpret_cast<void*>(controller)) {
      win = g_controllers[i].window;
      break;
    }
  }
  pthread_mutex_unlock(&g_controller_lock);
  return win;
}

static void SetControllerWindow(id controller, NSWindow* win) {
  if (!controller) return;
  pthread_mutex_lock(&g_controller_lock);
  void* ptr = reinterpret_cast<void*>(controller);
  for (size_t i = 0; i < g_controller_count; ++i) {
    if (g_controllers[i].controller == ptr) {
      if (g_controllers[i].window != win) {
        [g_controllers[i].window release];
        g_controllers[i].window = [win retain];
      }
      pthread_mutex_unlock(&g_controller_lock);
      return;
    }
  }
  if (g_controller_count < kMaxControllers) {
    g_controllers[g_controller_count++] = {ptr, [win retain], nil};
  }
  pthread_mutex_unlock(&g_controller_lock);
}

static void SetControllerNib(id controller, NSString* nibName) {
  if (!controller) return;
  pthread_mutex_lock(&g_controller_lock);
  void* ptr = reinterpret_cast<void*>(controller);
  for (size_t i = 0; i < g_controller_count; ++i) {
    if (g_controllers[i].controller == ptr) {
      if (g_controllers[i].nibName != nibName) {
        [g_controllers[i].nibName release];
        g_controllers[i].nibName = [nibName copy];
      }
      pthread_mutex_unlock(&g_controller_lock);
      return;
    }
  }
  if (g_controller_count < kMaxControllers) {
    g_controllers[g_controller_count++] = {ptr, nil, [nibName copy]};
  }
  pthread_mutex_unlock(&g_controller_lock);
}

static NSString* GetControllerNib(id controller) {
  if (!controller) return nil;
  pthread_mutex_lock(&g_controller_lock);
  NSString* nib = nil;
  for (size_t i = 0; i < g_controller_count; ++i) {
    if (g_controllers[i].controller == reinterpret_cast<void*>(controller)) {
      nib = g_controllers[i].nibName;
      break;
    }
  }
  pthread_mutex_unlock(&g_controller_lock);
  return nib;
}

static void RemoveController(id controller) {
  if (!controller) return;
  pthread_mutex_lock(&g_controller_lock);
  void* ptr = reinterpret_cast<void*>(controller);
  for (size_t i = 0; i < g_controller_count; ++i) {
    if (g_controllers[i].controller == ptr) {
      [g_controllers[i].window release];
      [g_controllers[i].nibName release];
      g_controllers[i] = g_controllers[g_controller_count - 1];
      g_controllers[g_controller_count - 1] = {nullptr, nil, nil};
      g_controller_count--;
      break;
    }
  }
  pthread_mutex_unlock(&g_controller_lock);
}

}  // namespace

#include "appkit_more.mm"
#include "appkit_nib.mm"
#include "appkit_menubar.mm"

@implementation NSWindowController

- (instancetype)initWithWindow:(NSWindow*)window {
  self = [super init];
  if (self) {
    SetControllerWindow(self, window);
  }
  return self;
}

- (instancetype)initWithWindowNibName:(NSString*)windowNibName {
  self = [super init];
  if (self) {
    SetControllerNib(self, windowNibName);
  }
  return self;
}

- (instancetype)initWithWindowNibName:(NSString*)windowNibName owner:(id)owner {
  (void)owner;
  return [self initWithWindowNibName:windowNibName];
}

- (NSWindow*)window {
  NSWindow* win = GetControllerWindow(self);
  if (!win) {
    [self loadWindow];
    win = GetControllerWindow(self);
    if (win && [self respondsToSelector:@selector(windowDidLoad)]) {
      [self windowDidLoad];
    }
  }
  return win;
}

- (void)setWindow:(NSWindow*)window {
  SetControllerWindow(self, window);
}

- (void)loadWindow {
  if (GetControllerWindow(self)) return;
  NSString* nib = GetControllerNib(self);
  if (!nib) return;
  // Instantiate the window from the application's compiled nib with this
  // controller as File's Owner; the nib's "window" outlet calls -setWindow:.
  if (!DarlingLoadNibNamed(nib, self, [NSBundle mainBundle])) {
    fprintf(stderr, "[AppKit] NSWindowController: failed to load nib '%s'\n",
            [nib UTF8String]);
  }
}

- (void)windowDidLoad {}

- (void)showWindow:(id)sender {
  fprintf(stderr, "[AppKit] NSWindowController showWindow on %p\n", self);
  (void)sender;
  [[self window] makeKeyAndOrderFront:sender];
}

- (void)dealloc {
  RemoveController(self);
  [super dealloc];
}

@end

extern "C" {

void NSBeep(void) {
  fprintf(stderr, "[Darling AppKit] NSBeep()\n");
}

int TransformProcessType(void* psn, uint32_t type) {
  (void)psn;
  (void)type;
  return 0;
}

int NSApplicationMain(int argc, const char* argv[]) {
  printf("[AppKit] Entered NSApplicationMain (argc=%d, argv[0]=%s)\n", argc,
         (argv && argv[0]) ? argv[0] : "<null>");
  fflush(stdout);
  NSBundle* bundle = [NSBundle mainBundle];
  NSDictionary* info = [bundle infoDictionary];
  NSString* principal = info ? [info objectForKey:@"NSPrincipalClass"] : nil;
  Class app_cls = principal ? objc_lookUpClass([principal UTF8String]) : nullptr;
  if (app_cls) {
    typedef id (*SharedFn)(id, SEL);
    reinterpret_cast<SharedFn>(objc_msgSend)(
        reinterpret_cast<id>(app_cls), @selector(sharedApplication));
  }
  NSApplication* app = [NSApplication sharedApplication];
  NSString* main_nib = info ? [info objectForKey:@"NSMainNibFile"] : nil;
  NSString* main_sb = info ? [info objectForKey:@"NSMainStoryboardFile"] : nil;
  if (main_nib) {
    // The main nib normally instantiates the application delegate and
    // connects it to File's Owner (NSApp) via the "delegate" outlet.
    if (!DarlingLoadNibNamed(main_nib, app, bundle)) {
      fprintf(stderr, "[AppKit] NSApplicationMain: failed to load main nib '%s'\n",
              [main_nib UTF8String]);
    }
  } else if (main_sb) {
    DarlingLoadNibNamed(@"MainMenu", app, bundle);
  }
  printf("[AppKit] NSApplication delegate = %p\n", [app delegate]);
  fflush(stdout);
  [app run];
  return 0;
}

}  // extern "C"
