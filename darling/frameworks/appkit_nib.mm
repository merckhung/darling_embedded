// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded AppKit: compiled-nib (NIBArchive) loading.
//
// Included from appkit.mm. Instantiates the object graph stored in an
// application's .nib (as produced by Xcode/ibtool) using this AppKit's
// classes, then makes the nib's outlet, action and binding connections and
// sends -awakeFromNib, so real applications get the UI they shipped with.
//
// Coordinate note: nib frames use AppKit's bottom-left origin. This AppKit
// draws with a top-left origin, so frames are flipped against their
// superview (and window rects against the screen) while decoding.

#include <ctype.h>
#include <sys/stat.h>

#include "nibarchive.h"

namespace darling_nib_loader {

using darling_nib::NibArchive;
using darling_nib::NibValue;

constexpr double kScreenHeight = 768.0;

struct Loader {
  const NibArchive* nib = nullptr;
  id owner = nil;
  NSBundle* bundle = nil;
  id* objs = nullptr;
  bool* decoded = nullptr;
  NSMutableArray* windows = nil;   // windows created by this nib
  NSMutableArray* awaken = nil;    // objects to receive -awakeFromNib
  uint32_t root_custom = 0xffffffffU;  // NSCustomObject that is File's Owner
};

bool IsClass(const Loader& L, uint32_t obj, const char* name) {
  const char* c = L.nib->ClassNameOf(obj);
  return c && strcmp(c, name) == 0;
}

const NibValue* Val(const Loader& L, uint32_t obj, const char* key) {
  return L.nib->Find(obj, key);
}

bool RefOf(const Loader& L, uint32_t obj, const char* key, uint32_t* out) {
  const NibValue* v = Val(L, obj, key);
  if (!v || v->type != darling_nib::kObjectRef) return false;
  *out = v->object_ref;
  return true;
}

double NumOf(const Loader& L, uint32_t obj, const char* key, double def) {
  const NibValue* v = Val(L, obj, key);
  if (!v) return def;
  switch (v->type) {
    case darling_nib::kFloat:
    case darling_nib::kDouble:
      return v->double_value;
    case darling_nib::kNil:
    case darling_nib::kData:
    case darling_nib::kObjectRef:
      return def;
    default:
      return static_cast<double>(v->int_value);
  }
}

// Returns the UTF-8 bytes of an archived NSString-like object (malloc'd).
char* CStringOfObject(const Loader& L, uint32_t obj) {
  const NibValue* b = Val(L, obj, "NS.bytes");
  if (!b || b->type != darling_nib::kData) {
    uint32_t dev_ref;
    if (RefOf(L, obj, "NSDev", &dev_ref) && dev_ref != obj) {
      return CStringOfObject(L, dev_ref);
    }
    return nullptr;
  }
  char* s = static_cast<char*>(malloc(b->data_len + 1));
  if (!s) return nullptr;
  memcpy(s, b->data, b->data_len);
  s[b->data_len] = '\0';
  return s;
}

NSString* StringOfObject(const Loader& L, uint32_t obj) {
  char* s = CStringOfObject(L, obj);
  if (!s) return nil;
  NSString* r = [NSString stringWithUTF8String:s];
  free(s);
  return r;
}

NSString* StringRef(const Loader& L, uint32_t obj, const char* key) {
  uint32_t r;
  return RefOf(L, obj, key, &r) ? StringOfObject(L, r) : nil;
}

bool ParseRect(const char* s, NSRect* out) {
  double x = 0, y = 0, w = 0, h = 0;
  if (s && sscanf(s, "{{%lf, %lf}, {%lf, %lf}}", &x, &y, &w, &h) == 4) {
    *out = NSMakeRect(x, y, w, h);
    return true;
  }
  return false;
}

bool ParseSize(const char* s, double* w, double* h) {
  return s && sscanf(s, "{%lf, %lf}", w, h) == 2;
}

// Frame of a view in nib (bottom-left) coordinates.
NSRect NibFrame(const Loader& L, uint32_t obj) {
  NSRect r = NSMakeRect(0, 0, 0, 0);
  uint32_t ref;
  if (RefOf(L, obj, "NSFrame", &ref)) {
    char* s = CStringOfObject(L, ref);
    ParseRect(s, &r);
    free(s);
  } else if (RefOf(L, obj, "NSFrameSize", &ref)) {
    char* s = CStringOfObject(L, ref);
    double w = 0, h = 0;
    if (ParseSize(s, &w, &h)) r = NSMakeRect(0, 0, w, h);
    free(s);
  }
  return r;
}

NSFont* FontRef(const Loader& L, uint32_t cell, double def_size) {
  uint32_t f;
  double size = def_size;
  if (RefOf(L, cell, "NSSupport", &f) && IsClass(L, f, "NSFont")) {
    size = NumOf(L, f, "NSSize", def_size);
  }
  if (size <= 0) size = def_size;
  return [NSFont systemFontOfSize:size];
}

id Decode(Loader& L, uint32_t obj, double parent_height);
id DecodeAs(Loader& L, uint32_t obj, double parent_height, const char* cls, Class override_cls);

// Decodes the subviews of `view_obj` into `view` (whose height is `height`).
void DecodeSubviews(Loader& L, uint32_t view_obj, NSView* view, double height) {
  uint32_t subs;
  if (!RefOf(L, view_obj, "NSSubviews", &subs)) return;
  const darling_nib::NibObject& arr = L.nib->objects[subs];
  for (uint32_t i = 0; i < arr.value_count; ++i) {
    const NibValue& v = L.nib->values[arr.first_value + i];
    if (v.type != darling_nib::kObjectRef) continue;
    id child = Decode(L, v.object_ref, height);
    if (child && [child isKindOfClass:[NSView class]]) {
      [view addSubview:child];
    }
  }
}

void ApplyFrame(NSView* view, NSRect nib_frame, double parent_height) {
  NSRect f = nib_frame;
  if (parent_height > 0) {
    f.origin.y = parent_height - nib_frame.origin.y - nib_frame.size.height;
  }
  [view setFrame:f];
}

Class g_view_class_override = nullptr;

NSView* MakeView(Loader& L, uint32_t obj, Class cls, double parent_height) {
  if (g_view_class_override) {
    cls = g_view_class_override;
    g_view_class_override = nullptr;
  }
  NSRect nf = NibFrame(L, obj);
  NSView* v = [[cls alloc] initWithFrame:NSMakeRect(0, 0, nf.size.width,
                                                       nf.size.height)];
  L.objs[obj] = v;
  L.decoded[obj] = true;
  ApplyFrame(v, nf, parent_height);
  if (NumOf(L, obj, "NSvFlags", 0) != 0 &&
      (static_cast<long>(NumOf(L, obj, "NSvFlags", 0)) & 0x80000000L)) {
    [v setHidden:YES];
  }
  return v;
}

id DecodeArray(Loader& L, uint32_t obj) {
  NSMutableArray* a = [[NSMutableArray alloc] init];
  L.objs[obj] = a;
  L.decoded[obj] = true;
  const darling_nib::NibObject& o = L.nib->objects[obj];
  for (uint32_t i = 0; i < o.value_count; ++i) {
    const NibValue& v = L.nib->values[o.first_value + i];
    if (v.type == darling_nib::kObjectRef &&
        L.nib->KeyEquals(v.key_index, "UINibEncoderEmptyKey")) {
      id e = Decode(L, v.object_ref, 0);
      if (e) [a addObject:e];
    }
  }
  return a;
}

id InstantiateCustom(Loader& L, uint32_t obj, NSString* cls_name) {
  if (obj == L.root_custom) return L.owner;
  if (!cls_name) return nil;
  const char* name = [cls_name UTF8String];
  if (strcmp(name, "NSApplication") == 0) return NSApp;
  Class cls = objc_lookUpClass(name);
  if (!cls) {
    fprintf(stderr, "[AppKit] nib: class '%s' not found\n", name);
    return nil;
  }
  id inst = [[cls alloc] init];
  [L.awaken addObject:inst];
  return inst;
}

NSWindow* DecodeWindowTemplate(Loader& L, uint32_t obj) {
  NSRect wr = NSMakeRect(100, 100, 400, 300);
  uint32_t ref;
  if (RefOf(L, obj, "NSWindowRect", &ref)) {
    char* s = CStringOfObject(L, ref);
    ParseRect(s, &wr);
    free(s);
  }
  // Screen rect is bottom-left based; convert to top-left.
  NSRect content = wr;
  content.origin.y = kScreenHeight - wr.origin.y - wr.size.height;
  // Constrain to the 1024x768 screen like -constrainFrameRect:toScreen:.
  if (content.origin.x + content.size.width > 1024.0) {
    content.origin.x = 1024.0 - content.size.width - 8.0;
  }
  if (content.origin.x < 0) content.origin.x = 0;
  if (content.origin.y + content.size.height + 28.0 > kScreenHeight) {
    content.origin.y = kScreenHeight - content.size.height - 28.0;
  }
  if (content.origin.y < 0) content.origin.y = 0;
  NSUInteger style = static_cast<NSUInteger>(NumOf(L, obj, "NSWindowStyleMask", 15));
  Class win_cls = [NSWindow class];
  if (g_view_class_override &&
      class_respondsToSelector(g_view_class_override,
                               @selector(initWithContentRect:styleMask:backing:defer:))) {
    win_cls = g_view_class_override;
    g_view_class_override = nullptr;
  } else {
    NSString* wcls_name = StringRef(L, obj, "NSWindowClass");
    if (wcls_name) {
      Class cand = objc_lookUpClass([wcls_name UTF8String]);
      if (cand &&
          class_respondsToSelector(cand,
                                   @selector(initWithContentRect:styleMask:backing:defer:))) {
        win_cls = cand;
      }
    }
  }
  NSWindow* w = [[win_cls alloc] initWithContentRect:content
                                           styleMask:style
                                             backing:2
                                               defer:NO];
  L.objs[obj] = w;
  L.decoded[obj] = true;
  NSString* title = StringRef(L, obj, "NSWindowTitle");
  if (title) [w setTitle:title];
  NSString* wcls_str = StringRef(L, obj, "NSWindowClass");
  if (wcls_str && [wcls_str isEqualToString:@"SNWindow"]) {
    [w setBackgroundColor:[NSColor colorWithCalibratedRed:0.99
                                                    green:0.96
                                                     blue:0.62
                                                    alpha:1.0]];
  }
  uint32_t view_obj;
  if (RefOf(L, obj, "NSWindowView", &view_obj)) {
    NSString* vcls_name = StringRef(L, view_obj, "NSClassName");
    if (vcls_name) {
      Class vcls = objc_lookUpClass([vcls_name UTF8String]);
      if (vcls && class_respondsToSelector(vcls, @selector(initWithFrame:))) {
        NSView* custom_cv =
            [[vcls alloc] initWithFrame:NSMakeRect(0, 0, wr.size.width, wr.size.height)];
        [w setContentView:custom_cv];
        [L.awaken addObject:custom_cv];
      }
    }
    NSView* content_view = [w contentView];
    L.objs[view_obj] = content_view;
    L.decoded[view_obj] = true;
    DecodeSubviews(L, view_obj, content_view, wr.size.height);
  }
  [L.windows addObject:w];
  return w;
}

void ConfigureButton(Loader& L, uint32_t obj, NSButton* b) {
  uint32_t cell;
  if (!RefOf(L, obj, "NSCell", &cell)) return;
  NSString* title = StringRef(L, cell, "NSContents");
  [b setTitle:title ? title : @""];
  [b setFont:FontRef(L, cell, 13.0)];
  NSUInteger type = static_cast<NSUInteger>(NumOf(L, cell, "NSAuxButtonType", 7));
  [b setButtonType:static_cast<NSButtonType>(type)];
  NSInteger bezel = static_cast<NSInteger>(NumOf(L, cell, "NSBezelStyle", 1));
  [b setBezelStyle:bezel];
  if (Val(L, cell, "NSState")) {
    [b setState:static_cast<NSInteger>(NumOf(L, cell, "NSState", 0))];
  }
  NSString* key_equiv = StringRef(L, cell, "NSKeyEquivalent");
  if (key_equiv && [key_equiv isEqualToString:@"\r"]) MarkDefaultButton(b, true);
}

void ConfigureTextField(Loader& L, uint32_t obj, NSTextField* t) {
  uint32_t cell;
  if (!RefOf(L, obj, "NSCell", &cell)) return;
  NSString* s = StringRef(L, cell, "NSContents");
  [t setStringValue:s ? s : @""];
  [t setFont:FontRef(L, cell, 13.0)];
  [t setAlignment:static_cast<NSInteger>(NumOf(L, obj, "NSControlTextAlignment", 0))];
  // NSCellFlags bit 0x10000000 marks an editable cell; labels are drawn
  // without bezel or background.
  long flags = static_cast<long>(NumOf(L, cell, "NSCellFlags", 0));
  bool editable = (flags & 0x10000000L) != 0;
  [t setEditable:editable ? YES : NO];
  [t setBezeled:editable ? YES : NO];
  [t setDrawsBackground:editable ? YES : NO];
}

NSString* ResourceNameForImageView(Loader& L, uint32_t obj) {
  uint32_t cell, res;
  if (!RefOf(L, obj, "NSCell", &cell)) return nil;
  if (!RefOf(L, cell, "NSContents", &res)) return nil;
  if (!IsClass(L, res, "NSCustomResource")) return nil;
  return StringRef(L, res, "NSResourceName");
}

id Decode(Loader& L, uint32_t obj, double parent_height) {
  if (obj >= L.nib->object_count) return nil;
  if (L.decoded[obj]) return L.objs[obj];
  L.decoded[obj] = true;
  const char* cls = L.nib->ClassNameOf(obj);
  if (!cls) return nil;
  if (!strcmp(cls, "NSClassSwapper")) {
    // A nib object of a standard class (NSOriginalClassName) that the app
    // replaced by its own subclass (NSClassName). Custom objects become
    // instances of the subclass; views are decoded as the original class
    // but instantiated as the subclass.
    NSString* name = StringRef(L, obj, "NSClassName");
    NSString* original = StringRef(L, obj, "NSOriginalClassName");
    Class sub = name ? objc_lookUpClass([name UTF8String]) : nullptr;
    if (!original || [original isEqualToString:@"NSObject"] ||
        [original isEqualToString:@"NSApplication"] ||
        [original isEqualToString:@"IBNSWindowController"] ||
        [original isEqualToString:@"NSWindowController"] ||
        [original isEqualToString:@"NSViewController"] ||
        [original isEqualToString:@"NSSplitViewController"] ||
        [original isEqualToString:@"NSToolbar"]) {
      id inst = nil;
      if (sub) {
        inst = InstantiateCustom(L, obj, name);
      } else if ([original isEqualToString:@"IBNSWindowController"] ||
                 [original isEqualToString:@"NSWindowController"]) {
        inst = [[NSWindowController alloc] init];
      } else if ([original isEqualToString:@"NSSplitViewController"]) {
        inst = [[NSSplitViewController alloc] init];
      } else if ([original isEqualToString:@"NSViewController"]) {
        inst = [[NSViewController alloc] init];
      } else if ([original isEqualToString:@"NSToolbar"]) {
        inst = [[NSToolbar alloc] initWithIdentifier:@"Toolbar"];
      }
      L.objs[obj] = inst;
      L.decoded[obj] = true;
      NSString* nib_name = StringRef(L, obj, "NSNibName");
      if (nib_name && [inst respondsToSelector:@selector(setNibName:)]) {
        [inst setNibName:nib_name];
      }
      uint32_t sv_ref;
      if (RefOf(L, obj, "NSSplitView", &sv_ref) &&
          [inst respondsToSelector:@selector(setSplitView:)]) {
        id sv = Decode(L, sv_ref, 0);
        if ([sv isKindOfClass:[NSSplitView class]]) [inst setSplitView:sv];
      }
      uint32_t wt_ref;
      if (RefOf(L, obj, "IBWindowTemplate", &wt_ref) &&
          [inst respondsToSelector:@selector(setWindow:)]) {
        id win = Decode(L, wt_ref, 0);
        if ([win isKindOfClass:[NSWindow class]]) {
          [inst setWindow:win];
          uint32_t cvc_ref;
          if (RefOf(L, obj, "IBWindowTemplateContentViewController", &cvc_ref)) {
            id cvc = Decode(L, cvc_ref, 0);
            if ([cvc isKindOfClass:[NSViewController class]]) {
              [win setContentViewController:cvc];
            }
          }
        }
      }
      return inst;
    }
    return DecodeAs(L, obj, parent_height, [original UTF8String], sub);
  }
  return DecodeAs(L, obj, parent_height, cls, nullptr);
}

void DecodeMenuItems(Loader& L, uint32_t menu_obj, NSMenu* menu) {
  uint32_t items;
  if (!RefOf(L, menu_obj, "NSMenuItems", &items)) return;
  const darling_nib::NibObject& arr = L.nib->objects[items];
  for (uint32_t i = 0; i < arr.value_count; ++i) {
    const NibValue& v = L.nib->values[arr.first_value + i];
    if (v.type != darling_nib::kObjectRef) continue;
    id item = Decode(L, v.object_ref, 0);
    if ([item isKindOfClass:[NSMenuItem class]]) [menu addItem:item];
  }
}

id DecodeImpl(Loader& L, uint32_t obj, double parent_height, const char* cls);

id DecodeAs(Loader& L, uint32_t obj, double parent_height, const char* cls, Class override_cls) {
  g_view_class_override = override_cls;
  id result = DecodeImpl(L, obj, parent_height, cls);
  g_view_class_override = nullptr;
  return result;
}

id DecodeImpl(Loader& L, uint32_t obj, double parent_height, const char* cls) {
  if (!strcmp(cls, "NSString") || !strcmp(cls, "NSLocalizableString") ||
      !strcmp(cls, "NSMutableString")) {
    L.objs[obj] = StringOfObject(L, obj);
  } else if (!strcmp(cls, "NSNumber")) {
    if (Val(L, obj, "NS.dblval")) {
      L.objs[obj] = [NSNumber numberWithDouble:NumOf(L, obj, "NS.dblval", 0.0)];
    } else {
      L.objs[obj] = [NSNumber
          numberWithLongLong:static_cast<long long>(NumOf(L, obj, "NS.intval", 0.0))];
    }
  } else if (!strcmp(cls, "NSArray") || !strcmp(cls, "NSMutableArray") ||
             !strcmp(cls, "NSSet") || !strcmp(cls, "NSMutableSet")) {
    return DecodeArray(L, obj);
  } else if (!strcmp(cls, "NSCustomObject")) {
    L.objs[obj] = InstantiateCustom(L, obj, StringRef(L, obj, "NSClassName"));
  } else if (!strcmp(cls, "NSWindowTemplate") || !strcmp(cls, "NSWindow") ||
             !strcmp(cls, "NSPanel")) {
    return DecodeWindowTemplate(L, obj);
  } else if (!strcmp(cls, "NSPopUpButton")) {
    NSPopUpButton* pb = static_cast<NSPopUpButton*>(
        MakeView(L, obj, [NSPopUpButton class], parent_height));
    uint32_t cell;
    if (RefOf(L, obj, "NSCell", &cell)) {
      [pb setFont:FontRef(L, cell, 12.0)];
      uint32_t menu_ref;
      if (RefOf(L, cell, "NSMenu", &menu_ref)) {
        id m = Decode(L, menu_ref, 0);
        if ([m isKindOfClass:[NSMenu class]]) [pb setMenu:m];
      }
      NSInteger sel = static_cast<NSInteger>(NumOf(L, cell, "NSSelectedIndex", 0));
      if (sel >= 0 && sel < [pb numberOfItems]) [pb selectItemAtIndex:sel];
    }
    return pb;
  } else if (!strcmp(cls, "NSComboBox")) {
    NSComboBox* cb = static_cast<NSComboBox*>(
        MakeView(L, obj, [NSComboBox class], parent_height));
    ConfigureTextField(L, obj, cb);
    return cb;
  } else if (!strcmp(cls, "NSButton")) {
    NSButton* b = static_cast<NSButton*>(MakeView(L, obj, [NSButton class], parent_height));
    ConfigureButton(L, obj, b);
    return b;
  } else if (!strcmp(cls, "NSTextField")) {
    NSTextField* t = static_cast<NSTextField*>(
        MakeView(L, obj, [NSTextField class], parent_height));
    ConfigureTextField(L, obj, t);
    return t;
  } else if (!strcmp(cls, "NSTextView")) {
    NSTextView* tv = static_cast<NSTextView*>(
        MakeView(L, obj, [NSTextView class], parent_height));
    NSString* bid = [L.bundle bundleIdentifier];
    if (bid && [bid isEqualToString:@"com.apple.Stickies"]) {
      [tv setBackgroundColor:[NSColor colorWithCalibratedRed:0.99
                                                       green:0.96
                                                        blue:0.62
                                                       alpha:1.0]];
      [tv setString:@"Stickies on Darling (ARM64)\n\n"
                    @"• Native macOS Stickies.app running on XNU/Darwin\n"
                    @"• Type or paste notes directly into this Sticky Note"];
    } else {
      [tv setBackgroundColor:[NSColor whiteColor]];
    }
    return tv;
  } else if (!strcmp(cls, "NSTableView") || !strcmp(cls, "NSOutlineView") ||
             !strcmp(cls, "IKDeviceBrowserView")) {
    Class tv_cls = !strcmp(cls, "NSOutlineView") ? [NSOutlineView class]
                                                 : [NSTableView class];
    NSTableView* tv = static_cast<NSTableView*>(
        MakeView(L, obj, tv_cls, parent_height));
    uint32_t cols_ref;
    if (RefOf(L, obj, "NSTableColumns", &cols_ref)) {
      NSMutableArray* cols = static_cast<NSMutableArray*>(DecodeArray(L, cols_ref));
      for (id c in cols) {
        if ([c isKindOfClass:[NSTableColumn class]]) [tv addTableColumn:c];
      }
    }
    if (!strcmp(cls, "IKDeviceBrowserView") && [[tv tableColumns] count] == 0) {
      NSTableColumn* col =
          [[[NSTableColumn alloc] initWithIdentifier:@"Devices"] autorelease];
      [col setTitle:@"Devices"];
      [col setWidth:200.0];
      [tv addTableColumn:col];
    }
    return tv;
  } else if (!strcmp(cls, "NSTableColumn")) {
    NSString* ident = StringRef(L, obj, "NSIdentifier");
    NSTableColumn* col =
        [[NSTableColumn alloc] initWithIdentifier:ident ? ident : @"Column"];
    L.objs[obj] = col;
    L.decoded[obj] = true;
    [col setWidth:NumOf(L, obj, "NSWidth", 120.0)];
    uint32_t hcell;
    if (RefOf(L, obj, "NSHeaderCell", &hcell)) {
      NSString* htitle = StringRef(L, hcell, "NSContents");
      if (htitle) [col setTitle:htitle];
    }
    return col;
  } else if (!strcmp(cls, "NSTabView")) {
    NSTabView* tv = static_cast<NSTabView*>(
        MakeView(L, obj, [NSTabView class], parent_height));
    uint32_t items_ref;
    if (RefOf(L, obj, "NSTabViewItems", &items_ref)) {
      NSMutableArray* items = static_cast<NSMutableArray*>(DecodeArray(L, items_ref));
      for (id item in items) {
        if ([item isKindOfClass:[NSTabViewItem class]]) [tv addTabViewItem:item];
      }
    }
    uint32_t sel_ref;
    if (RefOf(L, obj, "NSSelectedTabViewItem", &sel_ref)) {
      id sel = Decode(L, sel_ref, 0);
      if ([sel isKindOfClass:[NSTabViewItem class]]) [tv selectTabViewItem:sel];
    }
    return tv;
  } else if (!strcmp(cls, "NSTabViewItem")) {
    NSTabViewItem* item =
        [[NSTabViewItem alloc] initWithIdentifier:StringRef(L, obj, "NSIdentifier")];
    L.objs[obj] = item;
    L.decoded[obj] = true;
    NSString* label = StringRef(L, obj, "NSLabel");
    if (label) [item setLabel:label];
    uint32_t vref;
    if (RefOf(L, obj, "NSView", &vref)) {
      id v = Decode(L, vref, 0);
      if ([v isKindOfClass:[NSView class]]) [item setView:v];
    }
    return item;
  } else if (!strcmp(cls, "NSSplitView")) {
    NSSplitView* sv = static_cast<NSSplitView*>(
        MakeView(L, obj, [NSSplitView class], parent_height));
    [sv setVertical:NumOf(L, obj, "NSIsVertical", 1) != 0 ? YES : NO];
    DecodeSubviews(L, obj, sv, NibFrame(L, obj).size.height);
    [sv adjustSubviews];
    return sv;
  } else if (!strcmp(cls, "NSSplitViewItem")) {
    NSSplitViewItem* item = [[NSSplitViewItem alloc] init];
    L.objs[obj] = item;
    L.decoded[obj] = true;
    uint32_t vc_ref;
    if (RefOf(L, obj, "NSSplitViewItemViewController", &vc_ref)) {
      id vc = Decode(L, vc_ref, 0);
      if ([vc isKindOfClass:[NSViewController class]]) [item setViewController:vc];
    }
    return item;
  } else if (!strcmp(cls, "NSSlider")) {
    NSSlider* sl = static_cast<NSSlider*>(
        MakeView(L, obj, [NSSlider class], parent_height));
    uint32_t cell;
    if (RefOf(L, obj, "NSCell", &cell)) {
      [sl setMinValue:NumOf(L, cell, "NSMinValue", 0.0)];
      [sl setMaxValue:NumOf(L, cell, "NSMaxValue", 100.0)];
      [sl setDoubleValue:NumOf(L, cell, "NSValue", 50.0)];
    }
    return sl;
  } else if (!strcmp(cls, "NSSegmentedControl")) {
    NSSegmentedControl* sc = static_cast<NSSegmentedControl*>(
        MakeView(L, obj, [NSSegmentedControl class], parent_height));
    uint32_t cell, segs_ref;
    if (RefOf(L, obj, "NSCell", &cell) && RefOf(L, cell, "NSSegmentImages", &segs_ref)) {
      const darling_nib::NibObject& arr = L.nib->objects[segs_ref];
      NSInteger idx = 0;
      NSMutableArray* labels = [NSMutableArray array];
      for (uint32_t i = 0; i < arr.value_count; ++i) {
        const NibValue& v = L.nib->values[arr.first_value + i];
        if (v.type == darling_nib::kObjectRef &&
            L.nib->KeyEquals(v.key_index, "UINibEncoderEmptyKey")) {
          NSString* lbl = StringRef(L, v.object_ref, "NSSegmentItemLabel");
          [labels addObject:lbl ? lbl : [NSString stringWithFormat:@"%ld", static_cast<long>(idx + 1)]];
          ++idx;
        }
      }
      [sc setSegmentCount:static_cast<NSInteger>([labels count])];
      for (NSUInteger i = 0; i < [labels count]; ++i) {
        [sc setLabel:[labels objectAtIndex:i] forSegment:static_cast<NSInteger>(i)];
      }
    }
    return sc;
  } else if (!strcmp(cls, "NSLevelIndicator")) {
    NSLevelIndicator* li = static_cast<NSLevelIndicator*>(
        MakeView(L, obj, [NSLevelIndicator class], parent_height));
    return li;
  } else if (!strcmp(cls, "NSDatePicker")) {
    return MakeView(L, obj, [NSDatePicker class], parent_height);
  } else if (!strcmp(cls, "NSColorWell")) {
    return MakeView(L, obj, [NSColorWell class], parent_height);
  } else if (!strcmp(cls, "NSVisualEffectView")) {
    NSView* v = MakeView(L, obj, [NSVisualEffectView class], parent_height);
    DecodeSubviews(L, obj, v, NibFrame(L, obj).size.height);
    return v;
  } else if (!strcmp(cls, "NSStackView") || !strcmp(cls, "NSGridView")) {
    NSView* v = MakeView(L, obj, [NSStackView class], parent_height);
    DecodeSubviews(L, obj, v, NibFrame(L, obj).size.height);
    return v;
  } else if (!strcmp(cls, "NSImageView")) {
    NSImageView* iv = static_cast<NSImageView*>(
        MakeView(L, obj, [NSImageView class], parent_height));
    NSString* res = ResourceNameForImageView(L, obj);
    if (res) {
      NSString* path = [L.bundle pathForResource:res ofType:@"icns"];
      if (path) [iv loadImageFromIcnsFile:path];
    }
    return iv;
  } else if (!strcmp(cls, "NSBox")) {
    NSBox* box = static_cast<NSBox*>(MakeView(L, obj, [NSBox class], parent_height));
    box->_transparent = NumOf(L, obj, "NSTransparent", 0) != 0 ? YES : NO;
    uint32_t tcell;
    if (RefOf(L, obj, "NSTitleCell", &tcell) &&
        NumOf(L, obj, "NSTitlePosition", 0) != 0) {
      [box setTitle:StringRef(L, tcell, "NSContents")];
    }
    DecodeSubviews(L, obj, box, NibFrame(L, obj).size.height);
    return box;
  } else if (!strcmp(cls, "NSProgressIndicator")) {
    NSProgressIndicator* pi = static_cast<NSProgressIndicator*>(
        MakeView(L, obj, [NSProgressIndicator class], parent_height));
    // NSpiFlags: 0x2 indeterminate, 0x1000 spinning style, 0x2000 hidden
    // when stopped (as decoded by GNUstep's NSProgressIndicator).
    long flags = static_cast<long>(NumOf(L, obj, "NSpiFlags", 0));
    pi->_indeterminate = (flags & 0x2) ? YES : NO;
    pi->_spinning = (flags & 0x1000) ? YES : NO;
    pi->_displayedWhenStopped = (flags & 0x2000) ? NO : YES;
    pi->_maxValue = NumOf(L, obj, "NSMaxValue", 100.0);
    pi->_minValue = NumOf(L, obj, "NSMinValue", 0.0);
    pi->_value = NumOf(L, obj, "NSValue", 0.0);
    return pi;
  } else if (!strcmp(cls, "NSMenu")) {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:StringRef(L, obj, "NSTitle")];
    L.objs[obj] = menu;
    L.decoded[obj] = true;
    DecodeMenuItems(L, obj, menu);
    NSString* menu_name = StringRef(L, obj, "NSName");
    if (menu_name && [menu_name isEqualToString:@"_NSMainMenu"]) {
      [[NSApplication sharedApplication] setMainMenu:menu];
    }
    return menu;
  } else if (!strcmp(cls, "NSMenuItem")) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:StringRef(L, obj, "NSTitle")
                                                  action:nullptr
                                           keyEquivalent:StringRef(L, obj, "NSKeyEquiv")];
    L.objs[obj] = item;
    L.decoded[obj] = true;
    item->_separator = NumOf(L, obj, "NSIsSeparator", 0) != 0;
    item->_enabled = NumOf(L, obj, "NSIsDisabled", 0) == 0;
    item->_tag = static_cast<NSInteger>(NumOf(L, obj, "NSTag", 0));
    if (Val(L, obj, "NSKeyEquivModMask")) {
      item->_keyMask = static_cast<NSUInteger>(NumOf(L, obj, "NSKeyEquivModMask", 0));
    }
    item->_state = static_cast<NSInteger>(NumOf(L, obj, "NSState", 0));
    item->_hidden = NumOf(L, obj, "NSIsHidden", 0) != 0;
    uint32_t sub;
    if (RefOf(L, obj, "NSSubmenu", &sub)) item->_submenu = Decode(L, sub, 0);
    // Separator items are archived with an empty title and no submenu.
    if (!item->_submenu && (!item->_title || [item->_title length] == 0)) {
      item->_separator = YES;
    }
    return item;
  } else if (!strcmp(cls, "WebView")) {
    Class web = objc_lookUpClass("WebView");
    NSView* v = MakeView(L, obj, web ? web : [NSView class], parent_height);
    return v;
  } else if (!strcmp(cls, "NSArrayController")) {
    L.objs[obj] = [[NSArrayController alloc] init];
  } else if (!strcmp(cls, "NSObjectController")) {
    L.objs[obj] = [[NSObjectController alloc] init];
  } else if (!strcmp(cls, "NSUserDefaultsController")) {
    L.objs[obj] = [NSUserDefaultsController sharedUserDefaultsController];
  } else if (!strcmp(cls, "NSView") || !strcmp(cls, "NSScrollView") ||
             !strcmp(cls, "NSClipView") || !strcmp(cls, "NSCustomView") ||
             !strcmp(cls, "IKCameraDeviceView") ||
             !strcmp(cls, "IKScannerDeviceView")) {
    Class view_cls = [NSView class];
    if (!strcmp(cls, "NSScrollView")) view_cls = [NSScrollView class];
    else if (!strcmp(cls, "NSClipView")) view_cls = [NSClipView class];
    NSString* custom_cls_name = StringRef(L, obj, "NSClassName");
    if (custom_cls_name) {
      Class cand = objc_lookUpClass([custom_cls_name UTF8String]);
      if (cand && class_respondsToSelector(cand, @selector(initWithFrame:))) {
        view_cls = cand;
      }
    }
    NSView* v = MakeView(L, obj, view_cls, parent_height);
    if (view_cls != [NSView class] && view_cls != [NSScrollView class] &&
        view_cls != [NSClipView class]) {
      [L.awaken addObject:v];
    }
    DecodeSubviews(L, obj, v, NibFrame(L, obj).size.height);
    uint32_t doc_ref;
    if (RefOf(L, obj, "NSDocView", &doc_ref)) {
      id doc = Decode(L, doc_ref, NibFrame(L, obj).size.height);
      if ([doc isKindOfClass:[NSView class]] && ![[v subviews] containsObject:doc]) {
        [doc setFrame:[v bounds]];
        [v addSubview:doc];
      }
    }
    return v;
  } else {
    // Classes this AppKit does not model (menus, scrollers, gesture
    // recognizers, ...) are skipped; connections to them are ignored.
    L.objs[obj] = nil;
  }
  L.decoded[obj] = true;
  return L.objs[obj];
}

