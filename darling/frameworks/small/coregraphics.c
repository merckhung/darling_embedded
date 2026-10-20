// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded CoreGraphics / SkyLight / ColorSync / QuartzCore C functions
// and constants used by macOS ARM64 applications.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef double CGFloat;
typedef const void* CGColorRef;

typedef struct {
  CGFloat x;
  CGFloat y;
} CGPoint;

typedef struct {
  CGFloat width;
  CGFloat height;
} CGSize;

typedef struct {
  CGPoint origin;
  CGSize size;
} CGRect;

typedef struct {
  CGFloat a, b, c, d, tx, ty;
} CGAffineTransform;

const CGRect CGRectZero = {{0.0, 0.0}, {0.0, 0.0}};
const CGRect CGRectNull = {{1e30, 1e30}, {0.0, 0.0}};
const CGPoint CGPointZero = {0.0, 0.0};
const CGSize CGSizeZero = {0.0, 0.0};
const CGAffineTransform CGAffineTransformIdentity = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};

const void* kCGColorSpaceSRGB = "kCGColorSpaceSRGB";
const void* kCGColorSpaceGenericRGB = "kCGColorSpaceGenericRGB";
const void* kCGColorSpaceGenericGray = "kCGColorSpaceGenericGray";
const void* kCGColorSpaceDisplayP3 = "kCGColorSpaceDisplayP3";
const void* kCGColorWhite = "kCGColorWhite";
const void* kCGColorBlack = "kCGColorBlack";
const void* kCGColorClear = "kCGColorClear";

const void* kCAFilterLinear = "linear";
const void* kCAFilterNearest = "nearest";
const void* kCAFilterTrilinear = "trilinear";
const void* kCAGravityCenter = "center";
const void* kCAGravityResize = "resize";
const void* kCAGravityResizeAspect = "resizeAspect";
const void* kCAGravityResizeAspectFill = "resizeAspectFill";
const void* kCATransactionDisableActions = "kCATransactionDisableActions";

static const CGFloat kDefaultColor[4] = {0.20, 0.52, 0.90, 1.0};
static int g_dummy_colorspace = 1;
static int g_dummy_color_prof = 2;
static int g_dummy_color_xform = 3;

typedef struct {
  size_t width;
  size_t height;
  size_t bitsPerComponent;
  size_t bytesPerRow;
  uint8_t* data;
  int owns_data;
} DarlingCGImage;

const CGFloat* CGColorGetComponents(CGColorRef color) {
  return color ? (const CGFloat*)color : kDefaultColor;
}

CGFloat CGColorGetAlpha(CGColorRef color) {
  return color ? ((const CGFloat*)color)[3] : 1.0;
}

size_t CGColorGetNumberOfComponents(CGColorRef color) {
  return color ? 4 : 0;
}

CGColorRef CGColorRetain(CGColorRef color) { return color; }
void CGColorRelease(CGColorRef color) { (void)color; }

CGColorRef CGColorCreate(const void* space, const CGFloat* components) {
  (void)space;
  CGFloat* c = (CGFloat*)malloc(4 * sizeof(CGFloat));
  if (!c) return kDefaultColor;
  if (components) {
    c[0] = components[0];
    c[1] = components[1];
    c[2] = components[2];
    c[3] = components[3];
  } else {
    c[0] = c[1] = c[2] = 0.0;
    c[3] = 1.0;
  }
  return c;
}

CGColorRef CGColorCreateGenericRGB(CGFloat red, CGFloat green, CGFloat blue,
                                   CGFloat alpha) {
  CGFloat comp[4] = {red, green, blue, alpha};
  return CGColorCreate(NULL, comp);
}

CGColorRef CGColorCreateGenericGray(CGFloat gray, CGFloat alpha) {
  CGFloat comp[4] = {gray, gray, gray, alpha};
  return CGColorCreate(NULL, comp);
}

CGColorRef CGColorGetConstantColor(const void* name) {
  (void)name;
  return kDefaultColor;
}

const void* CGColorGetColorSpace(CGColorRef color) {
  (void)color;
  return &g_dummy_colorspace;
}

