// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded desktop shell: the Mac OS X "SystemUIServer", Dock and a
// minimal Finder for the Xorg session. Draws the desktop wallpaper, the global
// menu bar (showing the menus that AppKit applications publish in the
// _DARLING_APP_MENU window property and sending the chosen item back as a
// _DARLING_MENU_ACTION client message), the Dock, an "Applications" Finder
// window and "About This Mac". Rendering uses Xlib + Cairo.

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xrender.h>
#include <X11/extensions/shape.h>
#include <X11/keysym.h>
#include <cairo/cairo.h>
#include <ctype.h>
#include <dirent.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr int kBarH = 24;
constexpr int kIcon = 48;
constexpr int kIconGap = 6;
constexpr int kShelfPad = 8;
constexpr int kShelfH = 64;
constexpr int kDockBottom = 4;
constexpr int kBounceH = 26;
const char* const kFont = "Inter";

Display* g_dpy = nullptr;
int g_scr = 0;
Window g_root = 0;
int g_w = 1024, g_h = 768;
Visual* g_vis = nullptr;
int g_depth = 24;
cairo_surface_t* g_wall = nullptr;
Pixmap g_wall_pm = 0;
cairo_surface_t* g_desk = nullptr;  // wallpaper + desktop icons
bool g_desk_dirty = false;
double g_desk_rendered = 0;
Cursor g_cursor = 0;

Atom A(const char* n) { return XInternAtom(g_dpy, n, False); }

double NowSec() {
  timeval tv;
  gettimeofday(&tv, nullptr);
  return static_cast<double>(tv.tv_sec) + tv.tv_usec / 1e6;
}

int IgnoreXErrors(Display*, XErrorEvent*) { return 0; }

// ---------------------------------------------------------------------------
// Drawing helpers
// ---------------------------------------------------------------------------
void RoundRect(cairo_t* cr, double x, double y, double w, double h, double r) {
  if (r > w / 2) r = w / 2;
  if (r > h / 2) r = h / 2;
  cairo_new_sub_path(cr);
  cairo_arc(cr, x + w - r, y + r, r, -kPi / 2, 0);
  cairo_arc(cr, x + w - r, y + h - r, r, 0, kPi / 2);
  cairo_arc(cr, x + r, y + h - r, r, kPi / 2, kPi);
  cairo_arc(cr, x + r, y + r, r, kPi, 3 * kPi / 2);
  cairo_close_path(cr);
}

void SetFont(cairo_t* cr, double size, bool bold) {
  cairo_select_font_face(cr, kFont, CAIRO_FONT_SLANT_NORMAL,
                         bold ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, size);
}

double TextW(cairo_t* cr, const char* s) {
  cairo_text_extents_t e;
  cairo_text_extents(cr, s, &e);
  return e.x_advance;
}

void Text(cairo_t* cr, double x, double y, const char* s) {
  cairo_move_to(cr, x, y);
  cairo_show_text(cr, s);
}

void TextCentered(cairo_t* cr, double cx, double y, const char* s) {
  Text(cr, cx - TextW(cr, s) / 2, y, s);
}

// Copies |s| into |out|, shortening it with an ellipsis to fit |maxw|.
void Ellipsize(cairo_t* cr, const char* s, double maxw, char* out, size_t cap) {
  snprintf(out, cap, "%s", s);
  if (TextW(cr, out) <= maxw) return;
  size_t n = strlen(out);
  while (n > 0) {
    --n;
    while (n > 0 && (static_cast<unsigned char>(out[n]) & 0xC0) == 0x80) --n;
    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%.*s\xE2\x80\xA6", static_cast<int>(n), out);
    if (TextW(cr, tmp) <= maxw || n == 0) {
      snprintf(out, cap, "%s", tmp);
      return;
    }
  }
}

cairo_surface_t* NewImage(int w, int h) {
  return cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w > 0 ? w : 1, h > 0 ? h : 1);
}

void Blit(Window win, cairo_surface_t* img) {
  cairo_surface_flush(img);
  int iw = cairo_image_surface_get_width(img);
  int ih = cairo_image_surface_get_height(img);
  XImage* xi = XCreateImage(g_dpy, g_vis, static_cast<unsigned>(g_depth), ZPixmap, 0,
                            reinterpret_cast<char*>(cairo_image_surface_get_data(img)),
                            static_cast<unsigned>(iw), static_cast<unsigned>(ih), 32,
                            cairo_image_surface_get_stride(img));
  if (!xi) return;
  GC gc = XCreateGC(g_dpy, win, 0, nullptr);
  XPutImage(g_dpy, win, gc, xi, 0, 0, 0, 0, static_cast<unsigned>(iw),
            static_cast<unsigned>(ih));
  XFreeGC(g_dpy, gc);
  xi->data = nullptr;
  XDestroyImage(xi);
}

// Sets a rounded-rectangle bounding shape (scanline rectangles).
int RoundedRects(XRectangle* rects, int max, int x0, int y0, int w, int h, int r) {
  int n = 0;
  if (r * 2 > h) r = h / 2;
  if (r * 2 > w) r = w / 2;
  for (int y = 0; y < r && n + 2 < max; ++y) {
    double dy = r - y - 0.5;
    int inset = static_cast<int>(r - sqrt(static_cast<double>(r) * r - dy * dy) + 0.5);
    rects[n++] = {static_cast<short>(x0 + inset), static_cast<short>(y0 + y),
                  static_cast<unsigned short>(w - 2 * inset), 1};
    rects[n++] = {static_cast<short>(x0 + inset), static_cast<short>(y0 + h - 1 - y),
                  static_cast<unsigned short>(w - 2 * inset), 1};
  }
  if (n < max) {
    rects[n++] = {static_cast<short>(x0), static_cast<short>(y0 + r),
                  static_cast<unsigned short>(w), static_cast<unsigned short>(h - 2 * r)};
  }
  return n;
}

void ShapeRounded(Window win, int w, int h, int r) {
  XRectangle rects[160];
  int n = RoundedRects(rects, 160, 0, 0, w, h, r);
  XShapeCombineRectangles(g_dpy, win, ShapeBounding, 0, 0, rects, n, ShapeSet, Unsorted);
}

void SetWindowType(Window w, const char* type) {
  Atom t = A(type);
  XChangeProperty(g_dpy, w, A("_NET_WM_WINDOW_TYPE"), XA_ATOM, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(&t), 1);
}

void SetNoDecorations(Window w) {
  unsigned long hints[5] = {2, 0, 0, 0, 0};
  Atom m = A("_MOTIF_WM_HINTS");
  XChangeProperty(g_dpy, w, m, m, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(hints), 5);
}

void SetTitle(Window w, const char* title, const char* res_name, const char* res_class) {
  XStoreName(g_dpy, w, title);
  XChangeProperty(g_dpy, w, A("_NET_WM_NAME"), A("UTF8_STRING"), 8, PropModeReplace,
                  reinterpret_cast<const unsigned char*>(title),
                  static_cast<int>(strlen(title)));
  XClassHint ch;
  ch.res_name = const_cast<char*>(res_name);
  ch.res_class = const_cast<char*>(res_class);
  XSetClassHint(g_dpy, w, &ch);
}

// The session has no window manager: the shell moves its own windows while
// the title bar is dragged, and tracks the active window itself.
Window g_drag_win = 0;
int g_drag_dx = 0, g_drag_dy = 0;

void StartWindowMove(Window w, int x_root, int y_root, Time t) {
  int rx = 0, ry = 0;
  Window child = 0;
  XTranslateCoordinates(g_dpy, w, g_root, 0, 0, &rx, &ry, &child);
  g_drag_win = w;
  g_drag_dx = x_root - rx;
  g_drag_dy = y_root - ry;
  XGrabPointer(g_dpy, w, False, ButtonReleaseMask | PointerMotionMask, GrabModeAsync,
               GrabModeAsync, None, None, t);
}

void SetActiveWindowProperty(Window v) {
  unsigned long value = v;
  XChangeProperty(g_dpy, g_root, A("_DARLING_ACTIVE_WINDOW"), XA_WINDOW, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(&value), 1);
  XFlush(g_dpy);
}

// Raises and focuses one of the shell's own windows (Finder menus).
void FocusOwnWindow(Window w) {
  XRaiseWindow(g_dpy, w);
  XWindowAttributes wa;
  if (XGetWindowAttributes(g_dpy, w, &wa) && wa.map_state == IsViewable) {
    XSetInputFocus(g_dpy, w, RevertToPointerRoot, CurrentTime);
  }
  SetActiveWindowProperty(0);
}

unsigned char* GetProp(Window w, Atom prop, Atom type, unsigned long* count) {
  Atom actual = None;
  int fmt = 0;
  unsigned long n = 0, rem = 0;
  unsigned char* data = nullptr;
  if (XGetWindowProperty(g_dpy, w, prop, 0, 1 << 20, False, type, &actual, &fmt, &n, &rem,
                         &data) != Success) {
    return nullptr;
  }
  if (!data || actual == None) {
    if (data) XFree(data);
    return nullptr;
  }
  if (count) *count = n;
  return data;
}

// Traffic-light window buttons (close, minimize, zoom) with hover glyphs.
void DrawTrafficLights(cairo_t* cr, double x, double y, bool active, bool hover) {
  static const double kFill[3][3] = {{1.0, 0.373, 0.341}, {0.996, 0.737, 0.180},
                                     {0.157, 0.784, 0.251}};
  static const double kEdge[3][3] = {{0.878, 0.267, 0.243}, {0.871, 0.631, 0.137},
                                     {0.102, 0.671, 0.161}};
  static const double kGlyph[3][3] = {{0.30, 0.0, 0.0}, {0.60, 0.34, 0.0},
                                      {0.0, 0.39, 0.0}};
  for (int i = 0; i < 3; ++i) {
    double cx = x + i * 20.0;
    cairo_arc(cr, cx, y, 6.0, 0, 2 * kPi);
    if (active || hover) {
      cairo_set_source_rgb(cr, kFill[i][0], kFill[i][1], kFill[i][2]);
    } else {
      cairo_set_source_rgb(cr, 0.84, 0.84, 0.85);
    }
    cairo_fill_preserve(cr);
    if (active || hover) {
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
      cairo_move_to(cr, cx - 2.6, y - 2.6);
      cairo_line_to(cr, cx + 2.6, y + 2.6);
      cairo_move_to(cr, cx + 2.6, y - 2.6);
      cairo_line_to(cr, cx - 2.6, y + 2.6);
      cairo_stroke(cr);
    } else if (i == 1) {
      cairo_move_to(cr, cx - 3.2, y);
      cairo_line_to(cr, cx + 3.2, y);
      cairo_stroke(cr);
    } else {
      // Two arrowheads pointing to the top-right and bottom-left corners.
      cairo_move_to(cr, cx - 2.8, y - 1.2);
      cairo_line_to(cr, cx - 2.8, y - 2.8);
      cairo_line_to(cr, cx + 1.2, y - 2.8);
      cairo_close_path(cr);
      cairo_move_to(cr, cx + 2.8, y + 1.2);
      cairo_line_to(cr, cx + 2.8, y + 2.8);
      cairo_line_to(cr, cx - 1.2, y + 2.8);
      cairo_close_path(cr);
      cairo_fill(cr);
    }
  }
}

// Mac OS X push button (white bezel, or blue when |is_default|).
void DrawPushButton(cairo_t* cr, double x, double y, double w, double h, const char* title,
                    bool is_default, bool pressed) {
  RoundRect(cr, x, y + 0.5, w, h, 5.5);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.10);
  cairo_fill(cr);
  RoundRect(cr, x, y, w, h, 5.5);
  if (is_default) {
    cairo_pattern_t* g = cairo_pattern_create_linear(0, y, 0, y + h);
    cairo_pattern_add_color_stop_rgb(g, 0, 0.20, 0.56, 1.0);
    cairo_pattern_add_color_stop_rgb(g, 1, 0.02, 0.43, 0.95);
    cairo_set_source(cr, g);
    cairo_fill_preserve(cr);
    cairo_pattern_destroy(g);
    if (pressed) {
      cairo_set_source_rgba(cr, 0, 0, 0, 0.18);
      cairo_fill_preserve(cr);
    }
    cairo_set_source_rgba(cr, 0, 0.25, 0.7, 0.6);
  } else {
    cairo_set_source_rgb(cr, pressed ? 0.86 : 1.0, pressed ? 0.86 : 1.0, pressed ? 0.87 : 1.0);
    cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.20);
  }
  cairo_set_line_width(cr, 0.8);
  cairo_stroke(cr);
  SetFont(cr, 13, false);
  if (is_default) {
    cairo_set_source_rgb(cr, 1, 1, 1);
  } else {
    cairo_set_source_rgba(cr, 0, 0, 0, 0.85);
  }
  TextCentered(cr, x + w / 2, y + h / 2 + 4.5, title);
}

// ---------------------------------------------------------------------------
// Wallpaper and desktop
// ---------------------------------------------------------------------------
struct WaveSpec {
  double y0, c1x, c1y, c2x, c2y, y1;
  double top[4], bottom[4];
};

void RenderWallpaper(cairo_t* cr, int w, int h) {
  cairo_pattern_t* sky = cairo_pattern_create_linear(0, 0, 0, h);
  cairo_pattern_add_color_stop_rgb(sky, 0.00, 0.04, 0.11, 0.30);
  cairo_pattern_add_color_stop_rgb(sky, 0.35, 0.12, 0.31, 0.68);
  cairo_pattern_add_color_stop_rgb(sky, 0.62, 0.36, 0.50, 0.85);
  cairo_pattern_add_color_stop_rgb(sky, 0.82, 0.79, 0.55, 0.75);
  cairo_pattern_add_color_stop_rgb(sky, 1.00, 0.95, 0.66, 0.54);
  cairo_set_source(cr, sky);
  cairo_paint(cr);
  cairo_pattern_destroy(sky);

  cairo_pattern_t* glow = cairo_pattern_create_radial(w * 0.72, h * 0.28, 0, w * 0.72,
                                                      h * 0.28, w * 0.48);
  cairo_pattern_add_color_stop_rgba(glow, 0, 1, 0.95, 0.90, 0.30);
  cairo_pattern_add_color_stop_rgba(glow, 1, 1, 0.95, 0.90, 0.0);
  cairo_set_source(cr, glow);
  cairo_paint(cr);
  cairo_pattern_destroy(glow);

  const WaveSpec waves[] = {
      {0.56, 0.30, 0.42, 0.55, 0.70, 0.50, {0.24, 0.39, 0.84, 0.85}, {0.14, 0.13, 0.43, 0.95}},
      {0.73, 0.25, 0.60, 0.65, 0.88, 0.66, {0.88, 0.40, 0.61, 0.85}, {0.42, 0.17, 0.56, 0.95}},
      {0.89, 0.40, 0.77, 0.70, 0.99, 0.83, {1.00, 0.64, 0.42, 0.90}, {0.76, 0.25, 0.44, 0.97}},
  };
  for (const WaveSpec& wv : waves) {
    cairo_move_to(cr, 0, h * wv.y0);
    cairo_curve_to(cr, w * wv.c1x, h * wv.c1y, w * wv.c2x, h * wv.c2y, w, h * wv.y1);
    cairo_line_to(cr, w, h);
    cairo_line_to(cr, 0, h);
    cairo_close_path(cr);
    cairo_pattern_t* g = cairo_pattern_create_linear(0, h * wv.y0 - 60, 0, h);
    cairo_pattern_add_color_stop_rgba(g, 0, wv.top[0], wv.top[1], wv.top[2], wv.top[3]);
    cairo_pattern_add_color_stop_rgba(g, 1, wv.bottom[0], wv.bottom[1], wv.bottom[2],
                                      wv.bottom[3]);
    cairo_set_source(cr, g);
    cairo_fill(cr);
    cairo_pattern_destroy(g);
    cairo_move_to(cr, 0, h * wv.y0);
    cairo_curve_to(cr, w * wv.c1x, h * wv.c1y, w * wv.c2x, h * wv.c2y, w, h * wv.y1);
    cairo_set_source_rgba(cr, 1, 1, 1, 0.16);
    cairo_set_line_width(cr, 1.5);
    cairo_stroke(cr);
  }
}