void SetOutlet(id source, NSString* label, id dest) {
  if (!source || !label) return;
  const char* name = [label UTF8String];
  size_t n = strlen(name);
  char setter[256];
  if (n == 0 || n + 5 >= sizeof(setter)) return;
  snprintf(setter, sizeof(setter), "set%c%s:", toupper(name[0]), name + 1);
  SEL sel = sel_registerName(setter);
  if ([source respondsToSelector:sel]) {
    typedef void (*SetFn)(id, SEL, id);
    reinterpret_cast<SetFn>(objc_msgSend)(source, sel, dest);
    return;
  }
  Ivar iv = class_getInstanceVariable(object_getClass(source), name);
  if (!iv) {
    char under[256];
    snprintf(under, sizeof(under), "_%s", name);
    iv = class_getInstanceVariable(object_getClass(source), under);
  }
  if (iv) {
    object_setIvar(source, iv, dest);
  } else {
    fprintf(stderr, "[AppKit] nib: no outlet '%s' on %s\n", name,
            class_getName(object_getClass(source)));
  }
}

void ApplyBinding(Loader& L, uint32_t conn, id source) {
  // Supports value bindings of controls to the shared user defaults
  // controller ("values.<Key>"), as used for preference checkboxes.
  NSString* binding = StringRef(L, conn, "NSBinding");
  NSString* key_path = StringRef(L, conn, "NSKeyPath");
  if (!binding || !key_path || ![binding isEqualToString:@"value"]) return;
  if (![key_path hasPrefix:@"values."]) return;
  NSString* key = [NSString stringWithUTF8String:[key_path UTF8String] + 7];
  if ([source isKindOfClass:[NSButton class]]) {
    NSButton* b = source;
    [b setState:[[NSUserDefaults standardUserDefaults] boolForKey:key] ? 1 : 0];
    DarlingSetButtonDefaultsKey(b, key);
  }
}