void* CGColorSpaceCreateDeviceRGB(void) { return &g_dummy_colorspace; }
void* CGColorSpaceCreateDeviceGray(void) { return &g_dummy_colorspace; }
void* CGColorSpaceCreateWithName(const void* name) {
  (void)name;
  return &g_dummy_colorspace;
}
void* CGColorSpaceCreateWithICCData(const void* data) {
  (void)data;
  return &g_dummy_colorspace;
}
void* CGColorSpaceCopyName(const void* space) {
  (void)space;
  return (void*)kCGColorSpaceSRGB;
}
const void* CGColorSpaceCopyICCData(const void* space) {
  (void)space;
  return NULL;
}
size_t CGColorSpaceGetNumberOfComponents(const void* space) {
  (void)space;
  return 3;
}
void* CGColorSpaceRetain(void* space) { return space; }
void CGColorSpaceRelease(void* space) { (void)space; }

// Bitmap Context & Image support (used by Digital Color Meter & AppKit apps)
void* CGBitmapContextCreate(void* data, size_t width, size_t height,
                            size_t bitsPerComponent, size_t bytesPerRow,
                            void* space, uint32_t bitmapInfo) {
  (void)space;
  (void)bitmapInfo;
  DarlingCGImage* ctx = (DarlingCGImage*)calloc(1, sizeof(DarlingCGImage));
  if (!ctx) return NULL;
  if (width == 0) width = 64;
  if (height == 0) height = 64;
  if (bitsPerComponent == 0) bitsPerComponent = 8;
  if (bytesPerRow == 0) bytesPerRow = width * 4;
  ctx->width = width;
  ctx->height = height;
  ctx->bitsPerComponent = bitsPerComponent;
  ctx->bytesPerRow = bytesPerRow;
  if (data) {
    ctx->data = (uint8_t*)data;
    ctx->owns_data = 0;
  } else {
    ctx->data = (uint8_t*)calloc(height, bytesPerRow);
    ctx->owns_data = 1;
  }
  if (ctx->data) {
    // Populate with a pleasant Aqua blue-teal gradient sample so color meters
    // show meaningful non-zero RGB values.
    for (size_t y = 0; y < height; ++y) {
      uint8_t* row = ctx->data + y * bytesPerRow;
      for (size_t x = 0; x < width; ++x) {
        if (x * 4 + 3 < bytesPerRow) {
          row[x * 4 + 0] = (uint8_t)(48 + (x * 160) / (width ? width : 1));
          row[x * 4 + 1] = (uint8_t)(128 + (y * 100) / (height ? height : 1));
          row[x * 4 + 2] = 224;
          row[x * 4 + 3] = 255;
        }
      }
    }
  }
  return ctx;
}

void* CGBitmapContextGetData(void* context) {
  DarlingCGImage* ctx = (DarlingCGImage*)context;
  return ctx ? ctx->data : NULL;
}
size_t CGBitmapContextGetWidth(void* context) {
  DarlingCGImage* ctx = (DarlingCGImage*)context;
  return ctx ? ctx->width : 0;
}
size_t CGBitmapContextGetHeight(void* context) {
  DarlingCGImage* ctx = (DarlingCGImage*)context;
  return ctx ? ctx->height : 0;
}
size_t CGBitmapContextGetBytesPerRow(void* context) {
  DarlingCGImage* ctx = (DarlingCGImage*)context;
  return ctx ? ctx->bytesPerRow : 0;
}
void* CGBitmapContextCreateImage(void* context) {
  return CGBitmapContextCreate(NULL,
                               CGBitmapContextGetWidth(context),
                               CGBitmapContextGetHeight(context), 8, 0, NULL, 0);
}