void DrawHardDiskIcon(cairo_t* cr, double x, double y, double s) {
  cairo_save(cr);
  cairo_translate(cr, x, y);
  cairo_scale(cr, s / 64.0, s / 64.0);
  RoundRect(cr, 5, 17, 54, 32, 6);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.25);
  cairo_fill(cr);
  RoundRect(cr, 5, 15, 54, 32, 6);
  cairo_pattern_t* g = cairo_pattern_create_linear(0, 15, 0, 47);
  cairo_pattern_add_color_stop_rgb(g, 0, 0.97, 0.97, 0.98);
  cairo_pattern_add_color_stop_rgb(g, 0.62, 0.80, 0.81, 0.84);
  cairo_pattern_add_color_stop_rgb(g, 1, 0.62, 0.63, 0.67);
  cairo_set_source(cr, g);
  cairo_fill_preserve(cr);
  cairo_pattern_destroy(g);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.35);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  cairo_rectangle(cr, 6, 38, 52, 1);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.18);
  cairo_fill(cr);
  cairo_arc(cr, 50, 43, 1.8, 0, 2 * kPi);
  cairo_set_source_rgb(cr, 0.25, 0.85, 0.35);
  cairo_fill(cr);
  for (int i = 0; i < 6; ++i) {
    cairo_rectangle(cr, 12 + i * 4, 41.5, 2, 3);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.25);
    cairo_fill(cr);
  }
  cairo_restore(cr);
}

void DrawDesktopIcons(cairo_t* cr, int w) {
  double x = w - 84, y = kBarH + 14;
  DrawHardDiskIcon(cr, x, y, 64);
  SetFont(cr, 12, false);
  const char* label = "Macintosh HD";
  double tw = TextW(cr, label);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.55);
  Text(cr, x + 32 - tw / 2, y + 66 + 1, label);
  cairo_set_source_rgb(cr, 1, 1, 1);
  Text(cr, x + 32 - tw / 2, y + 66, label);
}

void SetupWallpaper() {
  g_wall = NewImage(g_w, g_h);
  cairo_t* cr = cairo_create(g_wall);
  RenderWallpaper(cr, g_w, g_h);
  cairo_destroy(cr);
  cairo_surface_t* desk = NewImage(g_w, g_h);
  cr = cairo_create(desk);
  cairo_set_source_surface(cr, g_wall, 0, 0);
  cairo_paint(cr);
  DrawDesktopIcons(cr, g_w);
  cairo_destroy(cr);

  g_wall_pm = XCreatePixmap(g_dpy, g_root, static_cast<unsigned>(g_w),
                            static_cast<unsigned>(g_h), static_cast<unsigned>(g_depth));
  cairo_surface_flush(desk);
  XImage* xi = XCreateImage(g_dpy, g_vis, static_cast<unsigned>(g_depth), ZPixmap, 0,
                            reinterpret_cast<char*>(cairo_image_surface_get_data(desk)),
                            static_cast<unsigned>(g_w), static_cast<unsigned>(g_h), 32,
                            cairo_image_surface_get_stride(desk));
  GC gc = XCreateGC(g_dpy, g_wall_pm, 0, nullptr);
  XPutImage(g_dpy, g_wall_pm, gc, xi, 0, 0, 0, 0, static_cast<unsigned>(g_w),
            static_cast<unsigned>(g_h));
  XFreeGC(g_dpy, gc);
  xi->data = nullptr;
  XDestroyImage(xi);
  g_desk = desk;
  XSetWindowBackgroundPixmap(g_dpy, g_root, g_wall_pm);
  XClearWindow(g_dpy, g_root);
  XChangeProperty(g_dpy, g_root, A("_XROOTPMAP_ID"), XA_PIXMAP, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(&g_wall_pm), 1);
  XChangeProperty(g_dpy, g_root, A("ESETROOT_PMAP_ID"), XA_PIXMAP, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(&g_wall_pm), 1);
}

// Re-renders the desktop background with soft window shadows beneath the
// mapped windows (there is no compositing manager; shadows are visible over
// the desktop).
void RenderDesktopWithShadows(const Window* wins, int n) {
  cairo_surface_t* img = NewImage(g_w, g_h);
  cairo_t* cr = cairo_create(img);
  cairo_set_source_surface(cr, g_desk, 0, 0);
  cairo_paint(cr);
  for (int k = 0; k < n; ++k) {
    XWindowAttributes wa;
    if (!XGetWindowAttributes(g_dpy, wins[k], &wa) || wa.map_state != IsViewable ||
        wa.override_redirect || wa.width < 40 || wa.height < 30) {
      continue;
    }
    for (int i = 22; i >= 1; --i) {
      RoundRect(cr, wa.x - i, wa.y - i * 0.55 + 9, wa.width + 2 * i, wa.height + i * 1.1,
                10 + i);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.018);
      cairo_fill(cr);
    }
    RoundRect(cr, wa.x - 1, wa.y, wa.width + 2, wa.height + 2, 11);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.18);
    cairo_fill(cr);
  }
  cairo_destroy(cr);
  cairo_surface_flush(img);
  XImage* xi = XCreateImage(g_dpy, g_vis, static_cast<unsigned>(g_depth), ZPixmap, 0,
                            reinterpret_cast<char*>(cairo_image_surface_get_data(img)),
                            static_cast<unsigned>(g_w), static_cast<unsigned>(g_h), 32,
                            cairo_image_surface_get_stride(img));
  GC gc = XCreateGC(g_dpy, g_wall_pm, 0, nullptr);
  XPutImage(g_dpy, g_wall_pm, gc, xi, 0, 0, 0, 0, static_cast<unsigned>(g_w),
            static_cast<unsigned>(g_h));
  XFreeGC(g_dpy, gc);
  xi->data = nullptr;
  XDestroyImage(xi);
  cairo_surface_destroy(img);
  XClearWindow(g_dpy, g_root);
  XFlush(g_dpy);
}

// Blurred copy of a wallpaper region (cheap down/up-sampling blur).
cairo_surface_t* BlurredWallpaper(int x, int y, int w, int h, int factor) {
  int sw = w / factor + 2, sh = h / factor + 2;
  cairo_surface_t* small = NewImage(sw, sh);
  cairo_t* cr = cairo_create(small);
  cairo_scale(cr, static_cast<double>(sw) / (w + 2 * factor),
              static_cast<double>(sh) / (h + 2 * factor));
  cairo_set_source_surface(cr, g_wall, -x + factor, -y + factor);
  cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
  cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
  cairo_paint(cr);
  cairo_destroy(cr);
  cairo_surface_t* out = NewImage(w, h);
  cr = cairo_create(out);
  cairo_translate(cr, -factor, -factor);
  cairo_scale(cr, (w + 2.0 * factor) / sw, (h + 2.0 * factor) / sh);
  cairo_set_source_surface(cr, small, 0, 0);
  cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
  cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BILINEAR);
  cairo_paint(cr);
  cairo_destroy(cr);
  cairo_surface_destroy(small);
  return out;
}

// ---------------------------------------------------------------------------
// Mac OS X arrow cursor (ARGB via XRender)
// ---------------------------------------------------------------------------
void SetupCursor() {
  int ev = 0, er = 0;
  if (!XRenderQueryExtension(g_dpy, &ev, &er)) return;
  const int cw = 24, chh = 32;
  cairo_surface_t* img = NewImage(cw, chh);
  cairo_t* cr = cairo_create(img);
  auto arrow = [&](double ox, double oy) {
    cairo_move_to(cr, ox + 0, oy + 0);
    cairo_line_to(cr, ox + 0, oy + 17);
    cairo_line_to(cr, ox + 4, oy + 13);
    cairo_line_to(cr, ox + 7, oy + 20);
    cairo_line_to(cr, ox + 10, oy + 19);
    cairo_line_to(cr, ox + 7, oy + 12.2);
    cairo_line_to(cr, ox + 12.5, oy + 12.2);
    cairo_close_path(cr);
  };
  arrow(3.0, 3.8);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
  cairo_set_line_width(cr, 3.0);
  cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
  cairo_stroke(cr);
  arrow(2.0, 2.0);
  cairo_set_source_rgb(cr, 1, 1, 1);
  cairo_set_line_width(cr, 2.4);
  cairo_stroke_preserve(cr);
  cairo_set_source_rgb(cr, 0, 0, 0);
  cairo_fill(cr);
  cairo_destroy(cr);
  cairo_surface_flush(img);

  XRenderPictFormat* fmt = XRenderFindStandardFormat(g_dpy, PictStandardARGB32);
  if (!fmt) {
    cairo_surface_destroy(img);
    return;
  }
  Pixmap pm = XCreatePixmap(g_dpy, g_root, cw, chh, 32);
  XImage* xi = XCreateImage(g_dpy, g_vis, 32, ZPixmap, 0,
                            reinterpret_cast<char*>(cairo_image_surface_get_data(img)), cw,
                            chh, 32, cairo_image_surface_get_stride(img));
  GC gc = XCreateGC(g_dpy, pm, 0, nullptr);
  XPutImage(g_dpy, pm, gc, xi, 0, 0, 0, 0, cw, chh);
  XFreeGC(g_dpy, gc);
  xi->data = nullptr;
  XDestroyImage(xi);
  Picture pic = XRenderCreatePicture(g_dpy, pm, fmt, 0, nullptr);
  g_cursor = XRenderCreateCursor(g_dpy, pic, 2, 2);
  XRenderFreePicture(g_dpy, pic);
  XFreePixmap(g_dpy, pm);
  cairo_surface_destroy(img);
  if (g_cursor) XDefineCursor(g_dpy, g_root, g_cursor);
}

}  // namespace