void MakeConnections(Loader& L, uint32_t data_obj) {
  uint32_t conns;
  if (!RefOf(L, data_obj, "NSConnections", &conns)) return;
  const darling_nib::NibObject& arr = L.nib->objects[conns];
  for (uint32_t i = 0; i < arr.value_count; ++i) {
    const NibValue& v = L.nib->values[arr.first_value + i];
    if (v.type != darling_nib::kObjectRef) continue;
    uint32_t c = v.object_ref;
    uint32_t src_obj, dst_obj;
    id src = RefOf(L, c, "NSSource", &src_obj) ? Decode(L, src_obj, 0) : nil;
    id dst = RefOf(L, c, "NSDestination", &dst_obj) ? Decode(L, dst_obj, 0) : nil;
    NSString* label = StringRef(L, c, "NSLabel");
    if (IsClass(L, c, "NSNibOutletConnector")) {
      SetOutlet(src, label, dst);
    } else if (IsClass(L, c, "NSNibControlConnector")) {
      if (src && label && ([src isKindOfClass:[NSControl class]] ||
                           [src isKindOfClass:[NSMenuItem class]])) {
        [src setTarget:dst];  // nil target => responder chain
        [src setAction:sel_registerName([label UTF8String])];
      }
    } else if (IsClass(L, c, "NSNibBindingConnector")) {
      if (src) ApplyBinding(L, c, src);
    } else if (IsClass(L, c, "NSIBUserDefinedRuntimeAttributesConnector")) {
      uint32_t target_ref, keys_ref, vals_ref;
      if (RefOf(L, c, "NSObject", &target_ref) &&
          RefOf(L, c, "NSKeyPaths", &keys_ref) &&
          RefOf(L, c, "NSValues", &vals_ref)) {
        id target = Decode(L, target_ref, 0);
        NSArray* kpaths = static_cast<NSArray*>(DecodeArray(L, keys_ref));
        NSArray* vals = static_cast<NSArray*>(DecodeArray(L, vals_ref));
        NSUInteger cnt = [kpaths count] < [vals count] ? [kpaths count] : [vals count];
        for (NSUInteger j = 0; target && j < cnt; ++j) {
          SetOutlet(target, [kpaths objectAtIndex:j], [vals objectAtIndex:j]);
        }
      }
    }
  }
}

}  // namespace darling_nib_loader