void* CGContextRetain(void* c) { return c; }
void CGContextRelease(void* c) { (void)c; }
void CGContextSaveGState(void* c) { (void)c; }
void CGContextRestoreGState(void* c) { (void)c; }
void CGContextScaleCTM(void* c, CGFloat sx, CGFloat sy) {
  (void)c; (void)sx; (void)sy;
}
void CGContextTranslateCTM(void* c, CGFloat tx, CGFloat ty) {
  (void)c; (void)tx; (void)ty;
}
void CGContextRotateCTM(void* c, CGFloat angle) { (void)c; (void)angle; }
void CGContextConcatCTM(void* c, CGAffineTransform transform) {
  (void)c; (void)transform;
}
void CGContextSetFillColorWithColor(void* c, CGColorRef color) {
  (void)c; (void)color;
}
void CGContextSetStrokeColorWithColor(void* c, CGColorRef color) {
  (void)c; (void)color;
}
void CGContextSetRGBFillColor(void* c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
  (void)c; (void)r; (void)g; (void)b; (void)a;
}
void CGContextSetRGBStrokeColor(void* c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
  (void)c; (void)r; (void)g; (void)b; (void)a;
}
void CGContextSetGrayFillColor(void* c, CGFloat gray, CGFloat a) {
  (void)c; (void)gray; (void)a;
}
void CGContextSetAlpha(void* c, CGFloat a) { (void)c; (void)a; }
void CGContextSetLineWidth(void* c, CGFloat w) { (void)c; (void)w; }
void CGContextSetBlendMode(void* c, int32_t mode) { (void)c; (void)mode; }
void CGContextSetInterpolationQuality(void* c, int32_t q) { (void)c; (void)q; }
void CGContextSetShouldAntialias(void* c, int b) { (void)c; (void)b; }
void CGContextFillRect(void* c, CGRect rect) { (void)c; (void)rect; }
void CGContextStrokeRect(void* c, CGRect rect) { (void)c; (void)rect; }
void CGContextStrokeRectWithWidth(void* c, CGRect rect, CGFloat w) {
  (void)c; (void)rect; (void)w;
}
void CGContextClearRect(void* c, CGRect rect) { (void)c; (void)rect; }
void CGContextClipToRect(void* c, CGRect rect) { (void)c; (void)rect; }
void CGContextBeginPath(void* c) { (void)c; }
void CGContextClosePath(void* c) { (void)c; }
void CGContextMoveToPoint(void* c, CGFloat x, CGFloat y) {
  (void)c; (void)x; (void)y;
}
void CGContextAddLineToPoint(void* c, CGFloat x, CGFloat y) {
  (void)c; (void)x; (void)y;
}
void CGContextAddRect(void* c, CGRect rect) { (void)c; (void)rect; }
void CGContextAddEllipseInRect(void* c, CGRect rect) { (void)c; (void)rect; }
void CGContextAddArc(void* c, CGFloat x, CGFloat y, CGFloat r, CGFloat s,
                     CGFloat e, int cw) {
  (void)c; (void)x; (void)y; (void)r; (void)s; (void)e; (void)cw;
}
void CGContextAddPath(void* c, const void* path) { (void)c; (void)path; }
void CGContextFillPath(void* c) { (void)c; }
void CGContextStrokePath(void* c) { (void)c; }
void CGContextDrawPath(void* c, int32_t mode) { (void)c; (void)mode; }
void CGContextClip(void* c) { (void)c; }
void CGContextFlush(void* c) { (void)c; }

void CGContextDrawImage(void* c, CGRect rect, void* image) {
  (void)rect;
  DarlingCGImage* dst = (DarlingCGImage*)c;
  DarlingCGImage* src = (DarlingCGImage*)image;
  if (!dst || !dst->data || !src || !src->data) return;
  size_t rows = dst->height < src->height ? dst->height : src->height;
  size_t bpr = dst->bytesPerRow < src->bytesPerRow ? dst->bytesPerRow : src->bytesPerRow;
  for (size_t y = 0; y < rows; ++y) {
    memcpy(dst->data + y * dst->bytesPerRow, src->data + y * src->bytesPerRow, bpr);
  }
}

size_t CGImageGetWidth(void* image) {
  DarlingCGImage* img = (DarlingCGImage*)image;
  return img ? img->width : 64;
}
size_t CGImageGetHeight(void* image) {
  DarlingCGImage* img = (DarlingCGImage*)image;
  return img ? img->height : 64;
}
size_t CGImageGetBitsPerComponent(void* image) {
  DarlingCGImage* img = (DarlingCGImage*)image;
  return img ? img->bitsPerComponent : 8;
}
size_t CGImageGetBitsPerPixel(void* image) {
  (void)image;
  return 32;
}
size_t CGImageGetBytesPerRow(void* image) {
  DarlingCGImage* img = (DarlingCGImage*)image;
  return img ? img->bytesPerRow : 256;
}
void* CGImageGetColorSpace(void* image) {
  (void)image;
  return &g_dummy_colorspace;
}
void* CGImageRetain(void* image) { return image; }
void CGImageRelease(void* image) { (void)image; }
void* CGImageCreateWithImageInRect(void* image, CGRect rect) {
  (void)rect;
  return image;
}