namespace {

// ---------------------------------------------------------------------------
// Menu model
// ---------------------------------------------------------------------------
enum Action {
  kActNone = 0,
  kActAboutMac,
  kActSettings,
  kActForceQuit,
  kActSleep,
  kActRestart,
  kActShutDown,
  kActLock,
  kActLogOut,
  kActAboutFinder,
  kActNewFinderWindow,
  kActApplications,
  kActCloseFinder,
  kActQuitForeign,
  kActCloseForeign,
  kActMinimizeForeign,
};

struct MItem {
  char title[128];
  char key[32];
  bool enabled, separator, checked, hidden;
  int child, next, depth, nchildren;
  int path[5];
  int action;
};

constexpr int kMaxItems = 1600;
MItem g_items[kMaxItems];
int g_nitems = 0;
int g_menu_root = -1;   // container of the top-level menus
int g_apple_root = -1;  // Apple menu

enum MenuMode { kModeFinder = 0, kModeApp = 1, kModeForeign = 2 };
int g_mode = kModeFinder;
Window g_active = 0;
pid_t g_active_pid = 0;
char g_app_name[128] = "Finder";

int NewItem() {
  if (g_nitems >= kMaxItems) return -1;
  MItem& m = g_items[g_nitems];
  memset(&m, 0, sizeof(m));
  m.child = m.next = -1;
  m.enabled = true;
  m.depth = -1;
  return g_nitems++;
}

int AddChild(int parent, const char* title, const char* key = "", int action = kActNone,
             bool enabled = true) {
  if (parent < 0) return -1;
  int idx = NewItem();
  if (idx < 0) return -1;
  MItem& m = g_items[idx];
  snprintf(m.title, sizeof(m.title), "%s", title ? title : "");
  snprintf(m.key, sizeof(m.key), "%s", key ? key : "");
  m.action = action;
  m.enabled = enabled;
  MItem& p = g_items[parent];
  m.depth = p.depth + 1;
  memcpy(m.path, p.path, sizeof(m.path));
  if (m.depth >= 0 && m.depth < 5) m.path[m.depth] = p.nchildren;
  p.nchildren++;
  if (p.child < 0) {
    p.child = idx;
  } else {
    int c = p.child;
    while (g_items[c].next >= 0) c = g_items[c].next;
    g_items[c].next = idx;
  }
  return idx;
}

int AddSep(int parent) {
  int i = AddChild(parent, "", "", kActNone, false);
  if (i >= 0) g_items[i].separator = true;
  return i;
}

void BuildAppleMenu() {
  g_apple_root = NewItem();
  int a = g_apple_root;
  AddChild(a, "About This Mac", "", kActAboutMac);
  AddSep(a);
  AddChild(a, "System Settings\xE2\x80\xA6", "", kActSettings);
  AddChild(a, "App Store\xE2\x80\xA6", "", kActNone, false);
  AddSep(a);
  AddChild(a, "Recent Items", "", kActNone, false);
  AddSep(a);
  AddChild(a, "Force Quit\xE2\x80\xA6", "\xE2\x8C\xA5\xE2\x8C\x98\xE2\x8E\x8B", kActForceQuit);
  AddSep(a);
  AddChild(a, "Sleep", "", kActSleep);
  AddChild(a, "Restart\xE2\x80\xA6", "", kActRestart);
  AddChild(a, "Shut Down\xE2\x80\xA6", "", kActShutDown);
  AddSep(a);
  AddChild(a, "Lock Screen", "\xE2\x8C\x83\xE2\x8C\x98Q", kActLock);
  AddChild(a, "Log Out root\xE2\x80\xA6", "\xE2\x87\xA7\xE2\x8C\x98Q", kActLogOut);
}

void ResetMenus() {
  g_nitems = 0;
  BuildAppleMenu();
  g_menu_root = NewItem();
}

void BuildFinderMenus() {
  ResetMenus();
  g_mode = kModeFinder;
  snprintf(g_app_name, sizeof(g_app_name), "Finder");
  int r = g_menu_root;
  int m = AddChild(r, "Finder");
  AddChild(m, "About Finder", "", kActAboutFinder);
  AddSep(m);
  AddChild(m, "Settings\xE2\x80\xA6", "\xE2\x8C\x98,", kActNone, false);
  AddSep(m);
  AddChild(m, "Empty Trash\xE2\x80\xA6", "\xE2\x87\xA7\xE2\x8C\x98\xE2\x8C\xAB", kActNone, false);
  AddSep(m);
  AddChild(m, "Hide Finder", "\xE2\x8C\x98H", kActNone, false);
  AddChild(m, "Hide Others", "\xE2\x8C\xA5\xE2\x8C\x98H", kActNone, false);
  AddChild(m, "Show All", "", kActNone, false);
  m = AddChild(r, "File");
  AddChild(m, "New Finder Window", "\xE2\x8C\x98N", kActNewFinderWindow);
  AddChild(m, "New Folder", "\xE2\x87\xA7\xE2\x8C\x98N", kActNone, false);
  AddChild(m, "Open", "\xE2\x8C\x98O", kActNone, false);
  AddChild(m, "Close Window", "\xE2\x8C\x98W", kActCloseFinder);
  AddSep(m);
  AddChild(m, "Get Info", "\xE2\x8C\x98I", kActNone, false);
  m = AddChild(r, "Edit");
  AddChild(m, "Undo", "\xE2\x8C\x98Z", kActNone, false);
  AddChild(m, "Redo", "\xE2\x87\xA7\xE2\x8C\x98Z", kActNone, false);
  AddSep(m);
  AddChild(m, "Cut", "\xE2\x8C\x98X", kActNone, false);
  AddChild(m, "Copy", "\xE2\x8C\x98" "C", kActNone, false);
  AddChild(m, "Paste", "\xE2\x8C\x98V", kActNone, false);
  AddChild(m, "Select All", "\xE2\x8C\x98" "A", kActNone, false);
  m = AddChild(r, "View");
  int it = AddChild(m, "as Icons", "\xE2\x8C\x98" "1", kActNone, true);
  if (it >= 0) g_items[it].checked = true;
  AddChild(m, "as List", "\xE2\x8C\x98" "2", kActNone, false);
  AddChild(m, "as Columns", "\xE2\x8C\x98" "3", kActNone, false);
  AddChild(m, "as Gallery", "\xE2\x8C\x98" "4", kActNone, false);
  m = AddChild(r, "Go");
  AddChild(m, "Back", "\xE2\x8C\x98[", kActNone, false);
  AddChild(m, "Forward", "\xE2\x8C\x98]", kActNone, false);
  AddSep(m);
  AddChild(m, "Applications", "\xE2\x87\xA7\xE2\x8C\x98" "A", kActApplications);
  AddChild(m, "Utilities", "\xE2\x87\xA7\xE2\x8C\x98U", kActNone, false);
  AddChild(m, "Computer", "\xE2\x87\xA7\xE2\x8C\x98" "C", kActNone, false);
  m = AddChild(r, "Window");
  AddChild(m, "Minimize", "\xE2\x8C\x98M", kActNone, false);
  AddChild(m, "Zoom", "", kActNone, false);
  AddSep(m);
  AddChild(m, "Bring All to Front", "", kActNone, false);
  m = AddChild(r, "Help");
  AddChild(m, "macOS Help", "", kActNone, false);
}

void BuildForeignMenus(const char* name) {
  ResetMenus();
  g_mode = kModeForeign;
  snprintf(g_app_name, sizeof(g_app_name), "%s", name);
  char buf[160];
  int r = g_menu_root;
  int m = AddChild(r, name);
  snprintf(buf, sizeof(buf), "About %s", name);
  AddChild(m, buf, "", kActNone, false);
  AddSep(m);
  snprintf(buf, sizeof(buf), "Hide %s", name);
  AddChild(m, buf, "\xE2\x8C\x98H", kActNone, false);
  AddSep(m);
  snprintf(buf, sizeof(buf), "Quit %s", name);
  AddChild(m, buf, "\xE2\x8C\x98Q", kActQuitForeign);
  m = AddChild(r, "File");
  AddChild(m, "Close Window", "\xE2\x8C\x98W", kActCloseForeign);
  m = AddChild(r, "Edit");
  AddChild(m, "Cut", "\xE2\x8C\x98X", kActNone, false);
  AddChild(m, "Copy", "\xE2\x8C\x98" "C", kActNone, false);
  AddChild(m, "Paste", "\xE2\x8C\x98V", kActNone, false);
  m = AddChild(r, "View");
  AddChild(m, "Enter Full Screen", "\xE2\x8C\x83\xE2\x8C\x98" "F", kActNone, false);
  m = AddChild(r, "Window");
  AddChild(m, "Minimize", "\xE2\x8C\x98M", kActMinimizeForeign);
  m = AddChild(r, "Help");
  AddChild(m, "Search", "", kActNone, false);
}

// Parses the menu that AppKit publishes in _DARLING_APP_MENU:
//   "#<AppName>\n" then one line per item:
//   <depth tabs><flags>\x1f<title>\x1f<key equivalent>\n
// with flags E (enabled), D (disabled), S (separator), C (checked), H (hidden).
void ParseAppMenu(const char* text) {
  ResetMenus();
  g_mode = kModeApp;
  int stack[8];
  for (int& s : stack) s = -1;
  stack[0] = g_menu_root;
  const char* p = text;
  while (p && *p) {
    const char* eol = strchr(p, '\n');
    size_t len = eol ? static_cast<size_t>(eol - p) : strlen(p);
    char line[512];
    if (len >= sizeof(line)) len = sizeof(line) - 1;
    memcpy(line, p, len);
    line[len] = '\0';
    p = eol ? eol + 1 : nullptr;
    if (line[0] == '#') {
      snprintf(g_app_name, sizeof(g_app_name), "%s", line + 1);
      continue;
    }
    int depth = 0;
    while (line[depth] == '\t') ++depth;
    if (depth > 4) continue;
    char* flags = line + depth;
    char* sep1 = strchr(flags, '\x1f');
    if (!sep1) continue;
    *sep1 = '\0';
    char* title = sep1 + 1;
    char* sep2 = strchr(title, '\x1f');
    const char* key = "";
    if (sep2) {
      *sep2 = '\0';
      key = sep2 + 1;
    }
    int parent = stack[depth];
    if (parent < 0) continue;
    int idx = AddChild(parent, title, key, kActNone, strchr(flags, 'E') != nullptr);
    if (idx < 0) break;
    g_items[idx].separator = strchr(flags, 'S') != nullptr;
    g_items[idx].checked = strchr(flags, 'C') != nullptr;
    g_items[idx].hidden = strchr(flags, 'H') != nullptr;
    stack[depth + 1] = idx;
    for (int d = depth + 2; d < 8; ++d) stack[d] = -1;
  }
}

// ---------------------------------------------------------------------------
// Menu bar
// ---------------------------------------------------------------------------
struct BarEntry {
  int item;
  double x, w;
  int kind;  // 0 = Apple logo, 1 = bold application name, 2 = menu title
  char title[128];
};

Window g_bar = 0;
cairo_surface_t* g_bar_bg = nullptr;
BarEntry g_entries[32];
int g_nentries = 0;
double g_status_x = 0;
int g_open_entry = -1;
int g_last_minute = -1;

struct Drop {
  Window win;
  int parent;
  int x, y, w, h;
  int hover;
  int nkids;
  int kids[128];
  double ky[128], kh[128];
};
Drop g_drops[4];
int g_ndrops = 0;
bool g_grabbed = false;
double g_press_time = 0;

void DrawAppleLogo(cairo_t* cr, double x, double y, double s) {
  // A stylised apple in a 1x1 box at (x, y) scaled by |s|.
  cairo_save(cr);
  cairo_translate(cr, x, y);
  cairo_scale(cr, s, s);
  cairo_push_group(cr);
  cairo_arc(cr, 0.33, 0.58, 0.29, 0, 2 * kPi);
  cairo_fill(cr);
  cairo_arc(cr, 0.63, 0.58, 0.29, 0, 2 * kPi);
  cairo_fill(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
  cairo_arc(cr, 0.48, 0.26, 0.085, 0, 2 * kPi);
  cairo_fill(cr);
  cairo_arc(cr, 0.48, 0.93, 0.07, 0, 2 * kPi);
  cairo_fill(cr);
  cairo_arc(cr, 1.00, 0.52, 0.17, 0, 2 * kPi);
  cairo_fill(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  cairo_save(cr);
  cairo_translate(cr, 0.58, 0.12);
  cairo_rotate(cr, -0.85);
  cairo_scale(cr, 0.15, 0.075);
  cairo_arc(cr, 0, 0, 1, 0, 2 * kPi);
  cairo_restore(cr);
  cairo_fill(cr);
  cairo_pop_group_to_source(cr);
  cairo_paint(cr);
  cairo_restore(cr);
}

void DrawStatusIcons(cairo_t* cr, double right) {
  // Clock.
  time_t now = time(nullptr);
  struct tm tmv;
  localtime_r(&now, &tmv);
  static const char* kDays[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
  static const char* kMonths[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
  int hour12 = tmv.tm_hour % 12 == 0 ? 12 : tmv.tm_hour % 12;
  char clock[64];
  snprintf(clock, sizeof(clock), "%s %s %d  %d:%02d %s", kDays[tmv.tm_wday % 7],
           kMonths[tmv.tm_mon % 12], tmv.tm_mday, hour12, tmv.tm_min,
           tmv.tm_hour < 12 ? "AM" : "PM");
  SetFont(cr, 13, false);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.86);
  double cw = TextW(cr, clock);
  double x = right - cw;
  Text(cr, x, 16.5, clock);
  double cy = kBarH / 2.0;

  // Control Center (two toggles).
  x -= 30;
  cairo_set_line_width(cr, 1.3);
  RoundRect(cr, x, cy - 6.5, 15, 5.5, 2.75);
  cairo_stroke(cr);
  RoundRect(cr, x, cy + 1, 15, 5.5, 2.75);
  cairo_stroke(cr);
  cairo_arc(cr, x + 11.5, cy - 3.75, 1.7, 0, 2 * kPi);
  cairo_fill(cr);
  cairo_arc(cr, x + 3.5, cy + 3.75, 1.7, 0, 2 * kPi);
  cairo_fill(cr);

  // Spotlight.
  x -= 26;
  cairo_set_line_width(cr, 1.6);
  cairo_arc(cr, x + 6, cy - 1.5, 4.6, 0, 2 * kPi);
  cairo_stroke(cr);
  cairo_move_to(cr, x + 9.4, cy + 1.9);
  cairo_line_to(cr, x + 13, cy + 5.5);
  cairo_stroke(cr);

  // Wi-Fi.
  x -= 28;
  double wx = x + 8, wy = cy + 5;
  cairo_set_line_width(cr, 1.7);
  for (int i = 1; i <= 3; ++i) {
    cairo_arc(cr, wx, wy, 3.4 * i, -kPi * 0.75, -kPi * 0.25);
    cairo_stroke(cr);
  }
  cairo_arc(cr, wx, wy - 0.4, 1.4, 0, 2 * kPi);
  cairo_fill(cr);

  // Battery.
  x -= 36;
  cairo_set_line_width(cr, 1.0);
  RoundRect(cr, x + 0.5, cy - 5, 23, 10.5, 3);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.45);
  cairo_stroke(cr);
  RoundRect(cr, x + 2.5, cy - 3, 19, 6.5, 1.5);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.86);
  cairo_fill(cr);
  RoundRect(cr, x + 24.5, cy - 2, 1.8, 4.5, 0.9);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.45);
  cairo_fill(cr);
  g_status_x = x - 12;
}

void LayoutBar(cairo_t* cr) {
  g_nentries = 0;
  double x = 6;
  BarEntry& apple = g_entries[g_nentries++];
  apple.item = g_apple_root;
  apple.x = x;
  apple.w = 36;
  apple.kind = 0;
  apple.title[0] = '\0';
  x += apple.w;
  bool first = true;
  for (int c = g_items[g_menu_root].child; c >= 0 && g_nentries < 32; c = g_items[c].next) {
    if (g_items[c].hidden || g_items[c].separator) continue;
    BarEntry& e = g_entries[g_nentries];
    e.item = c;
    e.kind = first ? 1 : 2;
    snprintf(e.title, sizeof(e.title), "%s", first ? g_app_name : g_items[c].title);
    if (first) {
      SetFont(cr, 13, true);
    } else {
      SetFont(cr, 13, false);
    }
    double tw = TextW(cr, e.title);
    if (x + tw + 22 > g_status_x && g_status_x > 0) break;
    e.x = x;
    e.w = tw + 22;
    x += e.w;
    first = false;
    ++g_nentries;
  }
}

void ReportBarLayout() {
  for (int i = 0; i < g_nentries; ++i) {
    printf("DARLING_MENUBAR_ITEM:%s:%d:%d\n", g_entries[i].kind == 0 ? "Apple" : g_entries[i].title,
           static_cast<int>(g_entries[i].x + g_entries[i].w / 2), kBarH / 2);
  }
  fflush(stdout);
}

void DrawBar() {
  if (!g_bar) return;
  if (!g_bar_bg) {
    g_bar_bg = BlurredWallpaper(0, 0, g_w, kBarH * 2, 16);
    cairo_t* cr = cairo_create(g_bar_bg);
    cairo_set_source_rgba(cr, 1, 1, 1, 0.62);
    cairo_paint(cr);
    cairo_destroy(cr);
  }
  cairo_surface_t* img = NewImage(g_w, kBarH);
  cairo_t* cr = cairo_create(img);
  cairo_set_source_surface(cr, g_bar_bg, 0, 0);
  cairo_paint(cr);
  cairo_rectangle(cr, 0, kBarH - 1, g_w, 1);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.10);
  cairo_fill(cr);
  DrawStatusIcons(cr, g_w - 12);
  LayoutBar(cr);
  for (int i = 0; i < g_nentries; ++i) {
    const BarEntry& e = g_entries[i];
    if (i == g_open_entry) {
      RoundRect(cr, e.x + 1, 3, e.w - 2, kBarH - 6, 4);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.14);
      cairo_fill(cr);
    }
    cairo_set_source_rgba(cr, 0, 0, 0, 0.88);
    if (e.kind == 0) {
      DrawAppleLogo(cr, e.x + 11, 4, 15);
    } else {
      SetFont(cr, 13, e.kind == 1);
      Text(cr, e.x + 11, 16.5, e.title);
    }
  }
  cairo_destroy(cr);
  Blit(g_bar, img);
  cairo_surface_destroy(img);
  XFlush(g_dpy);
}

// ---------------------------------------------------------------------------
// Drop-down menus
// ---------------------------------------------------------------------------
constexpr int kMenuPadY = 5;
constexpr int kItemH = 22;
constexpr int kSepH = 11;

void DrawDrop(int level) {
  Drop& d = g_drops[level];
  cairo_surface_t* img = NewImage(d.w, d.h);
  cairo_t* cr = cairo_create(img);
  RoundRect(cr, 0, 0, d.w, d.h, 7);
  cairo_set_source_rgb(cr, 0.955, 0.955, 0.962);
  cairo_fill(cr);
  RoundRect(cr, 0.5, 0.5, d.w - 1, d.h - 1, 6.5);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  for (int i = 0; i < d.nkids; ++i) {
    const MItem& m = g_items[d.kids[i]];
    double y = d.ky[i];
    if (m.separator) {
      cairo_rectangle(cr, 10, y + 5, d.w - 20, 1);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.11);
      cairo_fill(cr);
      continue;
    }
    bool hi = i == d.hover && m.enabled;
    if (hi) {
      RoundRect(cr, 5, y, d.w - 10, kItemH, 4);
      cairo_set_source_rgb(cr, 0.0, 0.40, 0.88);
      cairo_fill(cr);
    }
    SetFont(cr, 13, false);
    if (hi) {
      cairo_set_source_rgb(cr, 1, 1, 1);
    } else if (m.enabled) {
      cairo_set_source_rgba(cr, 0, 0, 0, 0.87);
    } else {
      cairo_set_source_rgba(cr, 0, 0, 0, 0.27);
    }
    if (m.checked) Text(cr, 9, y + 15.5, "\xE2\x9C\x93");
    Text(cr, 24, y + 15.5, m.title);
    if (m.child >= 0) {
      double ax = d.w - 16, ay = y + kItemH / 2.0;
      cairo_move_to(cr, ax, ay - 4);
      cairo_line_to(cr, ax + 4, ay);
      cairo_line_to(cr, ax, ay + 4);
      cairo_set_line_width(cr, 1.5);
      cairo_stroke(cr);
    } else if (m.key[0]) {
      if (!hi) {
        cairo_set_source_rgba(cr, 0, 0, 0, m.enabled ? 0.45 : 0.22);
      }
      Text(cr, d.w - 14 - TextW(cr, m.key), y + 15.5, m.key);
    }
  }
  cairo_destroy(cr);
  Blit(d.win, img);
  cairo_surface_destroy(img);
}

void CloseDropsFrom(int level) {
  while (g_ndrops > level) {
    --g_ndrops;
    XDestroyWindow(g_dpy, g_drops[g_ndrops].win);
  }
}

void OpenDrop(int level, int parent, int x, int y) {
  CloseDropsFrom(level);
  if (level >= 4 || parent < 0 || g_items[parent].child < 0) return;
  Drop& d = g_drops[level];
  memset(&d, 0, sizeof(Drop));
  d.parent = parent;
  d.hover = -1;
  cairo_surface_t* tmp = NewImage(4, 4);
  cairo_t* cr = cairo_create(tmp);
  SetFont(cr, 13, false);
  double maxw = 0, maxk = 0, yy = kMenuPadY;
  for (int c = g_items[parent].child; c >= 0 && d.nkids < 128; c = g_items[c].next) {
    const MItem& m = g_items[c];
    if (m.hidden) continue;
    d.kids[d.nkids] = c;
    d.ky[d.nkids] = yy;
    d.kh[d.nkids] = m.separator ? kSepH : kItemH;
    yy += d.kh[d.nkids];
    ++d.nkids;
    if (!m.separator) {
      double tw = TextW(cr, m.title);
      if (tw > maxw) maxw = tw;
      double kw = m.child >= 0 ? 14 : (m.key[0] ? TextW(cr, m.key) : 0);
      if (kw > maxk) maxk = kw;
    }
  }
  cairo_destroy(cr);
  cairo_surface_destroy(tmp);
  d.w = static_cast<int>(24 + maxw + (maxk > 0 ? 34 + maxk : 0) + 18);
  if (d.w < 180) d.w = 180;
  d.h = static_cast<int>(yy + kMenuPadY);
  if (x + d.w > g_w - 2) x = g_w - 2 - d.w;
  if (x < 2) x = 2;
  if (y + d.h > g_h - 2) y = g_h - 2 - d.h;
  d.x = x;
  d.y = y;
  XSetWindowAttributes attrs;
  memset(&attrs, 0, sizeof(attrs));
  attrs.override_redirect = True;
  attrs.save_under = True;
  attrs.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask;
  d.win = XCreateWindow(g_dpy, g_root, d.x, d.y, static_cast<unsigned>(d.w),
                        static_cast<unsigned>(d.h), 0, CopyFromParent, InputOutput,
                        CopyFromParent, CWOverrideRedirect | CWSaveUnder | CWEventMask, &attrs);
  ShapeRounded(d.win, d.w, d.h, 7);
  SetWindowType(d.win, "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU");
  XMapRaised(g_dpy, d.win);
  g_ndrops = level + 1;
  DrawDrop(level);
  for (int i = 0; i < d.nkids; ++i) {
    const MItem& m = g_items[d.kids[i]];
    if (m.separator) continue;
    printf("DARLING_MENU_ITEM:%s:%d:%d\n", m.title, d.x + d.w / 2,
           static_cast<int>(d.y + d.ky[i] + kItemH / 2));
  }
  fflush(stdout);
}

void Grab() {
  if (g_grabbed) return;
  XGrabPointer(g_dpy, g_bar, True, ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
               GrabModeAsync, GrabModeAsync, None, g_cursor, CurrentTime);
  XGrabKeyboard(g_dpy, g_bar, True, GrabModeAsync, GrabModeAsync, CurrentTime);
  g_grabbed = true;
}

