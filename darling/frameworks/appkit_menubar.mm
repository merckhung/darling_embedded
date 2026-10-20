// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded AppKit: global menu bar integration and standard panels.
//
// The application's main menu (from MainMenu.nib, or a default Mac OS X menu)
// is published as text in the _DARLING_APP_MENU property of every window;
// the desktop shell (darling-shell) draws it in the menu bar and sends the
// chosen item back as a _DARLING_MENU_ACTION client message carrying the
// item's index path. Command-key equivalents are matched here as well.
// Included from appkit.mm after appkit_more.mm.

namespace {

NSMenu* g_main_menu = nil;
NSMenu* g_default_menu = nil;

struct TextBuffer {
  char* data = nullptr;
  size_t len = 0, cap = 0;
  void Add(const char* s, size_t n) {
    if (len + n + 1 > cap) {
      size_t ncap = cap ? cap * 2 : 1024;
      while (ncap < len + n + 1) ncap *= 2;
      char* nd = static_cast<char*>(realloc(data, ncap));
      if (!nd) return;
      data = nd;
      cap = ncap;
    }
    memcpy(data + len, s, n);
    len += n;
    data[len] = '\0';
  }
  void Add(const char* s) { Add(s, strlen(s)); }
  void Add(char c) { Add(&c, 1); }
};

NSString* ApplicationName() {
  NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
  for (NSString* key in @[ @"CFBundleDisplayName", @"CFBundleName", @"CFBundleExecutable" ]) {
    id v = info ? [info objectForKey:key] : nil;
    if ([v isKindOfClass:[NSString class]] && [v length] > 0) return v;
  }
  const char* prog = getprogname();
  return [NSString stringWithUTF8String:prog ? prog : "Application"];
}

NSMenuItem* AddMenuItem(NSMenu* menu, NSString* title, SEL action, NSString* key,
                        NSUInteger mask = 1UL << 20) {
  NSMenuItem* item = [menu addItemWithTitle:title action:action keyEquivalent:key];
  item->_keyMask = mask;
  return item;
}

NSMenu* AddSubmenu(NSMenu* main, NSString* title) {
  NSMenuItem* top = [main addItemWithTitle:title action:nullptr keyEquivalent:@""];
  NSMenu* sub = [[NSMenu alloc] initWithTitle:title];
  [top setSubmenu:sub];
  return sub;
}

// The standard Mac OS X menu for applications without a MainMenu.nib menu.
NSMenu* DefaultMainMenu() {
  if (g_default_menu) return g_default_menu;
  NSString* name = ApplicationName();
  NSMenu* main = [[NSMenu alloc] initWithTitle:@"MainMenu"];
  NSMenu* app = AddSubmenu(main, name);
  AddMenuItem(app, [NSString stringWithFormat:@"About %@", name],
              @selector(orderFrontStandardAboutPanel:), @"");
  [app addItem:[NSMenuItem separatorItem]];
  AddMenuItem(app, [NSString stringWithFormat:@"Hide %@", name], @selector(hide:), @"h");
  AddMenuItem(app, @"Hide Others", @selector(hideOtherApplications:), @"h",
              (1UL << 20) | (1UL << 19));
  AddMenuItem(app, @"Show All", @selector(unhideAllApplications:), @"");
  [app addItem:[NSMenuItem separatorItem]];
  AddMenuItem(app, [NSString stringWithFormat:@"Quit %@", name], @selector(terminate:), @"q");
  NSMenu* file = AddSubmenu(main, @"File");
  AddMenuItem(file, @"Close Window", @selector(performClose:), @"w");
  NSMenu* edit = AddSubmenu(main, @"Edit");
  AddMenuItem(edit, @"Undo", @selector(undo:), @"z");
  AddMenuItem(edit, @"Redo", @selector(redo:), @"Z");
  [edit addItem:[NSMenuItem separatorItem]];
  AddMenuItem(edit, @"Cut", @selector(cut:), @"x");
  AddMenuItem(edit, @"Copy", @selector(copy:), @"c");
  AddMenuItem(edit, @"Paste", @selector(paste:), @"v");
  AddMenuItem(edit, @"Select All", @selector(selectAll:), @"a");
  NSMenu* window = AddSubmenu(main, @"Window");
  AddMenuItem(window, @"Minimize", @selector(performMiniaturize:), @"m");
  AddMenuItem(window, @"Zoom", @selector(performZoom:), @"");
  [window addItem:[NSMenuItem separatorItem]];
  AddMenuItem(window, @"Bring All to Front", @selector(arrangeInFront:), @"");
  NSMenu* help = AddSubmenu(main, @"Help");
  AddMenuItem(help, [NSString stringWithFormat:@"%@ Help", name], @selector(showHelp:), @"?");
  g_default_menu = main;
  return main;
}

NSMenu* ActiveMainMenu() {
  return (g_main_menu && [g_main_menu numberOfItems] > 0) ? g_main_menu : DefaultMainMenu();
}

// Finds the object that handles |action|: the explicit target, or the
// responder chain (key window, its delegate, the application and its
// delegate).
id ResponderForAction(SEL action, id target) {
  if (!action) return nil;
  if (target) return [target respondsToSelector:action] ? target : nil;
  NSWindow* key = NSApp ? NSApp->_keyWindow : nil;
  id candidates[4] = {key, key ? [key delegate] : nil, NSApp, NSApp ? [NSApp delegate] : nil};
  for (id c : candidates) {
    if (c && [c respondsToSelector:action]) return c;
  }
  return nil;
}

bool ItemEnabled(NSMenuItem* item) {
  if (item->_separator || !item->_enabled) return false;
  if (item->_submenu) return true;
  return ResponderForAction(item->_action, item->_target) != nil;
}

// Formats a key equivalent the way Mac OS X menus show it, e.g. "⇧⌘N".
void FormatKeyEquivalent(NSMenuItem* item, char* out, size_t cap) {
  out[0] = '\0';
  const char* k = item->_keyEquivalent ? [item->_keyEquivalent UTF8String] : "";
  if (!k || !k[0]) return;
  NSUInteger mask = item->_keyMask;
  unsigned char c = static_cast<unsigned char>(k[0]);
  bool shift = (mask & (1UL << 17)) || (c >= 'A' && c <= 'Z');
  char key[16];
  if (c == '\r') {
    snprintf(key, sizeof(key), "\xE2\x86\xA9");
  } else if (c == 0x1b) {
    snprintf(key, sizeof(key), "\xE2\x8E\x8B");
  } else if (c == 0x08 || c == 0x7f) {
    snprintf(key, sizeof(key), "\xE2\x8C\xAB");
  } else if (c == '\t') {
    snprintf(key, sizeof(key), "\xE2\x87\xA5");
  } else if (c == ' ') {
    snprintf(key, sizeof(key), "Space");
  } else if (c == 0xEF && static_cast<unsigned char>(k[1]) == 0x9C) {
    // Function-key range U+F700..: arrows; other function keys are omitted.
    static const char* kArrows[4] = {"\xE2\x86\x91", "\xE2\x86\x93", "\xE2\x86\x90",
                                     "\xE2\x86\x92"};
    unsigned char c2 = static_cast<unsigned char>(k[2]);
    if (c2 < 0x80 || c2 > 0x83) return;
    snprintf(key, sizeof(key), "%s", kArrows[c2 - 0x80]);
  } else if (c < 0x80) {
    key[0] = static_cast<char>(toupper(c));
    key[1] = '\0';
  } else {
    snprintf(key, sizeof(key), "%s", k);
  }
  snprintf(out, cap, "%s%s%s%s%s", (mask & (1UL << 18)) ? "\xE2\x8C\x83" : "",
           (mask & (1UL << 19)) ? "\xE2\x8C\xA5" : "", shift ? "\xE2\x87\xA7" : "",
           (mask & (1UL << 20)) ? "\xE2\x8C\x98" : "", key);
}

void AppendTitle(TextBuffer& buf, NSString* title) {
  const char* t = title ? [title UTF8String] : "";
  for (const char* p = t ? t : ""; *p; ++p) {
    buf.Add(*p == '\n' || *p == '\x1f' ? ' ' : *p);
  }
}

void SerializeMenu(TextBuffer& buf, NSMenu* menu, int depth) {
  if (!menu || depth > 4) return;
  bool top_level = depth == 0;
  NSUInteger n = [menu->_items count];
  for (NSUInteger i = 0; i < n; ++i) {
    NSMenuItem* item = [menu->_items objectAtIndex:i];
    for (int d = 0; d < depth; ++d) buf.Add('\t');
    buf.Add(ItemEnabled(item) || top_level ? 'E' : 'D');
    if (item->_separator) buf.Add('S');
    if (item->_state == 1) buf.Add('C');
    if (item->_hidden) buf.Add('H');
    buf.Add('\x1f');
    NSString* title = item->_title;
    if (top_level && (!title || [title length] == 0) && item->_submenu) {
      title = static_cast<NSMenu*>(item->_submenu)->_title;
    }
    AppendTitle(buf, title);
    buf.Add('\x1f');
    char key[48];
    FormatKeyEquivalent(item, key, sizeof(key));
    buf.Add(key);
    buf.Add('\n');
    if (item->_submenu) SerializeMenu(buf, item->_submenu, depth + 1);
  }
}

TextBuffer g_published;

void BuildMenuText(TextBuffer& buf) {
  buf.len = 0;
  buf.Add('#');
  AppendTitle(buf, ApplicationName());
  buf.Add('\n');
  SerializeMenu(buf, ActiveMainMenu(), 0);
}

void SetMenuProperty(Display* dpy, Window w, const TextBuffer& buf) {
  if (!dpy || !w || !buf.data) return;
  XChangeProperty(dpy, w, XInternAtom(dpy, "_DARLING_APP_MENU", False),
                  XInternAtom(dpy, "UTF8_STRING", False), 8, PropModeReplace,
                  reinterpret_cast<const unsigned char*>(buf.data), static_cast<int>(buf.len));
}

NSMenuItem* ItemAtPath(const long* path, int len) {
  NSMenu* menu = ActiveMainMenu();
  NSMenuItem* item = nil;
  for (int i = 0; i < len && menu; ++i) {
    if (path[i] < 0 || path[i] >= [menu numberOfItems]) return nil;
    item = [menu itemAtIndex:path[i]];
    menu = i + 1 < len ? item->_submenu : nil;
  }
  return item;
}

void PerformMenuItem(NSMenuItem* item) {
  if (!item || !ItemEnabled(item) || item->_submenu) return;
  printf("DARLING_MENU_ACTION:%s:%s\n", item->_title ? [item->_title UTF8String] : "",
         item->_action ? sel_getName(item->_action) : "");
  fflush(stdout);
  id responder = ResponderForAction(item->_action, item->_target);
  if (!responder) return;
  typedef void (*ActionFn)(id, SEL, id);
  reinterpret_cast<ActionFn>(objc_msgSend)(responder, item->_action, item);
}

NSMenuItem* FindKeyEquivalent(NSMenu* menu, char key, bool shift, bool option, bool control) {
  if (!menu) return nil;
  for (NSMenuItem* item in menu->_items) {
    if (item->_submenu) {
      NSMenuItem* found = FindKeyEquivalent(item->_submenu, key, shift, option, control);
      if (found) return found;
      continue;
    }
    const char* k = item->_keyEquivalent ? [item->_keyEquivalent UTF8String] : "";
    if (!k || !k[0] || k[1]) continue;
    char kc = k[0];
    bool item_shift = (item->_keyMask & (1UL << 17)) != 0;
    if (kc >= 'A' && kc <= 'Z') {
      item_shift = true;
      kc = static_cast<char>(kc - 'A' + 'a');
    }
    bool item_option = (item->_keyMask & (1UL << 19)) != 0;
    bool item_control = (item->_keyMask & (1UL << 18)) != 0;
    if (!(item->_keyMask & (1UL << 20))) continue;
    if (kc == key && item_shift == shift && item_option == option && item_control == control) {
      return item;
    }
  }
  return nil;
}

}  // namespace