// Geometry helpers
int CGRectEqualToRect(CGRect r1, CGRect r2) {
  return r1.origin.x == r2.origin.x && r1.origin.y == r2.origin.y &&
         r1.size.width == r2.size.width && r1.size.height == r2.size.height;
}
int CGPointEqualToPoint(CGPoint p1, CGPoint p2) {
  return p1.x == p2.x && p1.y == p2.y;
}
int CGSizeEqualToSize(CGSize s1, CGSize s2) {
  return s1.width == s2.width && s1.height == s2.height;
}
int CGRectIsEmpty(CGRect r) {
  return r.size.width <= 0.0 || r.size.height <= 0.0;
}
int CGRectIsNull(CGRect r) {
  return r.origin.x > 1e20;
}
int CGRectContainsPoint(CGRect r, CGPoint p) {
  return p.x >= r.origin.x && p.x < r.origin.x + r.size.width &&
         p.y >= r.origin.y && p.y < r.origin.y + r.size.height;
}
CGFloat CGRectGetMinX(CGRect r) { return r.origin.x; }
CGFloat CGRectGetMidX(CGRect r) { return r.origin.x + r.size.width * 0.5; }
CGFloat CGRectGetMaxX(CGRect r) { return r.origin.x + r.size.width; }
CGFloat CGRectGetMinY(CGRect r) { return r.origin.y; }
CGFloat CGRectGetMidY(CGRect r) { return r.origin.y + r.size.height * 0.5; }
CGFloat CGRectGetMaxY(CGRect r) { return r.origin.y + r.size.height; }
CGFloat CGRectGetWidth(CGRect r) { return r.size.width; }
CGFloat CGRectGetHeight(CGRect r) { return r.size.height; }
CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy) {
  r.origin.x += dx;
  r.origin.y += dy;
  r.size.width -= dx * 2.0;
  r.size.height -= dy * 2.0;
  return r;
}
CGRect CGRectIntegral(CGRect r) {
  r.origin.x = (CGFloat)((int64_t)r.origin.x);
  r.origin.y = (CGFloat)((int64_t)r.origin.y);
  r.size.width = (CGFloat)((int64_t)(r.size.width + 0.999999));
  r.size.height = (CGFloat)((int64_t)(r.size.height + 0.999999));
  return r;
}
CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy) {
  r.origin.x += dx;
  r.origin.y += dy;
  return r;
}
CGRect CGRectStandardize(CGRect r) {
  if (r.size.width < 0) {
    r.origin.x += r.size.width;
    r.size.width = -r.size.width;
  }
  if (r.size.height < 0) {
    r.origin.y += r.size.height;
    r.size.height = -r.size.height;
  }
  return r;
}

// Display & SkyLight functions (used by Digital Color Meter & utilities)
uint32_t CGMainDisplayID(void) { return 1; }
size_t CGDisplayPixelsWide(uint32_t display) {
  (void)display;
  return 1024;
}
size_t CGDisplayPixelsHigh(uint32_t display) {
  (void)display;
  return 768;
}
CGRect CGDisplayBounds(uint32_t display) {
  (void)display;
  CGRect r = {{0.0, 0.0}, {1024.0, 768.0}};
  return r;
}
int32_t CGGetDisplaysWithPoint(CGPoint point, uint32_t maxDisplays,
                               uint32_t* displays,
                               uint32_t* matchingDisplayCount) {
  (void)point;
  if (displays && maxDisplays > 0) displays[0] = 1;
  if (matchingDisplayCount) *matchingDisplayCount = 1;
  return 0;
}
int32_t CGGetDisplaysWithRect(CGRect rect, uint32_t maxDisplays,
                              uint32_t* displays,
                              uint32_t* matchingDisplayCount) {
  (void)rect;
  if (displays && maxDisplays > 0) displays[0] = 1;
  if (matchingDisplayCount) *matchingDisplayCount = 1;
  return 0;
}
int32_t CGDisplayRegisterReconfigurationCallback(void* cb, void* userInfo) {
  (void)cb; (void)userInfo;
  return 0;
}
int32_t CGDisplayRemoveReconfigurationCallback(void* cb, void* userInfo) {
  (void)cb; (void)userInfo;
  return 0;
}
void* CGDisplayCreateImageForRect(uint32_t display, CGRect rect) {
  (void)display;
  size_t w = rect.size.width > 0 ? (size_t)rect.size.width : 64;
  size_t h = rect.size.height > 0 ? (size_t)rect.size.height : 64;
  return CGBitmapContextCreate(NULL, w, h, 8, w * 4, NULL, 0);
}