void CloseMenus() {
  CloseDropsFrom(0);
  if (g_grabbed) {
    XUngrabPointer(g_dpy, CurrentTime);
    XUngrabKeyboard(g_dpy, CurrentTime);
    g_grabbed = false;
  }
  g_open_entry = -1;
  DrawBar();
}

void OpenEntry(int e) {
  if (e < 0 || e >= g_nentries) return;
  g_open_entry = e;
  DrawBar();
  OpenDrop(0, g_entries[e].item, static_cast<int>(g_entries[e].x), kBarH);
  Grab();
}

int BarEntryAt(int x, int y) {
  if (y < 0 || y >= kBarH) return -1;
  for (int i = 0; i < g_nentries; ++i) {
    if (x >= g_entries[i].x && x < g_entries[i].x + g_entries[i].w) return i;
  }
  return -1;
}

// Returns the deepest drop-down level containing the point, and the item.
int DropAt(int x, int y, int* item) {
  for (int l = g_ndrops - 1; l >= 0; --l) {
    const Drop& d = g_drops[l];
    if (x < d.x || x >= d.x + d.w || y < d.y || y >= d.y + d.h) continue;
    *item = -1;
    double ly = y - d.y;
    for (int i = 0; i < d.nkids; ++i) {
      if (ly >= d.ky[i] && ly < d.ky[i] + d.kh[i]) *item = i;
    }
    return l;
  }
  return -1;
}

void PerformInternal(int action);  // defined with the windows below

void Activate(int item_index) {
  const MItem& m = g_items[item_index];
  if (!m.enabled || m.separator || m.child >= 0) return;
  printf("DARLING_MENU_SELECT:%s\n", m.title);
  fflush(stdout);
  if (m.action != kActNone) {
    PerformInternal(m.action);
    return;
  }
  if (g_mode == kModeApp && g_active) {
    XEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.xclient.type = ClientMessage;
    ev.xclient.window = g_active;
    ev.xclient.message_type = A("_DARLING_MENU_ACTION");
    ev.xclient.format = 32;
    int len = m.depth + 1;
    if (len > 4) len = 4;
    ev.xclient.data.l[0] = len;
    for (int i = 0; i < len; ++i) ev.xclient.data.l[i + 1] = m.path[i];
    XSendEvent(g_dpy, g_active, False, NoEventMask, &ev);
    XFlush(g_dpy);
  }
}

void MenuMotion(int x, int y) {
  if (g_open_entry < 0) return;
  int e = BarEntryAt(x, y);
  if (e >= 0 && e != g_open_entry) {
    OpenEntry(e);
    return;
  }
  int item = -1;
  int level = DropAt(x, y, &item);
  if (level < 0) return;
  Drop& d = g_drops[level];
  if (d.hover != item) {
    d.hover = item;
    DrawDrop(level);
    if (item >= 0 && g_items[d.kids[item]].child >= 0 && g_items[d.kids[item]].enabled) {
      OpenDrop(level + 1, d.kids[item], d.x + d.w - 5,
               static_cast<int>(d.y + d.ky[item] - kMenuPadY));
    } else {
      CloseDropsFrom(level + 1);
    }
  }
}

void MenuPress(int x, int y) {
  int e = BarEntryAt(x, y);
  g_press_time = NowSec();
  if (e >= 0) {
    if (e == g_open_entry) {
      CloseMenus();
    } else {
      OpenEntry(e);
    }
    return;
  }
  int item = -1;
  if (DropAt(x, y, &item) >= 0) return;
  CloseMenus();
}

void MenuRelease(int x, int y) {
  if (g_open_entry < 0) return;
  int item = -1;
  int level = DropAt(x, y, &item);
  if (level >= 0 && item >= 0) {
    int idx = g_drops[level].kids[item];
    const MItem& m = g_items[idx];
    if (m.enabled && !m.separator && m.child < 0) {
      CloseMenus();
      Activate(idx);
    }
    return;
  }
  if (BarEntryAt(x, y) >= 0) return;  // sticky menu after a click
  if (NowSec() - g_press_time > 0.35) CloseMenus();
}

void MenuKey(KeySym ks) {
  if (g_open_entry < 0) return;
  Drop& d = g_drops[g_ndrops - 1];
  if (ks == XK_Escape) {
    CloseMenus();
  } else if (ks == XK_Down || ks == XK_Up) {
    int step = ks == XK_Down ? 1 : -1;
    int h = d.hover;
    for (int n = 0; n < d.nkids; ++n) {
      h = (h + step + d.nkids) % d.nkids;
      const MItem& m = g_items[d.kids[h]];
      if (!m.separator && m.enabled) break;
    }
    d.hover = h;
    DrawDrop(g_ndrops - 1);
  } else if (ks == XK_Left || ks == XK_Right) {
    int e = (g_open_entry + (ks == XK_Right ? 1 : -1) + g_nentries) % g_nentries;
    OpenEntry(e);
  } else if (ks == XK_Return || ks == XK_KP_Enter) {
    if (d.hover >= 0) {
      int idx = d.kids[d.hover];
      CloseMenus();
      Activate(idx);
    }
  }
}

}  // namespace

namespace {

// ---------------------------------------------------------------------------
// Application icons (.icns PNG elements, or drawn procedurally)
// ---------------------------------------------------------------------------
cairo_status_t ReadMem(void* closure, unsigned char* out, unsigned int length) {
  auto* c = static_cast<const uint8_t**>(closure);
  memcpy(out, c[0], length);
  c[0] += length;
  return c[0] <= c[1] ? CAIRO_STATUS_SUCCESS : CAIRO_STATUS_READ_ERROR;
}

cairo_surface_t* ScaleTo(cairo_surface_t* src, int size) {
  cairo_surface_t* cur = cairo_surface_reference(src);
  int cw = cairo_image_surface_get_width(cur);
  while (cw / 2 >= size) {
    int nw = cw / 2;
    int nh = cairo_image_surface_get_height(cur) / 2;
    cairo_surface_t* half = NewImage(nw, nh);
    cairo_t* cr = cairo_create(half);
    cairo_scale(cr, 0.5, 0.5);
    cairo_set_source_surface(cr, cur, 0, 0);
    cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
    cairo_paint(cr);
    cairo_destroy(cr);
    cairo_surface_destroy(cur);
    cur = half;
    cw = nw;
  }
  cairo_surface_t* out = NewImage(size, size);
  cairo_t* cr = cairo_create(out);
  double s = static_cast<double>(size) / cw;
  cairo_scale(cr, s, s);
  cairo_set_source_surface(cr, cur, 0, 0);
  cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
  cairo_paint(cr);
  cairo_destroy(cr);
  cairo_surface_destroy(cur);
  return out;
}

cairo_surface_t* LoadIcns(const char* path, int size) {
  FILE* fp = fopen(path, "rb");
  if (!fp) return nullptr;
  fseek(fp, 0, SEEK_END);
  long sz = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (sz < 16 || sz > 16 * 1024 * 1024) {
    fclose(fp);
    return nullptr;
  }
  uint8_t* buf = static_cast<uint8_t*>(malloc(static_cast<size_t>(sz)));
  size_t n = buf ? fread(buf, 1, static_cast<size_t>(sz), fp) : 0;
  fclose(fp);
  cairo_surface_t* best = nullptr;
  int best_w = 0;
  static const uint8_t kPng[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
  if (buf && n > 8 && memcmp(buf, "icns", 4) == 0) {
    size_t pos = 8;
    while (pos + 8 <= n) {
      uint32_t elen = (uint32_t(buf[pos + 4]) << 24) | (uint32_t(buf[pos + 5]) << 16) |
                      (uint32_t(buf[pos + 6]) << 8) | buf[pos + 7];
      if (elen < 8 || pos + elen > n) break;
      const uint8_t* p = buf + pos + 8;
      if (elen - 8 > 8 && memcmp(p, kPng, 8) == 0) {
        const uint8_t* ctx[2] = {p, p + (elen - 8)};
        cairo_surface_t* s = cairo_image_surface_create_from_png_stream(ReadMem, ctx);
        int w = cairo_surface_status(s) == CAIRO_STATUS_SUCCESS
                    ? cairo_image_surface_get_width(s) : 0;
        bool better = w > 0 && ((best_w < size * 2 && w > best_w) ||
                                (w >= size * 2 && w < best_w));
        if (better) {
          if (best) cairo_surface_destroy(best);
          best = s;
          best_w = w;
        } else {
          cairo_surface_destroy(s);
        }
      }
      pos += elen;
    }
  }
  free(buf);
  if (!best) return nullptr;
  cairo_surface_t* out = ScaleTo(best, size);
  cairo_surface_destroy(best);
  return out;
}

// Finds the bundle's icon file (CFBundleIconFile, or any .icns in Resources).
bool FindBundleIcon(const char* bundle, char* out, size_t cap) {
  char path[600];
  snprintf(path, sizeof(path), "%s/Contents/Info.plist", bundle);
  FILE* fp = fopen(path, "rb");
  if (fp) {
    char buf[16384];
    size_t n = fread(buf, 1, sizeof(buf) - 1, fp);
    fclose(fp);
    buf[n] = '\0';
    const char* k = strstr(buf, "<key>CFBundleIconFile</key>");
    if (k) {
      const char* s = strstr(k, "<string>");
      const char* e = s ? strstr(s, "</string>") : nullptr;
      if (s && e) {
        s += 8;
        char name[256];
        snprintf(name, sizeof(name), "%.*s", static_cast<int>(e - s), s);
        snprintf(out, cap, "%s/Contents/Resources/%s%s", bundle, name,
                 strstr(name, ".icns") ? "" : ".icns");
        if (access(out, R_OK) == 0) return true;
      }
    }
  }
  snprintf(path, sizeof(path), "%s/Contents/Resources", bundle);
  DIR* dir = opendir(path);
  if (!dir) return false;
  bool found = false;
  while (dirent* de = readdir(dir)) {
    size_t l = strlen(de->d_name);
    if (l > 5 && strcmp(de->d_name + l - 5, ".icns") == 0) {
      snprintf(out, cap, "%s/%s", path, de->d_name);
      found = true;
      if (strstr(de->d_name, "AppIcon") || strstr(de->d_name, "Icon")) break;
    }
  }
  closedir(dir);
  return found;
}

void Squircle(cairo_t* cr, double r0, double g0, double b0, double r1, double g1, double b1) {
  RoundRect(cr, 10, 11.5, 80, 80, 19);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
  cairo_fill(cr);
  RoundRect(cr, 10, 10, 80, 80, 19);
  cairo_pattern_t* g = cairo_pattern_create_linear(0, 10, 0, 90);
  cairo_pattern_add_color_stop_rgb(g, 0, r0, g0, b0);
  cairo_pattern_add_color_stop_rgb(g, 1, r1, g1, b1);
  cairo_set_source(cr, g);
  cairo_fill_preserve(cr);
  cairo_pattern_destroy(g);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.12);
  cairo_set_line_width(cr, 0.8);
  cairo_stroke(cr);
}

// Draws a procedural icon in a 100x100 design space.
cairo_surface_t* MakeIcon(const char* name, int size) {
  cairo_surface_t* img = NewImage(size, size);
  cairo_t* cr = cairo_create(img);
  cairo_scale(cr, size / 100.0, size / 100.0);
  if (!strcmp(name, "Finder")) {
    Squircle(cr, 0.40, 0.75, 1.0, 0.12, 0.50, 0.95);
    cairo_save(cr);
    RoundRect(cr, 10, 10, 80, 80, 19);
    cairo_clip(cr);
    cairo_move_to(cr, 10, 10);
    cairo_line_to(cr, 54, 10);
    cairo_line_to(cr, 47, 50);
    cairo_line_to(cr, 52, 50);
    cairo_line_to(cr, 49, 90);
    cairo_line_to(cr, 10, 90);
    cairo_close_path(cr);
    cairo_pattern_t* g = cairo_pattern_create_linear(0, 10, 0, 90);
    cairo_pattern_add_color_stop_rgb(g, 0, 0.12, 0.47, 0.96);
    cairo_pattern_add_color_stop_rgb(g, 1, 0.05, 0.30, 0.85);
    cairo_set_source(cr, g);
    cairo_fill(cr);
    cairo_pattern_destroy(g);
    cairo_restore(cr);
    cairo_set_source_rgba(cr, 0.05, 0.10, 0.25, 0.9);
    RoundRect(cr, 30, 30, 5, 14, 2.5);
    cairo_fill(cr);
    RoundRect(cr, 63, 30, 5, 14, 2.5);
    cairo_fill(cr);
    cairo_set_line_width(cr, 3.2);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_move_to(cr, 28, 64);
    cairo_curve_to(cr, 40, 76, 60, 76, 72, 64);
    cairo_stroke(cr);
  } else if (!strcmp(name, "Trash")) {
    cairo_move_to(cr, 24, 26);
    cairo_line_to(cr, 76, 26);
    cairo_line_to(cr, 70, 90);
    cairo_line_to(cr, 30, 90);
    cairo_close_path(cr);
    cairo_pattern_t* g = cairo_pattern_create_linear(24, 0, 76, 0);
    cairo_pattern_add_color_stop_rgba(g, 0, 0.78, 0.80, 0.84, 0.85);
    cairo_pattern_add_color_stop_rgba(g, 0.5, 0.96, 0.97, 0.98, 0.85);
    cairo_pattern_add_color_stop_rgba(g, 1, 0.74, 0.76, 0.80, 0.85);
    cairo_set_source(cr, g);
    cairo_fill_preserve(cr);
    cairo_pattern_destroy(g);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.3);
    cairo_set_line_width(cr, 1);
    cairo_stroke(cr);
    for (int i = 0; i < 5; ++i) {
      double x = 34 + i * 8;
      cairo_move_to(cr, x, 32);
      cairo_line_to(cr, x - (x - 50) * 0.12, 85);
    }
    cairo_set_source_rgba(cr, 0, 0, 0, 0.16);
    cairo_set_line_width(cr, 1.6);
    cairo_stroke(cr);
    RoundRect(cr, 20, 19, 60, 8, 3);
    cairo_set_source_rgba(cr, 0.88, 0.89, 0.91, 0.95);
    cairo_fill_preserve(cr);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.3);
    cairo_set_line_width(cr, 1);
    cairo_stroke(cr);
  } else if (!strcmp(name, "Chromium")) {
    Squircle(cr, 1, 1, 1, 0.90, 0.91, 0.93);
    cairo_pattern_t* g = cairo_pattern_create_radial(44, 40, 4, 50, 50, 30);
    cairo_pattern_add_color_stop_rgb(g, 0, 0.45, 0.70, 1.0);
    cairo_pattern_add_color_stop_rgb(g, 1, 0.10, 0.40, 0.90);
    cairo_arc(cr, 50, 50, 28, 0, 2 * kPi);
    cairo_set_source(cr, g);
    cairo_fill(cr);
    cairo_pattern_destroy(g);
    cairo_set_source_rgba(cr, 1, 1, 1, 0.85);
    cairo_set_line_width(cr, 1.8);
    cairo_arc(cr, 50, 50, 28, 0, 2 * kPi);
    cairo_stroke(cr);
    cairo_save(cr);
    cairo_translate(cr, 50, 50);
    cairo_scale(cr, 0.45, 1);
    cairo_arc(cr, 0, 0, 28, 0, 2 * kPi);
    cairo_restore(cr);
    cairo_stroke(cr);
    cairo_move_to(cr, 22, 50);
    cairo_line_to(cr, 78, 50);
    cairo_move_to(cr, 27, 36);
    cairo_line_to(cr, 73, 36);
    cairo_move_to(cr, 27, 64);
    cairo_line_to(cr, 73, 64);
    cairo_move_to(cr, 50, 22);
    cairo_line_to(cr, 50, 78);
    cairo_stroke(cr);
  } else if (!strcmp(name, "Stickies")) {
    Squircle(cr, 1.0, 0.86, 0.30, 0.98, 0.72, 0.10);
    cairo_move_to(cr, 26, 24);
    cairo_line_to(cr, 74, 24);
    cairo_line_to(cr, 74, 62);
    cairo_line_to(cr, 60, 76);
    cairo_line_to(cr, 26, 76);
    cairo_close_path(cr);
    cairo_set_source_rgb(cr, 1.0, 0.97, 0.62);
    cairo_fill(cr);
    cairo_move_to(cr, 74, 62);
    cairo_line_to(cr, 60, 62);
    cairo_line_to(cr, 60, 76);
    cairo_close_path(cr);
    cairo_set_source_rgb(cr, 0.93, 0.84, 0.40);
    cairo_fill(cr);
    cairo_set_source_rgba(cr, 0.55, 0.45, 0.1, 0.5);
    cairo_set_line_width(cr, 2);
    for (int i = 0; i < 4; ++i) {
      cairo_move_to(cr, 32, 35 + i * 9);
      cairo_line_to(cr, i == 3 ? 54 : 68, 35 + i * 9);
    }
    cairo_stroke(cr);
  } else if (!strcmp(name, "Digital Color Meter")) {
    Squircle(cr, 0.32, 0.33, 0.36, 0.14, 0.14, 0.16);
    cairo_set_operator(cr, CAIRO_OPERATOR_ADD);
    const double cols[3][3] = {{0.95, 0.15, 0.15}, {0.15, 0.85, 0.2}, {0.2, 0.35, 1.0}};
    const double pos[3][2] = {{50, 40}, {40, 58}, {60, 58}};
    for (int i = 0; i < 3; ++i) {
      cairo_arc(cr, pos[i][0], pos[i][1], 16, 0, 2 * kPi);
      cairo_set_source_rgb(cr, cols[i][0], cols[i][1], cols[i][2]);
      cairo_fill(cr);
    }
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  } else if (!strcmp(name, "Image Capture")) {
    Squircle(cr, 0.85, 0.86, 0.88, 0.62, 0.63, 0.67);
    RoundRect(cr, 24, 36, 52, 34, 6);
    cairo_set_source_rgb(cr, 0.18, 0.19, 0.22);
    cairo_fill(cr);
    RoundRect(cr, 38, 30, 16, 8, 2);
    cairo_fill(cr);
    cairo_arc(cr, 50, 53, 12, 0, 2 * kPi);
    cairo_set_source_rgb(cr, 0.55, 0.6, 0.7);
    cairo_fill(cr);
    cairo_arc(cr, 50, 53, 7, 0, 2 * kPi);
    cairo_set_source_rgb(cr, 0.08, 0.10, 0.18);
    cairo_fill(cr);
    cairo_arc(cr, 47, 50, 2, 0, 2 * kPi);
    cairo_set_source_rgba(cr, 1, 1, 1, 0.8);
    cairo_fill(cr);
  } else if (!strcmp(name, "WidgetGallery")) {
    Squircle(cr, 0.98, 0.98, 1.0, 0.86, 0.87, 0.90);
    const double cols[4][3] = {{1.0, 0.37, 0.34}, {1.0, 0.74, 0.18},
                               {0.16, 0.78, 0.25}, {0.04, 0.48, 1.0}};
    for (int i = 0; i < 4; ++i) {
      RoundRect(cr, 24 + (i % 2) * 28, 24 + (i / 2) * 28, 24, 24, 6);
      cairo_set_source_rgb(cr, cols[i][0], cols[i][1], cols[i][2]);
      cairo_fill(cr);
    }
  } else if (strstr(name, "Zoom")) {
    Squircle(cr, 0.30, 0.62, 1.0, 0.05, 0.42, 0.95);
    RoundRect(cr, 24, 36, 38, 28, 7);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_fill(cr);
    cairo_move_to(cr, 64, 44);
    cairo_line_to(cr, 77, 36);
    cairo_line_to(cr, 77, 64);
    cairo_line_to(cr, 64, 56);
    cairo_close_path(cr);
    cairo_fill(cr);
  } else if (!strcmp(name, "AppleScript Utility")) {
    Squircle(cr, 0.80, 0.81, 0.84, 0.56, 0.57, 0.62);
    RoundRect(cr, 30, 22, 40, 56, 4);
    cairo_set_source_rgb(cr, 0.99, 0.98, 0.94);
    cairo_fill(cr);
    cairo_set_source_rgba(cr, 0.25, 0.30, 0.55, 0.7);
    cairo_set_line_width(cr, 2.2);
    for (int i = 0; i < 5; ++i) {
      cairo_move_to(cr, 36 + (i % 2) * 5, 32 + i * 9);
      cairo_line_to(cr, i == 4 ? 52 : 64, 32 + i * 9);
    }
    cairo_stroke(cr);
  } else if (!strcmp(name, "Directory Utility")) {
    Squircle(cr, 0.45, 0.47, 0.52, 0.22, 0.23, 0.27);
    const double nodes[4][2] = {{50, 30}, {30, 64}, {70, 64}, {50, 52}};
    cairo_set_source_rgba(cr, 1, 1, 1, 0.8);
    cairo_set_line_width(cr, 3);
    for (int i = 0; i < 3; ++i) {
      cairo_move_to(cr, nodes[3][0], nodes[3][1]);
      cairo_line_to(cr, nodes[i][0], nodes[i][1]);
    }
    cairo_stroke(cr);
    for (const auto& nd : nodes) {
      cairo_arc(cr, nd[0], nd[1], 7, 0, 2 * kPi);
      cairo_set_source_rgb(cr, 0.35, 0.70, 1.0);
      cairo_fill_preserve(cr);
      cairo_set_source_rgb(cr, 1, 1, 1);
      cairo_set_line_width(cr, 2);
      cairo_stroke(cr);
    }
  } else if (!strcmp(name, "Ticket Viewer")) {
    Squircle(cr, 1.0, 0.72, 0.36, 0.93, 0.47, 0.16);
    cairo_move_to(cr, 22, 36);
    cairo_line_to(cr, 78, 36);
    cairo_arc_negative(cr, 78, 50, 6, -kPi / 2, kPi / 2);
    cairo_line_to(cr, 78, 64);
    cairo_line_to(cr, 22, 64);
    cairo_arc_negative(cr, 22, 50, 6, kPi / 2, -kPi / 2);
    cairo_close_path(cr);
    cairo_set_source_rgb(cr, 1, 0.97, 0.90);
    cairo_fill(cr);
    cairo_set_source_rgba(cr, 0.75, 0.35, 0.1, 0.8);
    cairo_set_line_width(cr, 1.5);
    static const double kDash[2] = {3, 3};
    cairo_set_dash(cr, kDash, 2, 0);
    cairo_move_to(cr, 62, 38);
    cairo_line_to(cr, 62, 62);
    cairo_stroke(cr);
    cairo_set_dash(cr, nullptr, 0, 0);
  } else if (!strcmp(name, "Bluetooth File Exchange")) {
    Squircle(cr, 0.30, 0.62, 1.0, 0.02, 0.40, 0.92);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_set_line_width(cr, 5);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_move_to(cr, 36, 38);
    cairo_line_to(cr, 62, 60);
    cairo_line_to(cr, 50, 72);
    cairo_line_to(cr, 50, 28);
    cairo_line_to(cr, 62, 40);
    cairo_line_to(cr, 36, 62);
    cairo_stroke(cr);
  } else if (!strcmp(name, "Expansion Slot Utility")) {
    Squircle(cr, 0.40, 0.80, 0.50, 0.12, 0.55, 0.30);
    RoundRect(cr, 22, 32, 56, 32, 3);
    cairo_set_source_rgb(cr, 0.10, 0.35, 0.18);
    cairo_fill(cr);
    for (int i = 0; i < 9; ++i) {
      cairo_rectangle(cr, 26 + i * 6, 64, 3, 7);
    }
    cairo_set_source_rgb(cr, 0.95, 0.80, 0.30);
    cairo_fill(cr);
    RoundRect(cr, 30, 38, 18, 18, 2);
    cairo_set_source_rgb(cr, 0.85, 0.86, 0.88);
    cairo_fill(cr);
  } else if (!strcmp(name, "Folder Actions Setup")) {
    Squircle(cr, 0.55, 0.78, 1.0, 0.25, 0.55, 0.95);
    cairo_move_to(cr, 22, 34);
    cairo_line_to(cr, 42, 34);
    cairo_line_to(cr, 47, 39);
    cairo_line_to(cr, 78, 39);
    cairo_line_to(cr, 78, 72);
    cairo_line_to(cr, 22, 72);
    cairo_close_path(cr);
    cairo_set_source_rgb(cr, 0.80, 0.92, 1.0);
    cairo_fill(cr);
    cairo_arc(cr, 50, 56, 9, 0, 2 * kPi);
    cairo_set_source_rgb(cr, 0.30, 0.50, 0.80);
    cairo_set_line_width(cr, 4);
    cairo_stroke(cr);
    for (int i = 0; i < 8; ++i) {
      double a = i * kPi / 4;
      cairo_move_to(cr, 50 + cos(a) * 11, 56 + sin(a) * 11);
      cairo_line_to(cr, 50 + cos(a) * 15, 56 + sin(a) * 15);
    }
    cairo_stroke(cr);
  } else if (strstr(name, "Command Line") || !strcmp(name, "System Info") ||
             !strcmp(name, "HelloWorld")) {
    Squircle(cr, 0.25, 0.26, 0.30, 0.08, 0.08, 0.10);
    SetFont(cr, 26, true);
    cairo_set_source_rgb(cr, 0.95, 0.95, 0.95);
    Text(cr, 26, 60, ">_");
  } else if (strstr(name, "Sparkle")) {
    Squircle(cr, 0.98, 0.98, 1.0, 0.86, 0.87, 0.90);
    cairo_move_to(cr, 50, 20);
    cairo_curve_to(cr, 53, 44, 56, 47, 80, 50);
    cairo_curve_to(cr, 56, 53, 53, 56, 50, 80);
    cairo_curve_to(cr, 47, 56, 44, 53, 20, 50);
    cairo_curve_to(cr, 44, 47, 47, 44, 50, 20);
    cairo_set_source_rgb(cr, 0.98, 0.70, 0.10);
    cairo_fill(cr);
  } else {
    unsigned h = 5381;
    for (const char* p = name; *p; ++p) h = h * 33 + static_cast<unsigned char>(*p);
    static const double kPalette[6][6] = {
        {0.40, 0.62, 1.0, 0.10, 0.35, 0.90}, {0.55, 0.90, 0.55, 0.15, 0.62, 0.30},
        {1.0, 0.65, 0.35, 0.92, 0.38, 0.15}, {0.80, 0.55, 1.0, 0.48, 0.25, 0.86},
        {0.55, 0.58, 0.64, 0.30, 0.32, 0.38}, {0.40, 0.85, 0.95, 0.08, 0.55, 0.75}};
    const double* c = kPalette[h % 6];
    Squircle(cr, c[0], c[1], c[2], c[3], c[4], c[5]);
    char glyph[8] = {name[0] ? name[0] : '?', 0};
    SetFont(cr, 44, true);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.18);
    TextCentered(cr, 50, 67.5, glyph);
    cairo_set_source_rgb(cr, 1, 1, 1);
    TextCentered(cr, 50, 66, glyph);
  }
  cairo_destroy(cr);
  return img;
}