static void DarlingPublishMenusToWindow(Display* dpy, Window w) {
  TextBuffer buf;
  BuildMenuText(buf);
  SetMenuProperty(dpy, w, buf);
  free(buf.data);
}

// Raises and focuses |w| and tells the desktop shell that it is the active
// window (the session has no window manager).
static void DarlingActivateWindow(NSWindow* w) {
  if (!w || !w->_x11Window || !NSApp || !NSApp->_x11Display) return;
  auto* dpy = static_cast<Display*>(NSApp->_x11Display);
  Window xw = w->_x11Window;
  WindowChrome* chrome = ChromeFor(w);
  if (chrome->minimized) {
    chrome->minimized = false;
    XMapRaised(dpy, xw);
  }
  XRaiseWindow(dpy, xw);
  for (int i = 0; i < 100; ++i) {
    XWindowAttributes wa;
    if (XGetWindowAttributes(dpy, xw, &wa) && wa.map_state == IsViewable) {
      XSetInputFocus(dpy, xw, RevertToPointerRoot, CurrentTime);
      break;
    }
    XSync(dpy, False);
    usleep(5000);
  }
  unsigned long value = xw;
  XChangeProperty(dpy, DefaultRootWindow(dpy), XInternAtom(dpy, "_DARLING_ACTIVE_WINDOW", False),
                  XA_WINDOW, 32, PropModeReplace, reinterpret_cast<unsigned char*>(&value), 1);
  NSApp->_keyWindow = w;
  // Only the key window shows the active title bar.
  for (NSWindow* other in NSApp->_windows) {
    WindowChrome* c = ChromeFor(other);
    bool active = other == w;
    if (c->active != active) {
      c->active = active;
      if (other->_visible && other->_x11Window) other->_needsDisplay = YES;
    }
  }
  XFlush(dpy);
}