uint32_t CGSMainConnectionID(void) { return 1; }
uint32_t SLSMainConnectionID(void) { return 1; }
int32_t CGSGetCurrentCursorLocation(uint32_t cid, CGPoint* outPt) {
  (void)cid;
  if (outPt) {
    outPt->x = 512.0;
    outPt->y = 384.0;
  }
  return 0;
}
int32_t SLSGetCurrentCursorLocation(uint32_t cid, CGPoint* outPt) {
  return CGSGetCurrentCursorLocation(cid, outPt);
}
void* SLSHWCaptureWindowListInRect(uint32_t cid, const uint32_t* windowList,
                                   size_t count, CGRect rect, uint32_t flags) {
  (void)cid; (void)windowList; (void)count; (void)flags;
  size_t w = rect.size.width > 0 ? (size_t)rect.size.width : 64;
  size_t h = rect.size.height > 0 ? (size_t)rect.size.height : 64;
  void* img = CGBitmapContextCreate(NULL, w, h, 8, w * 4, NULL, 0);
  // Return a 1-element CFArray containing the captured CGImageRef.
  extern const void* CFArrayCreate(const void*, const void**, long, const void*);
  return (void*)CFArrayCreate(NULL, (const void**)&img, 1, NULL);
}

// ColorSync functions (used by Digital Color Meter)
void* ColorSyncProfileCreateWithDisplayID(uint32_t displayID) {
  (void)displayID;
  return &g_dummy_color_prof;
}
void* ColorSyncProfileCreateWithName(const void* name) {
  (void)name;
  return &g_dummy_color_prof;
}
void* ColorSyncProfileCreateWithData(const void* data, void** error) {
  (void)data;
  if (error) *error = NULL;
  return &g_dummy_color_prof;
}
const void* ColorSyncProfileCopyDescriptionString(void* prof) {
  (void)prof;
  extern const void* __CFStringMakeConstantString(const char*);
  return __CFStringMakeConstantString("sRGB IEC61966-2.1");
}
void* ColorSyncTransformCreate(const void* profileSequence, const void* options) {
  (void)profileSequence; (void)options;
  return &g_dummy_color_xform;
}
int ColorSyncTransformConvert(void* transform, size_t width, size_t height,
                              void* dst, int dstDepth, int dstLayout,
                              size_t dstBytesPerRow, const void* src,
                              int srcDepth, int srcLayout,
                              size_t srcBytesPerRow, const void* options) {
  (void)transform; (void)dstDepth; (void)dstLayout;
  (void)srcDepth; (void)srcLayout; (void)options;
  if (dst && src && height > 0) {
    size_t bpr = dstBytesPerRow < srcBytesPerRow ? dstBytesPerRow : srcBytesPerRow;
    if (bpr == 0) bpr = width * 4;
    for (size_t y = 0; y < height; ++y) {
      memcpy((uint8_t*)dst + y * dstBytesPerRow,
             (const uint8_t*)src + y * srcBytesPerRow, bpr);
    }
  }
  return 1;
}

const void* kColorSyncGenericRGBProfile = "kColorSyncGenericRGBProfile";
const void* kColorSyncSRGBProfile = "kColorSyncSRGBProfile";
const void* kColorSyncDisplayP3Profile = "kColorSyncDisplayP3Profile";
const void* kColorSyncAdobeRGB1998Profile = "kColorSyncAdobeRGB1998Profile";
const void* kColorSyncGenericLabProfile = "kColorSyncGenericLabProfile";
const void* kColorSyncProfile = "kColorSyncProfile";
const void* kColorSyncRenderingIntent = "kColorSyncRenderingIntent";
const void* kColorSyncRenderingIntentPerceptual = "kColorSyncRenderingIntentPerceptual";
const void* kColorSyncRenderingIntentUseProfileHeader = "kColorSyncRenderingIntentUseProfileHeader";
const void* kColorSyncTransformTag = "kColorSyncTransformTag";
const void* kColorSyncConvertQuality = "kColorSyncConvertQuality";
const void* kColorSyncBestQuality = "kColorSyncBestQuality";
const void* kColorSyncTransformPCSToDevice = "kColorSyncTransformPCSToDevice";
const void* kColorSyncTransformDeviceToPCS = "kColorSyncTransformDeviceToPCS";
const void* kColorSyncTransformDeviceToDevice = "kColorSyncTransformDeviceToDevice";