cairo_surface_t* IconForBundle(const char* bundle, const char* name, int size) {
  char icns[700];
  if (bundle && bundle[0] == '/' && FindBundleIcon(bundle, icns, sizeof(icns))) {
    cairo_surface_t* s = LoadIcns(icns, size);
    if (s) return s;
  }
  return MakeIcon(name, size);
}

void BundleDisplayName(const char* path, char* out, size_t cap) {
  const char* base = strrchr(path, '/');
  base = base ? base + 1 : path;
  snprintf(out, cap, "%s", base);
  char* dot = strstr(out, ".app");
  if (dot) *dot = '\0';
}

void Launch(const char* bundle_or_cmd) {
  pid_t pid = fork();
  if (pid == 0) {
    setsid();
    if (bundle_or_cmd[0] == '/') {
      execl("/usr/bin/open", "open", bundle_or_cmd, static_cast<char*>(nullptr));
    } else {
      execl("/bin/sh", "sh", "-c", bundle_or_cmd, static_cast<char*>(nullptr));
    }
    _exit(127);
  }
}

// ---------------------------------------------------------------------------
// Dock
// ---------------------------------------------------------------------------
enum DockKind { kDockApp, kDockFinder, kDockTrash, kDockCommand, kDockSeparator };

struct DockItem {
  char name[96];
  char path[512];
  int kind;
  cairo_surface_t* icon;
  bool running;
  Window win;
  double bounce_start;
  double x;
};

DockItem g_dock[24];
int g_ndock = 0;
Window g_dock_win = 0;
Window g_label_win = 0;
cairo_surface_t* g_label_img = nullptr;
int g_dock_x = 0, g_dock_y = 0, g_dock_w = 0, g_dock_h = 0;
int g_dock_hover = -1, g_dock_pressed = -1;
cairo_surface_t* g_dock_bg = nullptr;

void AddDockItem(const char* name, const char* path, int kind) {
  if (g_ndock >= 24) return;
  DockItem& d = g_dock[g_ndock++];
  memset(&d, 0, sizeof(d));
  snprintf(d.name, sizeof(d.name), "%s", name);
  snprintf(d.path, sizeof(d.path), "%s", path);
  d.kind = kind;
  if (kind == kDockApp) {
    d.icon = IconForBundle(path, name, kIcon);
  } else if (kind != kDockSeparator) {
    d.icon = MakeIcon(name, kIcon);
  }
}

void SetupDockItems() {
  AddDockItem("Finder", "", kDockFinder);
  static const char* kDefaults[] = {
      "/Applications/FastDMG.app",          "/Applications/WidgetGallery.app",
      "/Applications/System Info.app",      "/Applications/ProgressBar.app",
      "/Applications/Stickies.app",         "/Applications/Digital Color Meter.app",
      "/Applications/Image Capture.app",    "/Applications/AppleScript Utility.app",
      "/Applications/Directory Utility.app", "/Applications/ZoomUninstaller.app",
  };
  char line[512];
  FILE* fp = fopen("/etc/darling/dock-apps", "r");
  if (fp) {
    while (fgets(line, sizeof(line), fp)) {
      line[strcspn(line, "\r\n")] = '\0';
      if (!line[0] || line[0] == '#') continue;
      char name[96];
      BundleDisplayName(line, name, sizeof(name));
      if (access(line, R_OK) == 0) AddDockItem(name, line, kDockApp);
    }
    fclose(fp);
  } else {
    for (const char* p : kDefaults) {
      char name[96];
      BundleDisplayName(p, name, sizeof(name));
      if (access(p, R_OK) == 0) AddDockItem(name, p, kDockApp);
    }
  }
  if (access("/bin/chromium", X_OK) == 0) {
    AddDockItem("Chromium",
                "/bin/chromium file:///usr/share/chromium/test.html >/dev/console 2>&1",
                kDockCommand);
  }
  AddDockItem("", "", kDockSeparator);
  AddDockItem("Trash", "", kDockTrash);
}

void LayoutDock() {
  double w = kShelfPad;
  for (int i = 0; i < g_ndock; ++i) {
    g_dock[i].x = w;
    w += g_dock[i].kind == kDockSeparator ? 1 + kIconGap : kIcon + kIconGap;
  }
  w += kShelfPad - kIconGap;
  g_dock_w = static_cast<int>(w);
  g_dock_h = kShelfH + kBounceH;
  g_dock_x = (g_w - g_dock_w) / 2;
  g_dock_y = g_h - kDockBottom - g_dock_h;
}

double BounceOffset(const DockItem& d, double now) {
  if (d.bounce_start <= 0) return 0;
  double t = now - d.bounce_start;
  return fabs(sin(kPi * t / 0.55)) * (kBounceH - 4);
}

bool DockAnimating() {
  for (int i = 0; i < g_ndock; ++i) {
    if (g_dock[i].bounce_start > 0) return true;
  }
  return false;
}

void ShapeDock(double now) {
  XRectangle rects[200];
  int n = RoundedRects(rects, 160, 0, kBounceH, g_dock_w, kShelfH, 18);
  for (int i = 0; i < g_ndock && n < 199; ++i) {
    double off = BounceOffset(g_dock[i], now);
    if (off > 0.5) {
      rects[n++] = {static_cast<short>(g_dock[i].x), static_cast<short>(kBounceH + 6 - off),
                    static_cast<unsigned short>(kIcon), static_cast<unsigned short>(kIcon)};
    }
  }
  XShapeCombineRectangles(g_dpy, g_dock_win, ShapeBounding, 0, 0, rects, n, ShapeSet,
                          Unsorted);
}