// Brings the application forward (Dock click): shows minimized or hidden
// windows and activates the key window.
static void DarlingActivateApplication(void) {
  if (!NSApp) return;
  NSWindow* target = nil;
  for (NSWindow* w in NSApp->_windows) {
    if (!w->_visible || !w->_x11Window) continue;
    WindowChrome* chrome = ChromeFor(w);
    if (chrome->minimized && NSApp->_x11Display) {
      chrome->minimized = false;
      XMapRaised(static_cast<Display*>(NSApp->_x11Display), w->_x11Window);
    }
    if (!target || w == NSApp->_keyWindow) target = w;
  }
  if (target) DarlingActivateWindow(target);
}

static void DarlingPublishMenus(void) {
  if (!NSApp || !NSApp->_x11Display) return;
  TextBuffer buf;
  BuildMenuText(buf);
  if (g_published.data && buf.len == g_published.len &&
      memcmp(buf.data, g_published.data, buf.len) == 0) {
    free(buf.data);
    return;
  }
  auto* dpy = static_cast<Display*>(NSApp->_x11Display);
  for (NSWindow* w in NSApp->_windows) {
    if (w->_x11Window) SetMenuProperty(dpy, w->_x11Window, buf);
  }
  XFlush(dpy);
  free(g_published.data);
  g_published = buf;
}