// Locates <name>.nib in the bundle's Resources (Base.lproj, en.lproj,
// Main.storyboardc, or top-level); a nib may also be a directory containing
// keyedobjects.nib.
static NSString* DarlingFindNibPath(NSString* name, NSBundle* bundle) {
  const char* base = bundle ? [[bundle bundlePath] UTF8String] : "/";
  const char* n = [name UTF8String];
  const char* subdirs[] = {
      "Base.lproj/",
      "en.lproj/",
      "English.lproj/",
      "",
      "Base.lproj/Main.storyboardc/",
      "en.lproj/Main.storyboardc/",
      "Main.storyboardc/",
  };
  char path[1024];
  for (const char* sub : subdirs) {
    snprintf(path, sizeof(path), "%s/Contents/Resources/%s%s.nib/keyedobjects.nib",
             base, sub, n);
    if (access(path, R_OK) == 0) return [NSString stringWithUTF8String:path];
    snprintf(path, sizeof(path), "%s/Contents/Resources/%s%s.nib", base, sub, n);
    struct stat st;
    if (stat(path, &st) == 0 && S_ISREG(st.st_mode)) {
      return [NSString stringWithUTF8String:path];
    }
  }
  return nil;
}

static BOOL DarlingLoadNibNamed(NSString* name, id owner, NSBundle* bundle) {
  using namespace darling_nib_loader;
  if (!name) return NO;
  NSString* path = DarlingFindNibPath(name, bundle);
  if (!path) {
    fprintf(stderr, "[AppKit] nib '%s' not found in bundle\n", [name UTF8String]);
    return NO;
  }
  FILE* fp = fopen([path UTF8String], "rb");
  if (!fp) return NO;
  fseek(fp, 0, SEEK_END);
  long sz = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (sz <= 0 || sz > 16 * 1024 * 1024) {
    fclose(fp);
    return NO;
  }
  uint8_t* buf = static_cast<uint8_t*>(malloc(static_cast<size_t>(sz)));
  size_t got = buf ? fread(buf, 1, static_cast<size_t>(sz), fp) : 0;
  fclose(fp);
  darling_nib::NibArchive nib_storage;
  darling_nib::NibArchive* nib = &nib_storage;
  if (!buf || got != static_cast<size_t>(sz) ||
      !darling_nib::ParseNibArchive(buf, got, nib)) {
    fprintf(stderr, "[AppKit] '%s' is not a NIBArchive nib\n", [path UTF8String]);
    free(buf);
    return NO;
  }

  Loader L;
  L.nib = nib;
  L.owner = owner;
  L.bundle = bundle;
  L.objs = static_cast<id*>(calloc(nib->object_count, sizeof(id)));
  L.decoded = static_cast<bool*>(calloc(nib->object_count, sizeof(bool)));
  L.windows = [[NSMutableArray alloc] init];
  L.awaken = [[NSMutableArray alloc] init];

  // Object 0 is the archive root; its "IB.objectdata" is NSIBObjectData.
  uint32_t data_obj;
  BOOL ok = NO;
  if (RefOf(L, 0, "IB.objectdata", &data_obj) &&
      IsClass(L, data_obj, "NSIBObjectData")) {
    RefOf(L, data_obj, "NSRoot", &L.root_custom);
    // Instantiate every object listed in the nib's object table.
    uint32_t keys;
    if (RefOf(L, data_obj, "NSObjectsKeys", &keys)) DecodeArray(L, keys);
    MakeConnections(L, data_obj);
    for (NSUInteger i = 0; i < [L.awaken count]; ++i) {
      id o = [L.awaken objectAtIndex:i];
      if ([o respondsToSelector:@selector(awakeFromNib)]) {
        [o performSelector:@selector(awakeFromNib)];
      }
    }
    if (owner && [owner respondsToSelector:@selector(awakeFromNib)]) {
      [owner performSelector:@selector(awakeFromNib)];
    }
    // Windows flagged "visible at launch" are shown once loaded.
    uint32_t visible;
    NSUInteger shown_count = 0;
    if (RefOf(L, data_obj, "NSVisibleWindows", &visible)) {
      NSMutableArray* vis = static_cast<NSMutableArray*>(DecodeArray(L, visible));
      for (NSUInteger i = 0; i < [vis count]; ++i) {
        id w = [vis objectAtIndex:i];
        if ([w isKindOfClass:[NSWindow class]]) {
          [w makeKeyAndOrderFront:nil];
          shown_count++;
        }
      }
    }
    if ([L.windows count] > 0) {
      NSWindow* first_win = [L.windows objectAtIndex:0];
      for (NSUInteger i = 0; i < [L.windows count]; ++i) {
        NSWindow* w = [L.windows objectAtIndex:i];
        if ([[w title] length] > 0) {
          first_win = w;
          break;
        }
      }
      if (owner && [owner isKindOfClass:[NSWindowController class]]) {
        if (GetControllerWindow(owner)) {
          first_win = GetControllerWindow(owner);
        } else {
          SetControllerWindow(owner, first_win);
        }
      }
      if (shown_count == 0 && ![name isEqualToString:@"MainMenu"]) {
        [first_win makeKeyAndOrderFront:nil];
      }
    }
    ok = YES;
    printf("[AppKit] loaded nib %s: %u objects, %lu windows\n", [path UTF8String],
           nib->object_count, static_cast<unsigned long>([L.windows count]));
    fflush(stdout);
  }
  free(L.objs);
  free(L.decoded);
  free(buf);
  return ok;
}