void DrawDock() {
  if (!g_dock_win) return;
  double now = NowSec();
  if (!g_dock_bg) g_dock_bg = BlurredWallpaper(g_dock_x, g_dock_y, g_dock_w, g_dock_h, 12);
  cairo_surface_t* img = NewImage(g_dock_w, g_dock_h);
  cairo_t* cr = cairo_create(img);
  cairo_set_source_surface(cr, g_wall, -g_dock_x, -g_dock_y);
  cairo_paint(cr);
  RoundRect(cr, 0, kBounceH, g_dock_w, kShelfH, 18);
  cairo_save(cr);
  cairo_clip_preserve(cr);
  cairo_set_source_surface(cr, g_dock_bg, 0, 0);
  cairo_fill_preserve(cr);
  cairo_set_source_rgba(cr, 1, 1, 1, 0.30);
  cairo_fill(cr);
  cairo_restore(cr);
  RoundRect(cr, 1, kBounceH + 1, g_dock_w - 2, kShelfH - 2, 17);
  cairo_set_source_rgba(cr, 1, 1, 1, 0.45);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  RoundRect(cr, 0.5, kBounceH + 0.5, g_dock_w - 1, kShelfH - 1, 17.5);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.18);
  cairo_stroke(cr);
  for (int i = 0; i < g_ndock; ++i) {
    const DockItem& d = g_dock[i];
    if (d.kind == kDockSeparator) {
      cairo_rectangle(cr, d.x, kBounceH + 10, 1, kShelfH - 20);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
      cairo_fill(cr);
      continue;
    }
    if (!d.icon) continue;
    double iy = kBounceH + 6 - BounceOffset(d, now);
    cairo_set_source_surface(cr, d.icon, d.x, iy);
    cairo_paint(cr);
    if (i == g_dock_pressed) {
      cairo_set_source_rgba(cr, 0, 0, 0, 0.35);
      cairo_mask_surface(cr, d.icon, d.x, iy);
    }
    if (d.running || d.kind == kDockFinder) {
      cairo_arc(cr, d.x + kIcon / 2.0, kBounceH + kShelfH - 5, 2.0, 0, 2 * kPi);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.62);
      cairo_fill(cr);
    }
  }
  cairo_destroy(cr);
  ShapeDock(now);
  Blit(g_dock_win, img);
  cairo_surface_destroy(img);
  XFlush(g_dpy);
}

void ReportDockLayout() {
  for (int i = 0; i < g_ndock; ++i) {
    if (g_dock[i].kind == kDockSeparator) continue;
    printf("DARLING_DOCK_ITEM:%s:%d:%d\n", g_dock[i].name,
           static_cast<int>(g_dock_x + g_dock[i].x + kIcon / 2),
           g_dock_y + kBounceH + 6 + kIcon / 2);
  }
  fflush(stdout);
}

void HideDockLabel() {
  if (g_label_win) {
    XDestroyWindow(g_dpy, g_label_win);
    g_label_win = 0;
  }
  if (g_label_img) {
    cairo_surface_destroy(g_label_img);
    g_label_img = nullptr;
  }
}

void ShowDockLabel(int i) {
  HideDockLabel();
  if (i < 0 || g_dock[i].kind == kDockSeparator) return;
  cairo_surface_t* tmp = NewImage(4, 4);
  cairo_t* cr = cairo_create(tmp);
  SetFont(cr, 13, false);
  int w = static_cast<int>(TextW(cr, g_dock[i].name) + 24);
  cairo_destroy(cr);
  cairo_surface_destroy(tmp);
  int h = 26;
  int x = static_cast<int>(g_dock_x + g_dock[i].x + kIcon / 2.0 - w / 2.0);
  int y = g_dock_y + kBounceH - h - 8;
  XSetWindowAttributes attrs;
  memset(&attrs, 0, sizeof(attrs));
  attrs.override_redirect = True;
  attrs.event_mask = ExposureMask;
  g_label_win = XCreateWindow(g_dpy, g_root, x, y, static_cast<unsigned>(w),
                              static_cast<unsigned>(h), 0, CopyFromParent, InputOutput,
                              CopyFromParent, CWOverrideRedirect | CWEventMask, &attrs);
  ShapeRounded(g_label_win, w, h, 7);
  XMapRaised(g_dpy, g_label_win);
  cairo_surface_t* img = NewImage(w, h);
  cr = cairo_create(img);
  cairo_surface_t* bg = BlurredWallpaper(x, y, w, h, 8);
  cairo_set_source_surface(cr, bg, 0, 0);
  cairo_paint(cr);
  cairo_surface_destroy(bg);
  RoundRect(cr, 0, 0, w, h, 7);
  cairo_set_source_rgba(cr, 0.96, 0.96, 0.97, 0.88);
  cairo_fill(cr);
  RoundRect(cr, 0.5, 0.5, w - 1, h - 1, 6.5);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.2);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  SetFont(cr, 13, false);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.85);
  TextCentered(cr, w / 2.0, 17.5, g_dock[i].name);
  cairo_destroy(cr);
  g_label_img = img;
  Blit(g_label_win, img);
}

int DockItemAt(int x, int y) {
  if (y < kBounceH || y >= g_dock_h) return -1;
  for (int i = 0; i < g_ndock; ++i) {
    if (g_dock[i].kind == kDockSeparator) continue;
    if (x >= g_dock[i].x - kIconGap / 2.0 && x < g_dock[i].x + kIcon + kIconGap / 2.0) return i;
  }
  return -1;
}

void OpenFinderWindow();
void OpenAboutWindow();

// ---------------------------------------------------------------------------
// Top-level windows, running applications and the active window. There is
// no window manager: the shell watches the root window's children itself.
// ---------------------------------------------------------------------------
struct TopLevel {
  Window w;
  bool mapped;
  bool chromium;
  bool has_menu;
  char bundle[512];
};

TopLevel g_tops[160];
int g_ntops = 0;
Window g_finder_win = 0, g_about_win = 0;
Window g_finder_reported = 0, g_about_reported = 0;

int DropLevelOf(Window w);

bool IsOwnWindow(Window w) {
  return w == g_bar || w == g_dock_win || w == g_label_win || w == g_finder_win ||
         w == g_about_win || DropLevelOf(w) >= 0;
}

bool IsChromiumWindow(Window w) {
  XClassHint ch;
  memset(&ch, 0, sizeof(ch));
  bool r = false;
  if (XGetClassHint(g_dpy, w, &ch)) {
    r = (ch.res_name && (strstr(ch.res_name, "hromium") || strstr(ch.res_name, "headless"))) ||
        (ch.res_class && (strstr(ch.res_class, "hromium") || strstr(ch.res_class, "eadless")));
    if (ch.res_name) XFree(ch.res_name);
    if (ch.res_class) XFree(ch.res_class);
  }
  return r;
}

TopLevel* FindTop(Window w) {
  for (int i = 0; i < g_ntops; ++i) {
    if (g_tops[i].w == w) return &g_tops[i];
  }
  return nullptr;
}

void ReadTopInfo(TopLevel& t) {
  unsigned long len = 0;
  char* bp = reinterpret_cast<char*>(GetProp(t.w, A("_DARLING_BUNDLE_PATH"), AnyPropertyType, &len));
  t.bundle[0] = '\0';
  if (bp) {
    snprintf(t.bundle, sizeof(t.bundle), "%.*s", static_cast<int>(len), bp);
    XFree(bp);
  }
  unsigned char* menu = GetProp(t.w, A("_DARLING_APP_MENU"), AnyPropertyType, &len);
  t.has_menu = menu != nullptr;
  if (menu) XFree(menu);
  t.chromium = !t.bundle[0] && IsChromiumWindow(t.w);
}

TopLevel* AddTop(Window w) {
  if (IsOwnWindow(w)) return nullptr;
  TopLevel* t = FindTop(w);
  if (t) return t;
  if (g_ntops >= 160) return nullptr;
  t = &g_tops[g_ntops++];
  memset(t, 0, sizeof(*t));
  t->w = w;
  XSelectInput(g_dpy, w, PropertyChangeMask);
  return t;
}

void RemoveTop(Window w) {
  for (int i = 0; i < g_ntops; ++i) {
    if (g_tops[i].w == w) {
      g_tops[i] = g_tops[--g_ntops];
      return;
    }
  }
}

void ScanTopLevels() {
  Window root_ret = 0, parent_ret = 0;
  Window* kids = nullptr;
  unsigned int n = 0;
  if (!XQueryTree(g_dpy, g_root, &root_ret, &parent_ret, &kids, &n)) return;
  for (unsigned int i = 0; i < n; ++i) {
    TopLevel* t = AddTop(kids[i]);
    if (!t) continue;
    XWindowAttributes wa;
    t->mapped = XGetWindowAttributes(g_dpy, kids[i], &wa) && wa.map_state == IsViewable;
    ReadTopInfo(*t);
  }
  if (kids) XFree(kids);
}

// The Dock and the menu bar float above application windows.
void KeepShellOnTop() {
  if (g_dock_win) XRaiseWindow(g_dpy, g_dock_win);
  if (g_bar) XRaiseWindow(g_dpy, g_bar);
  for (int l = 0; l < g_ndrops; ++l) XRaiseWindow(g_dpy, g_drops[l].win);
  if (g_label_win) XRaiseWindow(g_dpy, g_label_win);
}

void UpdateRunning() {
  for (int i = 0; i < g_ndock; ++i) {
    g_dock[i].running = false;
    g_dock[i].win = 0;
  }
  for (int k = 0; k < g_ntops; ++k) {
    const TopLevel& t = g_tops[k];
    for (int i = 0; i < g_ndock; ++i) {
      DockItem& d = g_dock[i];
      bool match = (t.bundle[0] && d.kind == kDockApp && strcmp(d.path, t.bundle) == 0) ||
                   (t.chromium && t.mapped && d.kind == kDockCommand);
      if (match) {
        d.running = true;
        if (!d.win || t.mapped) d.win = t.w;
        if (t.mapped) d.bounce_start = 0;
      }
    }
  }
  double now = NowSec();
  for (int i = 0; i < g_ndock; ++i) {
    if (g_dock[i].bounce_start > 0 && now - g_dock[i].bounce_start > 6.0) {
      g_dock[i].bounce_start = 0;
    }
  }
}

void SendActivateApp(Window w) {
  XEvent ev;
  memset(&ev, 0, sizeof(ev));
  ev.xclient.type = ClientMessage;
  ev.xclient.window = w;
  ev.xclient.message_type = A("_DARLING_ACTIVATE_APP");
  ev.xclient.format = 32;
  XSendEvent(g_dpy, w, False, NoEventMask, &ev);
  XFlush(g_dpy);
}

void DockClick(int i) {
  DockItem& d = g_dock[i];
  printf("DARLING_DOCK_CLICK:%s\n", d.name);
  fflush(stdout);
  if (d.kind == kDockFinder) {
    OpenFinderWindow();
  } else if (d.kind == kDockTrash) {
    return;
  } else if (d.running && d.win) {
    TopLevel* t = FindTop(d.win);
    if (t && t->bundle[0]) {
      SendActivateApp(d.win);
    } else {
      XMapRaised(g_dpy, d.win);
      SetActiveWindowProperty(d.win);
    }
  } else {
    Launch(d.path);
    d.bounce_start = NowSec();
  }
}

char* g_menu_signature = nullptr;  // menus currently shown in the bar

// Rebuilds the menu bar for the active window; unchanged menus (e.g. a
// second window of the same application) keep any open menu intact.
void RefreshActiveMenus() {
  unsigned long n = 0;
  unsigned char* data = GetProp(g_root, A("_DARLING_ACTIVE_WINDOW"), XA_WINDOW, &n);
  Window w = (data && n > 0) ? reinterpret_cast<Window*>(data)[0] : 0;
  if (data) XFree(data);
  TopLevel* top = w ? FindTop(w) : nullptr;
  if (!top || !top->mapped) w = 0;
  pid_t pid_value = 0;
  char* menu = nullptr;
  char foreign_name[128] = "Application";
  if (w) {
    unsigned long len = 0;
    unsigned char* pid = GetProp(w, A("_NET_WM_PID"), XA_CARDINAL, &len);
    if (pid && len) pid_value = static_cast<pid_t>(reinterpret_cast<unsigned long*>(pid)[0]);
    if (pid) XFree(pid);
    menu = reinterpret_cast<char*>(GetProp(w, A("_DARLING_APP_MENU"), AnyPropertyType, &len));
    if (!menu) {
      XClassHint ch;
      memset(&ch, 0, sizeof(ch));
      if (XGetClassHint(g_dpy, w, &ch)) {
        const char* src = ch.res_class ? ch.res_class : ch.res_name;
        if (src) snprintf(foreign_name, sizeof(foreign_name), "%s", src);
        if (ch.res_name) XFree(ch.res_name);
        if (ch.res_class) XFree(ch.res_class);
      }
      if (IsChromiumWindow(w)) snprintf(foreign_name, sizeof(foreign_name), "Chromium");
      foreign_name[0] = static_cast<char>(toupper(static_cast<unsigned char>(foreign_name[0])));
    }
  }
  const char* sig = !w ? "\x01" "finder" : (menu ? menu : foreign_name);
  bool same = g_menu_signature && strcmp(g_menu_signature, sig) == 0;
  g_active = w;
  g_active_pid = pid_value;
  if (!same) {
    free(g_menu_signature);
    g_menu_signature = strdup(sig);
    if (g_open_entry >= 0) CloseMenus();
    if (!w) {
      BuildFinderMenus();
    } else if (menu) {
      ParseAppMenu(menu);
    } else {
      BuildForeignMenus(foreign_name);
    }
    DrawBar();
    ReportBarLayout();
  }
  if (menu) XFree(menu);
}

// After the active window disappears, the most recently mapped application
// window (or the Finder) becomes active.
void ActivateFallback(Window gone) {
  Window next = 0;
  for (int i = 0; i < g_ntops; ++i) {
    const TopLevel& t = g_tops[i];
    if (t.w != gone && t.mapped && (t.has_menu || t.chromium)) next = t.w;
  }
  SetActiveWindowProperty(next);
}

void HandleTopLevelEvent(XEvent& ev) {
  {
    Window ew = ev.type == MapNotify       ? ev.xmap.window
                : ev.type == UnmapNotify   ? ev.xunmap.window
                : ev.type == DestroyNotify ? ev.xdestroywindow.window
                : ev.type == ConfigureNotify ? ev.xconfigure.window
                                             : 0;
    bool shell_chrome = IsOwnWindow(ew) && ew != g_finder_win && ew != g_about_win;
    if (ew && !shell_chrome) g_desk_dirty = true;
  }
  switch (ev.type) {
    case CreateNotify:
      if (ev.xcreatewindow.parent == g_root && !ev.xcreatewindow.override_redirect) {
        AddTop(ev.xcreatewindow.window);
      }
      break;
    case MapNotify: {
      Window w = ev.xmap.window;
      if (IsOwnWindow(w)) break;
      TopLevel* t = ev.xmap.override_redirect ? nullptr : AddTop(w);
      if (t) {
        t->mapped = true;
        ReadTopInfo(*t);
        // Windows of programs that do not report activation themselves
        // (Chromium, X clients) become active when they appear.
        if (!t->bundle[0] && t->chromium) SetActiveWindowProperty(w);

        UpdateRunning();
        DrawDock();
      }
      KeepShellOnTop();
      break;
    }
    case UnmapNotify:
    case DestroyNotify: {
      Window w = ev.type == UnmapNotify ? ev.xunmap.window : ev.xdestroywindow.window;
      if (IsOwnWindow(w)) break;
      if (ev.type == UnmapNotify) {
        if (TopLevel* t = FindTop(w)) t->mapped = false;
      } else {
        RemoveTop(w);
      }
      if (w == g_active) ActivateFallback(w);
      UpdateRunning();
      DrawDock();
      break;
    }
    case ConfigureNotify:
      if (!IsOwnWindow(ev.xconfigure.window)) KeepShellOnTop();
      break;
    default:
      break;
  }
}

}  // namespace