static void DarlingPerformMenuPath(const long* path, int len) {
  PerformMenuItem(ItemAtPath(path, len));
  DarlingPublishMenus();
}

// Command is the Super (Mod4) key; with no Super key pressed, Alt (Mod1)
// also acts as Command.
static bool DarlingPerformKeyEquivalent(KeySym ks, unsigned int state) {
  bool super_key = (state & Mod4Mask) != 0;
  bool alt_key = (state & Mod1Mask) != 0;
  if (!super_key && !alt_key) return false;
  if (ks < 0x20 || ks > 0x7e) return false;
  char key = static_cast<char>(tolower(static_cast<int>(ks)));
  bool shift = (state & ShiftMask) != 0;
  bool option = super_key && alt_key;
  bool control = (state & ControlMask) != 0;
  NSMenuItem* item = FindKeyEquivalent(ActiveMainMenu(), key, shift, option, control);
  if (item && ItemEnabled(item)) {
    PerformMenuItem(item);
    DarlingPublishMenus();
    return true;
  }
  if (shift || option || control) return false;
  NSWindow* kw = NSApp ? NSApp->_keyWindow : nil;
  switch (key) {
    case 'q':
      [NSApp terminate:nil];
      return true;
    case 'w':
      if (kw) [kw performClose:nil];
      return kw != nil;
    case 'm':
      if (kw) [kw performMiniaturize:nil];
      return kw != nil;
    case 'h':
      [NSApp hide:nil];
      return true;
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Standard About panel
// ---------------------------------------------------------------------------
@interface _DarlingAboutPanelView : NSView {
 @public
  NSImage* _icon;
  NSString* _name;
  NSString* _version;
  NSString* _copyright;
}
@end

@implementation _DarlingAboutPanelView
// Breaks |text| into lines that fit |width| at the 10 pt About-panel size.
static NSString* WrapAboutText(NSString* text, double width) {
  cairo_t* cr = g_current_cairo;
  const char* src = [text UTF8String];
  if (!cr || !src) return text;
  cairo_select_font_face(cr, UIFontFamily(false), CAIRO_FONT_SLANT_NORMAL,
                         CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, 10.0);
  char out[1024], line[512];
  size_t o = 0, l = 0;
  out[0] = line[0] = '\0';
  const char* p = src;
  while (*p && o + 4 < sizeof(out)) {
    const char* sp = strchr(p, ' ');
    size_t wl = sp ? static_cast<size_t>(sp - p) : strlen(p);
    char cand[512];
    snprintf(cand, sizeof(cand), "%s%s%.*s", line, l ? " " : "", static_cast<int>(wl), p);
    cairo_text_extents_t ext;
    cairo_text_extents(cr, cand, &ext);
    if (l && ext.x_advance > width) {
      o += static_cast<size_t>(snprintf(out + o, sizeof(out) - o, "%s\n", line));
      snprintf(line, sizeof(line), "%.*s", static_cast<int>(wl), p);
    } else {
      snprintf(line, sizeof(line), "%s", cand);
    }
    l = strlen(line);
    p += wl;
    while (*p == ' ') ++p;
  }
  if (o < sizeof(out)) snprintf(out + o, sizeof(out) - o, "%s", line);
  return [NSString stringWithUTF8String:out];
}
- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  cairo_t* cr = g_current_cairo;
  if (!cr) return;
  double w = _bounds.size.width;
  NSRect icon_rect = NSMakeRect((w - 64) / 2, 14, 64, 64);
  if (_icon && [_icon isValid]) {
    [_icon drawInRect:icon_rect];
  } else {
    // Generic application icon.
    AppendRoundedRectPath(cr, NSInsetRect(icon_rect, 6, 6), 12);
    cairo_pattern_t* g = cairo_pattern_create_linear(0, 20, 0, 72);
    cairo_pattern_add_color_stop_rgb(g, 0, 0.45, 0.68, 1.0);
    cairo_pattern_add_color_stop_rgb(g, 1, 0.10, 0.38, 0.92);
    cairo_set_source(cr, g);
    cairo_fill(cr);
    cairo_pattern_destroy(g);
    const char* n = _name ? [_name UTF8String] : "A";
    char glyph[2] = {n && n[0] ? n[0] : 'A', 0};
    [NSBezierPath drawText:[NSString stringWithUTF8String:glyph]
                    inRect:NSMakeRect(icon_rect.origin.x, icon_rect.origin.y + 2, 64, 60)
                      font:[NSFont boldSystemFontOfSize:30]
                     color:[NSColor whiteColor]
                 alignment:NSTextAlignmentCenter];
  }
  [NSBezierPath drawText:_name ? _name : @""
                  inRect:NSMakeRect(0, 88, w, 20)
                    font:[NSFont boldSystemFontOfSize:14]
                   color:[NSColor labelColor]
               alignment:NSTextAlignmentCenter];
  NSColor* secondary = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0.5];
  [NSBezierPath drawText:_version ? _version : @""
                  inRect:NSMakeRect(0, 110, w, 16)
                    font:[NSFont systemFontOfSize:11]
                   color:secondary
               alignment:NSTextAlignmentCenter];
  [NSBezierPath drawText:_copyright ? WrapAboutText(_copyright, w - 24) : @""
                  inRect:NSMakeRect(10, 136, w - 20, 44)
                    font:[NSFont systemFontOfSize:10]
                   color:secondary
               alignment:NSTextAlignmentCenter];
}
@end

@implementation NSApplication (DarlingMenuBar)

- (void)setMainMenu:(NSMenu*)menu {
  g_main_menu = menu;
  DarlingPublishMenus();
}

- (NSMenu*)mainMenu {
  return g_main_menu;
}

- (void)orderFrontStandardAboutPanel:(id)sender {
  [self orderFrontStandardAboutPanelWithOptions:nil];
  (void)sender;
}

- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary*)options {
  static NSWindow* panel = nil;
  if (panel && panel->_visible) {
    [panel makeKeyAndOrderFront:nil];
    return;
  }
  NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
  NSString* name = ApplicationName();
  id short_version = info ? [info objectForKey:@"CFBundleShortVersionString"] : nil;
  id build = info ? [info objectForKey:@"CFBundleVersion"] : nil;
  id copyright = info ? [info objectForKey:@"NSHumanReadableCopyright"] : nil;
  if (options) {
    if ([options objectForKey:@"ApplicationName"]) name = [options objectForKey:@"ApplicationName"];
    if ([options objectForKey:@"ApplicationVersion"]) {
      short_version = [options objectForKey:@"ApplicationVersion"];
    }
    if ([options objectForKey:@"Version"]) build = [options objectForKey:@"Version"];
  }
  NSString* version = @"";
  if (short_version && build && ![short_version isEqual:build]) {
    version = [NSString stringWithFormat:@"Version %@ (%@)", short_version, build];
  } else if (short_version || build) {
    version = [NSString stringWithFormat:@"Version %@", short_version ? short_version : build];
  }
  _DarlingAboutPanelView* view =
      [[_DarlingAboutPanelView alloc] initWithFrame:NSMakeRect(0, 0, 280, 190)];
  view->_name = [name copy];
  view->_version = [version copy];
  view->_copyright = copyright ? [[copyright description] copy] : @"";
  id icon_file = info ? [info objectForKey:@"CFBundleIconFile"] : nil;
  if ([icon_file isKindOfClass:[NSString class]]) {
    char base[256];
    snprintf(base, sizeof(base), "%s", [icon_file UTF8String]);
    size_t blen = strlen(base);
    if (blen > 5 && strcmp(base + blen - 5, ".icns") == 0) base[blen - 5] = '\0';
    view->_icon = [NSImage imageNamed:[NSString stringWithUTF8String:base]];
  }
  panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 280, 190)
                                      styleMask:3
                                        backing:2
                                          defer:NO];
  [panel setTitle:[NSString stringWithFormat:@"About %@", name]];
  ChromeFor(panel)->hide_title = true;
  [panel setContentView:view];
  [panel center];
  [panel makeKeyAndOrderFront:nil];
}