namespace {

// ---------------------------------------------------------------------------
// Finder ("Applications" window)
// ---------------------------------------------------------------------------
struct FinderEntry {
  char name[128];
  char path[512];
  cairo_surface_t* icon;
};

constexpr int kFinderW = 700, kFinderH = 440, kSidebarW = 172, kToolbarH = 52;
constexpr int kStatusH = 24, kCellW = 104, kCellH = 96;
FinderEntry g_fentries[64];
int g_nfentries = 0;
int g_fsel = -1, g_fscroll = 0;
bool g_finder_active = true, g_finder_hover_lights = false;
double g_flast_click = 0;
int g_flast_index = -1;

void LoadFinderEntries() {
  if (g_nfentries) return;
  DIR* dir = opendir("/Applications");
  if (!dir) return;
  while (dirent* de = readdir(dir)) {
    size_t l = strlen(de->d_name);
    if (l < 5 || strcmp(de->d_name + l - 4, ".app") != 0 || g_nfentries >= 64) continue;
    FinderEntry& e = g_fentries[g_nfentries++];
    snprintf(e.path, sizeof(e.path), "/Applications/%s", de->d_name);
    BundleDisplayName(e.path, e.name, sizeof(e.name));
    e.icon = nullptr;
  }
  closedir(dir);
  for (int i = 0; i < g_nfentries; ++i) {
    for (int j = i + 1; j < g_nfentries; ++j) {
      if (strcasecmp(g_fentries[j].name, g_fentries[i].name) < 0) {
        FinderEntry t = g_fentries[i];
        g_fentries[i] = g_fentries[j];
        g_fentries[j] = t;
      }
    }
  }
  for (int i = 0; i < g_nfentries; ++i) {
    g_fentries[i].icon = IconForBundle(g_fentries[i].path, g_fentries[i].name, 64);
  }
}

int FinderCols() { return (kFinderW - kSidebarW - 16) / kCellW; }

void DrawFolderGlyph(cairo_t* cr, double x, double y) {
  cairo_set_line_width(cr, 1.3);
  cairo_move_to(cr, x, y + 2);
  cairo_line_to(cr, x + 5, y + 2);
  cairo_line_to(cr, x + 6.5, y + 3.5);
  cairo_line_to(cr, x + 14, y + 3.5);
  cairo_line_to(cr, x + 14, y + 12);
  cairo_line_to(cr, x, y + 12);
  cairo_close_path(cr);
  cairo_stroke(cr);
}

void DrawFinder() {
  if (!g_finder_win) return;
  cairo_surface_t* img = NewImage(kFinderW, kFinderH);
  cairo_t* cr = cairo_create(img);
  cairo_set_source_rgb(cr, 1, 1, 1);
  cairo_paint(cr);
  // Sidebar.
  cairo_rectangle(cr, 0, 0, kSidebarW, kFinderH);
  cairo_set_source_rgb(cr, 0.905, 0.905, 0.92);
  cairo_fill(cr);
  cairo_rectangle(cr, kSidebarW - 1, 0, 1, kFinderH);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.12);
  cairo_fill(cr);
  DrawTrafficLights(cr, 20, 20, g_finder_active, g_finder_hover_lights);
  SetFont(cr, 11, true);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.42);
  Text(cr, 18, 66, "Favorites");
  const char* favs[] = {"Applications", "Desktop", "Documents", "Downloads"};
  for (int i = 0; i < 4; ++i) {
    double y = 74 + i * 26;
    if (i == 0) {
      RoundRect(cr, 9, y, kSidebarW - 18, 24, 6);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.09);
      cairo_fill(cr);
    }
    cairo_set_source_rgb(cr, 0.0, 0.45, 0.95);
    DrawFolderGlyph(cr, 20, y + 5);
    SetFont(cr, 13, false);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.85);
    Text(cr, 42, y + 16.5, favs[i]);
  }
  SetFont(cr, 11, true);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.42);
  Text(cr, 18, 196, "Locations");
  DrawHardDiskIcon(cr, 17, 198, 20);
  SetFont(cr, 13, false);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.85);
  Text(cr, 42, 218, "Macintosh HD");

  // Toolbar.
  cairo_rectangle(cr, kSidebarW, 0, kFinderW - kSidebarW, kToolbarH);
  cairo_set_source_rgb(cr, g_finder_active ? 0.97 : 0.985, g_finder_active ? 0.97 : 0.985,
                       g_finder_active ? 0.975 : 0.985);
  cairo_fill(cr);
  cairo_rectangle(cr, kSidebarW, kToolbarH - 1, kFinderW - kSidebarW, 1);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.12);
  cairo_fill(cr);
  cairo_set_source_rgba(cr, 0, 0, 0, g_finder_active ? 0.55 : 0.25);
  cairo_set_line_width(cr, 1.8);
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
  double bx = kSidebarW + 22;
  cairo_move_to(cr, bx + 5, 20);
  cairo_line_to(cr, bx, 26);
  cairo_line_to(cr, bx + 5, 32);
  cairo_stroke(cr);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.22);
  cairo_move_to(cr, bx + 24, 20);
  cairo_line_to(cr, bx + 29, 26);
  cairo_line_to(cr, bx + 24, 32);
  cairo_stroke(cr);
  SetFont(cr, 15, true);
  cairo_set_source_rgba(cr, 0, 0, 0, g_finder_active ? 0.85 : 0.4);
  Text(cr, bx + 48, 31, "Applications");
  // View switcher (icons selected) and search.
  double vx = kFinderW - 150;
  RoundRect(cr, vx, 15, 62, 22, 6);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.06);
  cairo_fill(cr);
  RoundRect(cr, vx + 2, 17, 28, 18, 5);
  cairo_set_source_rgb(cr, 1, 1, 1);
  cairo_fill(cr);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.65);
  for (int i = 0; i < 4; ++i) {
    cairo_rectangle(cr, vx + 10 + (i % 2) * 6, 20 + (i / 2) * 6, 4.5, 4.5);
  }
  cairo_fill(cr);
  for (int i = 0; i < 3; ++i) cairo_rectangle(cr, vx + 39, 20.5 + i * 4.5, 14, 1.6);
  cairo_fill(cr);
  cairo_set_line_width(cr, 1.6);
  cairo_arc(cr, kFinderW - 40, 25, 5.5, 0, 2 * kPi);
  cairo_stroke(cr);
  cairo_move_to(cr, kFinderW - 36, 29);
  cairo_line_to(cr, kFinderW - 31.5, 33.5);
  cairo_stroke(cr);

  // Icon grid.
  cairo_save(cr);
  cairo_rectangle(cr, kSidebarW, kToolbarH, kFinderW - kSidebarW, kFinderH - kToolbarH - kStatusH);
  cairo_clip(cr);
  int cols = FinderCols();
  for (int i = 0; i < g_nfentries; ++i) {
    double cx = kSidebarW + 12 + (i % cols) * kCellW;
    double cy = kToolbarH + 10 + (i / cols) * kCellH - g_fscroll;
    if (cy > kFinderH || cy + kCellH < kToolbarH) continue;
    if (i == g_fsel) {
      RoundRect(cr, cx + (kCellW - 76) / 2.0, cy - 2, 76, 72, 6);
      cairo_set_source_rgba(cr, 0, 0, 0, 0.09);
      cairo_fill(cr);
    }
    if (g_fentries[i].icon) {
      cairo_set_source_surface(cr, g_fentries[i].icon, cx + (kCellW - 64) / 2.0, cy + 2);
      cairo_paint(cr);
    }
    SetFont(cr, 12, false);
    char label[160];
    Ellipsize(cr, g_fentries[i].name, kCellW - 10, label, sizeof(label));
    double tw = TextW(cr, label);
    if (i == g_fsel) {
      RoundRect(cr, cx + (kCellW - tw) / 2 - 5, cy + 71, tw + 10, 17, 4);
      cairo_set_source_rgb(cr, 0.0, 0.40, 0.88);
      cairo_fill(cr);
      cairo_set_source_rgb(cr, 1, 1, 1);
    } else {
      cairo_set_source_rgba(cr, 0, 0, 0, 0.85);
    }
    Text(cr, cx + (kCellW - tw) / 2, cy + 83.5, label);
  }
  cairo_restore(cr);

  // Status bar.
  cairo_rectangle(cr, kSidebarW, kFinderH - kStatusH, kFinderW - kSidebarW, kStatusH);
  cairo_set_source_rgb(cr, 0.975, 0.975, 0.98);
  cairo_fill(cr);
  cairo_rectangle(cr, kSidebarW, kFinderH - kStatusH, kFinderW - kSidebarW, 1);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.10);
  cairo_fill(cr);
  char status[96];
  snprintf(status, sizeof(status), "%d items, 1.9 GB available", g_nfentries);
  SetFont(cr, 11, false);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.5);
  TextCentered(cr, kSidebarW + (kFinderW - kSidebarW) / 2.0, kFinderH - 8, status);
  RoundRect(cr, 0.5, 0.5, kFinderW - 1, kFinderH - 1, 10);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.28);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  cairo_destroy(cr);
  Blit(g_finder_win, img);
  cairo_surface_destroy(img);
}

Window CreateAppWindow(int x, int y, int w, int h, const char* title, const char* cls) {
  XSetWindowAttributes attrs;
  memset(&attrs, 0, sizeof(attrs));
  attrs.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask |
                     LeaveWindowMask | FocusChangeMask | StructureNotifyMask;
  Window win = XCreateWindow(g_dpy, g_root, x, y, static_cast<unsigned>(w),
                             static_cast<unsigned>(h), 0, CopyFromParent, InputOutput,
                             CopyFromParent, CWEventMask, &attrs);
  SetNoDecorations(win);
  SetTitle(win, title, cls, cls);
  XSizeHints sh;
  memset(&sh, 0, sizeof(sh));
  sh.flags = PPosition | PSize | PMinSize | PMaxSize;
  sh.x = x;
  sh.y = y;
  sh.width = sh.min_width = sh.max_width = w;
  sh.height = sh.min_height = sh.max_height = h;
  XSetWMNormalHints(g_dpy, win, &sh);
  XWMHints wmh;
  memset(&wmh, 0, sizeof(wmh));
  wmh.flags = InputHint;
  wmh.input = True;
  XSetWMHints(g_dpy, win, &wmh);
  Atom del = A("WM_DELETE_WINDOW");
  XSetWMProtocols(g_dpy, win, &del, 1);
  ShapeRounded(win, w, h, 10);
  XMapRaised(g_dpy, win);
  XMoveWindow(g_dpy, win, x, y);
  return win;
}

void OpenFinderWindow() {
  if (g_finder_win) {
    FocusOwnWindow(g_finder_win);
    return;
  }
  LoadFinderEntries();
  g_finder_win = CreateAppWindow(162, 80, kFinderW, kFinderH, "Applications", "Finder");
}

void CloseFinderWindow() {
  if (!g_finder_win) return;
  XDestroyWindow(g_dpy, g_finder_win);
  g_finder_win = 0;
  g_finder_reported = 0;
  g_fsel = -1;
}

bool InLights(int x, int y, int lx, int ly) {
  return y >= ly - 8 && y <= ly + 8 && x >= lx - 8 && x <= lx + 48;
}

void FinderPress(const XButtonEvent& b) {
  if (b.button == Button4 || b.button == Button5) {
    int cols = FinderCols();
    int rows = (g_nfentries + cols - 1) / cols;
    int maxs = rows * kCellH + 20 - (kFinderH - kToolbarH - kStatusH);
    g_fscroll += b.button == Button5 ? 40 : -40;
    if (g_fscroll > maxs) g_fscroll = maxs;
    if (g_fscroll < 0) g_fscroll = 0;
    DrawFinder();
    return;
  }
  if (b.button != Button1) return;
  if (InLights(b.x, b.y, 20, 20)) {
    if (b.x <= 28) CloseFinderWindow();
    return;
  }
  if (b.y < kToolbarH) {
    StartWindowMove(g_finder_win, b.x_root, b.y_root, b.time);
    return;
  }
  if (b.x > kSidebarW && b.y < kFinderH - kStatusH) {
    int cols = FinderCols();
    int col = (b.x - kSidebarW - 12) / kCellW;
    int row = (b.y - kToolbarH - 10 + g_fscroll) / kCellH;
    int idx = (col >= 0 && col < cols && row >= 0) ? row * cols + col : -1;
    if (idx >= g_nfentries) idx = -1;
    double now = NowSec();
    if (idx >= 0 && idx == g_flast_index && now - g_flast_click < 0.5) {
      printf("DARLING_FINDER_OPEN:%s\n", g_fentries[idx].path);
      fflush(stdout);
      Launch(g_fentries[idx].path);
      for (int i = 0; i < g_ndock; ++i) {
        if (!strcmp(g_dock[i].path, g_fentries[idx].path)) g_dock[i].bounce_start = now;
      }
    }
    g_flast_click = now;
    g_flast_index = idx;
    g_fsel = idx;
    DrawFinder();
  }
}

// ---------------------------------------------------------------------------
// About This Mac
// ---------------------------------------------------------------------------
constexpr int kAboutW = 300, kAboutH = 392;
bool g_about_active = true, g_about_hover = false;

void ReadProductVersion(char* out, size_t cap) {
  snprintf(out, cap, "26.5");
  FILE* fp = fopen("/System/Library/CoreServices/SystemVersion.plist", "r");
  if (!fp) return;
  char buf[4096];
  size_t n = fread(buf, 1, sizeof(buf) - 1, fp);
  fclose(fp);
  buf[n] = '\0';
  const char* k = strstr(buf, "<key>ProductVersion</key>");
  const char* s = k ? strstr(k, "<string>") : nullptr;
  const char* e = s ? strstr(s, "</string>") : nullptr;
  if (s && e) snprintf(out, cap, "%.*s", static_cast<int>(e - s - 8), s + 8);
}

void DrawAbout() {
  if (!g_about_win) return;
  cairo_surface_t* img = NewImage(kAboutW, kAboutH);
  cairo_t* cr = cairo_create(img);
  cairo_set_source_rgb(cr, 0.925, 0.925, 0.93);
  cairo_paint(cr);
  DrawTrafficLights(cr, 20, 16, g_about_active, g_about_hover);
  // A Mac with the current wallpaper on screen.
  double mx = kAboutW / 2.0 - 70, my = 40;
  RoundRect(cr, mx, my, 140, 92, 7);
  cairo_set_source_rgb(cr, 0.80, 0.81, 0.84);
  cairo_fill(cr);
  RoundRect(cr, mx + 5, my + 5, 130, 74, 3);
  cairo_set_source_rgb(cr, 0.1, 0.1, 0.12);
  cairo_fill(cr);
  cairo_save(cr);
  cairo_rectangle(cr, mx + 7, my + 7, 126, 70);
  cairo_clip(cr);
  cairo_translate(cr, mx + 7, my + 7);
  cairo_scale(cr, 126.0 / g_w, 70.0 / g_h);
  cairo_set_source_surface(cr, g_wall, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
  cairo_move_to(cr, mx + 56, my + 92);
  cairo_line_to(cr, mx + 84, my + 92);
  cairo_line_to(cr, mx + 90, my + 112);
  cairo_line_to(cr, mx + 50, my + 112);
  cairo_close_path(cr);
  cairo_set_source_rgb(cr, 0.72, 0.73, 0.76);
  cairo_fill(cr);
  char ver[64], line[160];
  ReadProductVersion(ver, sizeof(ver));
  SetFont(cr, 24, true);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.88);
  TextCentered(cr, kAboutW / 2.0, 186, "Darling");
  SetFont(cr, 12, false);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.5);
  snprintf(line, sizeof(line), "Version %s", ver);
  TextCentered(cr, kAboutW / 2.0, 206, line);

  int ncpu = 4;
  uint64_t mem = 2ULL << 30;
  char rel[64] = "25.5.0";
  size_t len = sizeof(ncpu);
  sysctlbyname("hw.ncpu", &ncpu, &len, nullptr, 0);
  len = sizeof(mem);
  sysctlbyname("hw.memsize", &mem, &len, nullptr, 0);
  len = sizeof(rel) - 1;
  sysctlbyname("kern.osrelease", rel, &len, nullptr, 0);
  char chip[64], memory[32], darwin[96];
  snprintf(chip, sizeof(chip), "ARM Cortex-A72 (%d cores)", ncpu);
  snprintf(memory, sizeof(memory), "%llu GB",
           static_cast<unsigned long long>((mem + (512ULL << 20)) >> 30));
  snprintf(darwin, sizeof(darwin), "Darwin %s", rel);
  const char* rows[][2] = {{"Chip", chip},
                           {"Memory", memory},
                           {"Startup disk", "Macintosh HD"},
                           {"Serial number", "DARLING-ARM64"},
                           {"Kernel", darwin}};
  for (int i = 0; i < 5; ++i) {
    double y = 238 + i * 19;
    SetFont(cr, 12, false);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.85);
    Text(cr, 136 - TextW(cr, rows[i][0]), y, rows[i][0]);
    cairo_set_source_rgba(cr, 0, 0, 0, 0.5);
    Text(cr, 144, y, rows[i][1]);
  }
  DrawPushButton(cr, kAboutW / 2.0 - 55, 340, 110, 22, "More Info\xE2\x80\xA6", false, false);
  SetFont(cr, 10, false);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.4);
  TextCentered(cr, kAboutW / 2.0, 380, "\xE2\x84\xA2 and \xC2\xA9 2026 The Darling Project");
  RoundRect(cr, 0.5, 0.5, kAboutW - 1, kAboutH - 1, 10);
  cairo_set_source_rgba(cr, 0, 0, 0, 0.28);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  cairo_destroy(cr);
  Blit(g_about_win, img);
  cairo_surface_destroy(img);
}

void OpenAboutWindow() {
  if (g_about_win) {
    FocusOwnWindow(g_about_win);
    return;
  }
  int x = (g_w - kAboutW) / 2, y = 120;
  g_about_win = CreateAppWindow(x, y, kAboutW, kAboutH, "About This Mac", "SystemUIServer");
}