- (void)hide:(id)sender {
  (void)sender;
  for (NSWindow* w in _windows) {
    if (w->_visible && w->_x11Window) [w miniaturize:nil];
  }
}

- (void)hideOtherApplications:(id)sender {
  (void)sender;
}

- (void)unhideAllApplications:(id)sender {
  (void)sender;
  DarlingActivateApplication();
}

- (void)showHelp:(id)sender {
  (void)sender;
  fprintf(stderr, "[AppKit] Help isn't available for %s.\n", [ApplicationName() UTF8String]);
}

@end

@implementation NSWindow (DarlingMenuBar)

- (void)miniaturize:(id)sender {
  (void)sender;
  if (_x11Window && NSApp && NSApp->_x11Display) {
    // Without a window manager a minimized window is simply unmapped; the
    // Dock brings it back through _DARLING_ACTIVATE_APP.
    auto* dpy = static_cast<Display*>(NSApp->_x11Display);
    ChromeFor(self)->minimized = true;
    XUnmapWindow(dpy, _x11Window);
    XFlush(dpy);
    printf("DARLING_WINDOW_MINIMIZED:%s\n", _title ? [_title UTF8String] : "");
    fflush(stdout);
  }
}

- (void)performMiniaturize:(id)sender {
  [self miniaturize:sender];
}

- (void)zoom:(id)sender {
  (void)sender;
}

- (void)performZoom:(id)sender {
  [self zoom:sender];
}

@end