void CloseAboutWindow() {
  if (!g_about_win) return;
  XDestroyWindow(g_dpy, g_about_win);
  g_about_win = 0;
  g_about_reported = 0;
}

void AboutPress(const XButtonEvent& b) {
  if (b.button != Button1) return;
  if (InLights(b.x, b.y, 20, 16)) {
    if (b.x <= 28) CloseAboutWindow();
    return;
  }
  if (b.y < 30) StartWindowMove(g_about_win, b.x_root, b.y_root, b.time);
}

void SendDelete(Window w) {
  XEvent ev;
  memset(&ev, 0, sizeof(ev));
  ev.xclient.type = ClientMessage;
  ev.xclient.window = w;
  ev.xclient.message_type = A("WM_PROTOCOLS");
  ev.xclient.format = 32;
  ev.xclient.data.l[0] = static_cast<long>(A("WM_DELETE_WINDOW"));
  ev.xclient.data.l[1] = CurrentTime;
  XSendEvent(g_dpy, w, False, NoEventMask, &ev);
  XFlush(g_dpy);
}

void PerformInternal(int action) {
  switch (action) {
    case kActAboutMac:
    case kActAboutFinder:
      OpenAboutWindow();
      break;
    case kActNewFinderWindow:
    case kActApplications:
      OpenFinderWindow();
      break;
    case kActCloseFinder:
      CloseFinderWindow();
      break;
    case kActForceQuit:
      if (g_active_pid > 1) kill(g_active_pid, SIGKILL);
      break;
    case kActQuitForeign:
      if (g_active_pid > 1) {
        kill(g_active_pid, SIGTERM);
      } else if (g_active) {
        SendDelete(g_active);
      }
      break;
    case kActCloseForeign:
      if (g_active) SendDelete(g_active);
      break;
    case kActMinimizeForeign:
      if (g_active) XIconifyWindow(g_dpy, g_active, g_scr);
      break;
    default:
      printf("[Shell] menu action %d is not available in this environment\n", action);
      fflush(stdout);
      break;
  }
}

void CreateBar() {
  XSetWindowAttributes attrs;
  memset(&attrs, 0, sizeof(attrs));
  attrs.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask |
                     KeyPressMask | KeyReleaseMask;
  g_bar = XCreateWindow(g_dpy, g_root, 0, 0, static_cast<unsigned>(g_w), kBarH, 0,
                        CopyFromParent, InputOutput, CopyFromParent, CWEventMask, &attrs);
  SetWindowType(g_bar, "_NET_WM_WINDOW_TYPE_DOCK");
  SetTitle(g_bar, "Menu Bar", "SystemUIServer", "SystemUIServer");
  long strut[12] = {0, 0, kBarH, 0, 0, 0, 0, 0, 0, g_w - 1, 0, 0};
  XChangeProperty(g_dpy, g_bar, A("_NET_WM_STRUT_PARTIAL"), XA_CARDINAL, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(strut), 12);
  XChangeProperty(g_dpy, g_bar, A("_NET_WM_STRUT"), XA_CARDINAL, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(strut), 4);
  long all = 0xFFFFFFFFL;
  XChangeProperty(g_dpy, g_bar, A("_NET_WM_DESKTOP"), XA_CARDINAL, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(&all), 1);
  XWMHints wmh;
  memset(&wmh, 0, sizeof(wmh));
  wmh.flags = InputHint;
  wmh.input = False;
  XSetWMHints(g_dpy, g_bar, &wmh);
  XMapRaised(g_dpy, g_bar);
  XMoveWindow(g_dpy, g_bar, 0, 0);
}

void CreateDock() {
  SetupDockItems();
  LayoutDock();
  XSetWindowAttributes attrs;
  memset(&attrs, 0, sizeof(attrs));
  attrs.event_mask = ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask |
                     LeaveWindowMask | KeyPressMask | KeyReleaseMask;
  g_dock_win = XCreateWindow(g_dpy, g_root, g_dock_x, g_dock_y,
                             static_cast<unsigned>(g_dock_w), static_cast<unsigned>(g_dock_h),
                             0, CopyFromParent, InputOutput, CopyFromParent, CWEventMask,
                             &attrs);
  SetWindowType(g_dock_win, "_NET_WM_WINDOW_TYPE_DOCK");
  SetTitle(g_dock_win, "Dock", "Dock", "Dock");
  long all = 0xFFFFFFFFL;
  XChangeProperty(g_dpy, g_dock_win, A("_NET_WM_DESKTOP"), XA_CARDINAL, 32, PropModeReplace,
                  reinterpret_cast<unsigned char*>(&all), 1);
  XWMHints wmh;
  memset(&wmh, 0, sizeof(wmh));
  wmh.flags = InputHint;
  wmh.input = False;
  XSetWMHints(g_dpy, g_dock_win, &wmh);
  ShapeDock(0);
  XMapRaised(g_dpy, g_dock_win);
  XMoveWindow(g_dpy, g_dock_win, g_dock_x, g_dock_y);
}

int DropLevelOf(Window w) {
  for (int l = 0; l < g_ndrops; ++l) {
    if (g_drops[l].win == w) return l;
  }
  return -1;
}

// Reports where the window manager actually placed one of our windows.
void ReportWindowOnce(Window w, const char* marker, Window* reported) {
  if (*reported == w) return;
  *reported = w;
  int rx = 0, ry = 0;
  Window child = 0;
  XWindowAttributes wa;
  XGetWindowAttributes(g_dpy, w, &wa);
  XTranslateCoordinates(g_dpy, w, g_root, 0, 0, &rx, &ry, &child);
  printf("%s%d:%d:%d:%d\n", marker, rx, ry, wa.width, wa.height);
  fflush(stdout);
}



// Minimal window placement (the shell owns SubstructureRedirect on the root
// window): requests are honoured as made, except that windows are kept below
// the menu bar.
void HandleRedirect(XEvent& ev) {
  if (ev.type == MapRequest) {
    Window w = ev.xmaprequest.window;
    XWindowAttributes wa;
    if (!IsOwnWindow(w) && XGetWindowAttributes(g_dpy, w, &wa) && wa.y < kBarH) {
      XMoveWindow(g_dpy, w, wa.x < 8 ? 16 : wa.x, kBarH + 24);
    }
    XMapWindow(g_dpy, w);
  } else if (ev.type == ConfigureRequest) {
    const XConfigureRequestEvent& r = ev.xconfigurerequest;
    XWindowChanges wc;
    memset(&wc, 0, sizeof(wc));
    wc.x = r.x;
    wc.y = r.y;
    wc.width = r.width;
    wc.height = r.height;
    wc.border_width = r.border_width;
    wc.sibling = r.above;
    wc.stack_mode = r.detail;
    if ((r.value_mask & CWY) && wc.y < kBarH && !IsOwnWindow(r.window)) wc.y = kBarH;
    XConfigureWindow(g_dpy, r.window, static_cast<unsigned>(r.value_mask), &wc);
  } else if (ev.type == CirculateRequest) {
    if (ev.xcirculaterequest.place == PlaceOnTop) {
      XRaiseWindow(g_dpy, ev.xcirculaterequest.window);
    } else {
      XLowerWindow(g_dpy, ev.xcirculaterequest.window);
    }
  }
}

void HandleEvent(XEvent& ev) {
  Window w = ev.xany.window;
  if (ev.type == MapRequest || ev.type == ConfigureRequest || ev.type == CirculateRequest) {
    HandleRedirect(ev);
    return;
  }
  if (w == g_root && (ev.type == CreateNotify || ev.type == MapNotify ||
                      ev.type == UnmapNotify || ev.type == DestroyNotify ||
                      ev.type == ConfigureNotify)) {
    HandleTopLevelEvent(ev);
    return;
  }
  switch (ev.type) {
    case Expose:
      if (ev.xexpose.count) break;
      if (w == g_bar) {
        DrawBar();
      } else if (w == g_dock_win) {
        DrawDock();
      } else if (w == g_finder_win) {
        DrawFinder();
        if (g_finder_reported != w) FocusOwnWindow(w);
        ReportWindowOnce(w, "DARLING_FINDER_WINDOW:", &g_finder_reported);
      } else if (w == g_about_win) {
        DrawAbout();
        if (g_about_reported != w) FocusOwnWindow(w);
        ReportWindowOnce(w, "DARLING_ABOUT_MAC_WINDOW:", &g_about_reported);
      } else if (DropLevelOf(w) >= 0) {
        DrawDrop(DropLevelOf(w));
      } else if (w == g_label_win && g_label_img) {
        Blit(g_label_win, g_label_img);
      }
      break;
    case ButtonPress:
      if (g_open_entry >= 0) {
        MenuPress(ev.xbutton.x_root, ev.xbutton.y_root);
      } else if (w == g_bar && ev.xbutton.button == Button1) {
        int e = BarEntryAt(ev.xbutton.x, ev.xbutton.y);
        g_press_time = NowSec();
        if (e >= 0) OpenEntry(e);
      } else if (w == g_dock_win && ev.xbutton.button == Button1) {
        g_dock_pressed = DockItemAt(ev.xbutton.x, ev.xbutton.y);
        HideDockLabel();
        DrawDock();
      } else if (w == g_finder_win) {
        FocusOwnWindow(w);
        FinderPress(ev.xbutton);
      } else if (w == g_about_win) {
        FocusOwnWindow(w);
        AboutPress(ev.xbutton);
      }
      break;
    case ButtonRelease:
      if (g_drag_win) {
        g_drag_win = 0;
        XUngrabPointer(g_dpy, ev.xbutton.time);
      } else if (g_open_entry >= 0) {
        MenuRelease(ev.xbutton.x_root, ev.xbutton.y_root);
      } else if (w == g_dock_win && ev.xbutton.button == Button1) {
        int i = DockItemAt(ev.xbutton.x, ev.xbutton.y);
        int pressed = g_dock_pressed;
        g_dock_pressed = -1;
        if (i >= 0 && i == pressed) DockClick(i);
        DrawDock();
      }
      break;
    case MotionNotify:
      if (g_drag_win && w == g_drag_win) {
        while (XCheckTypedWindowEvent(g_dpy, w, MotionNotify, &ev)) {
        }
        int ny = ev.xmotion.y_root - g_drag_dy;
        if (ny < kBarH) ny = kBarH;
        XMoveWindow(g_dpy, w, ev.xmotion.x_root - g_drag_dx, ny);
      } else if (g_open_entry >= 0) {
        MenuMotion(ev.xmotion.x_root, ev.xmotion.y_root);
      } else if (w == g_dock_win) {
        int i = DockItemAt(ev.xmotion.x, ev.xmotion.y);
        if (i != g_dock_hover) {
          g_dock_hover = i;
          if (i >= 0) {
            ShowDockLabel(i);
          } else {
            HideDockLabel();
          }
        }
      } else if (w == g_finder_win) {
        bool h = InLights(ev.xmotion.x, ev.xmotion.y, 20, 20);
        if (h != g_finder_hover_lights) {
          g_finder_hover_lights = h;
          DrawFinder();
        }
      } else if (w == g_about_win) {
        bool h = InLights(ev.xmotion.x, ev.xmotion.y, 20, 16);
        if (h != g_about_hover) {
          g_about_hover = h;
          DrawAbout();
        }
      }
      break;
    case LeaveNotify:
      if (w == g_dock_win) {
        g_dock_hover = -1;
        HideDockLabel();
        if (g_dock_pressed >= 0) {
          g_dock_pressed = -1;
          DrawDock();
        }
      } else if (w == g_finder_win && g_finder_hover_lights) {
        g_finder_hover_lights = false;
        DrawFinder();
      } else if (w == g_about_win && g_about_hover) {
        g_about_hover = false;
        DrawAbout();
      }
      break;
    case KeyPress:
    case KeyRelease:
      if (g_open_entry >= 0) {
        if (ev.type == KeyPress) MenuKey(XLookupKeysym(&ev.xkey, 0));
      } else if (g_active && (w == g_bar || w == g_dock_win)) {
        // With the pointer over the menu bar or Dock, keystrokes (and
        // Command-key equivalents) belong to the active application.
        ev.xkey.window = g_active;
        XSendEvent(g_dpy, g_active, False,
                   ev.type == KeyPress ? KeyPressMask : KeyReleaseMask, &ev);
        XFlush(g_dpy);
      }
      break;
    case FocusIn:
    case FocusOut:
      if (w == g_finder_win) {
        g_finder_active = ev.type == FocusIn;
        DrawFinder();
      } else if (w == g_about_win) {
        g_about_active = ev.type == FocusIn;
        DrawAbout();
      }
      break;
    case PropertyNotify:
      if (w == g_root && ev.xproperty.atom == A("_DARLING_ACTIVE_WINDOW")) {
        RefreshActiveMenus();
      } else if (TopLevel* t = FindTop(w)) {
        if (ev.xproperty.atom == A("_DARLING_APP_MENU") ||
            ev.xproperty.atom == A("_DARLING_BUNDLE_PATH")) {
          ReadTopInfo(*t);
          UpdateRunning();
          if (w == g_active) RefreshActiveMenus();
        }
      }
      break;
    case ClientMessage:
      if (ev.xclient.message_type == A("WM_PROTOCOLS") &&
          static_cast<Atom>(ev.xclient.data.l[0]) == A("WM_DELETE_WINDOW")) {
        if (w == g_finder_win) CloseFinderWindow();
        if (w == g_about_win) CloseAboutWindow();
      }
      break;
    default:
      break;
  }
}

}  // namespace

extern "C" int main(int argc, char** argv) {
  (void)argc;
  (void)argv;
  if (!getenv("DISPLAY")) setenv("DISPLAY", ":0", 1);
  for (int retry = 0; retry < 600 && !g_dpy; ++retry) {
    g_dpy = XOpenDisplay(nullptr);
    if (!g_dpy) usleep(50000);
  }
  if (!g_dpy) {
    fprintf(stderr, "darling-shell: cannot open display\n");
    return 1;
  }
  XSetErrorHandler(IgnoreXErrors);
  g_scr = DefaultScreen(g_dpy);
  g_root = RootWindow(g_dpy, g_scr);
  g_w = DisplayWidth(g_dpy, g_scr);
  g_h = DisplayHeight(g_dpy, g_scr);
  g_vis = DefaultVisual(g_dpy, g_scr);
  g_depth = DefaultDepth(g_dpy, g_scr);

  SetupWallpaper();
  SetupCursor();
  CreateBar();
  CreateDock();
  XSelectInput(g_dpy, g_root,
               PropertyChangeMask | SubstructureNotifyMask | SubstructureRedirectMask);
  XSync(g_dpy, False);
  ScanTopLevels();
  SetActiveWindowProperty(0);
  BuildFinderMenus();
  RefreshActiveMenus();
  UpdateRunning();
  DrawDock();
  ReportDockLayout();
  printf("DARLING_SHELL_READY:menubar=%d:dock=%d,%d,%d,%d:items=%d\n", kBarH, g_dock_x,
         g_dock_y, g_dock_w, g_dock_h, g_ndock);
  fflush(stdout);

  double last_scan = NowSec();
  int fd = ConnectionNumber(g_dpy);
  while (true) {
    while (XPending(g_dpy) > 0) {
      XEvent ev;
      XNextEvent(g_dpy, &ev);
      HandleEvent(ev);
    }
    bool animating = DockAnimating();
    pollfd pfd = {fd, POLLIN, 0};
    poll(&pfd, 1, animating ? 30 : 500);
    double now = NowSec();
    if (animating) DrawDock();
    time_t t = time(nullptr);
    struct tm tmv;
    localtime_r(&t, &tmv);
    if (tmv.tm_min != g_last_minute) {
      g_last_minute = tmv.tm_min;
      DrawBar();
    }
    if (g_desk_dirty && now - g_desk_rendered > 0.15) {
      g_desk_dirty = false;
      g_desk_rendered = now;
      Window wins[170];
      int nw = 0;
      for (int i = 0; i < g_ntops && nw < 168; ++i) {
        if (g_tops[i].mapped) wins[nw++] = g_tops[i].w;
      }
      if (g_finder_win) wins[nw++] = g_finder_win;
      if (g_about_win) wins[nw++] = g_about_win;
      RenderDesktopWithShadows(wins, nw);
    }
    if (now - last_scan > 1.5) {
      last_scan = now;
      bool before[24];
      for (int i = 0; i < g_ndock; ++i) before[i] = g_dock[i].running;
      UpdateRunning();
      bool changed = false;
      for (int i = 0; i < g_ndock; ++i) changed |= before[i] != g_dock[i].running;
      if (changed && !animating) DrawDock();
    }
    while (waitpid(-1, nullptr, WNOHANG) > 0) {
    }
  }
  return 0;
}
