// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef DARLING_EMBEDDED_COREGRAPHICS_COREGRAPHICS_H_
#define DARLING_EMBEDDED_COREGRAPHICS_COREGRAPHICS_H_

#include <CoreFoundation/CoreFoundation.h>
#include <stddef.h>
#include <stdint.h>

typedef double CGFloat;

typedef struct CGPoint {
  CGFloat x;
  CGFloat y;
} CGPoint;

typedef struct CGSize {
  CGFloat width;
  CGFloat height;
} CGSize;

typedef struct CGRect {
  CGPoint origin;
  CGSize size;
} CGRect;

typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;

static inline CGPoint CGPointMake(CGFloat x, CGFloat y) {
  CGPoint p = {x, y};
  return p;
}

static inline CGSize CGSizeMake(CGFloat width, CGFloat height) {
  CGSize s = {width, height};
  return s;
}

static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat width,
                                CGFloat height) {
  CGRect r = {{x, y}, {width, height}};
  return r;
}

static inline NSPoint NSMakePoint(CGFloat x, CGFloat y) {
  return CGPointMake(x, y);
}

static inline NSSize NSMakeSize(CGFloat w, CGFloat h) {
  return CGSizeMake(w, h);
}

static inline NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
  return CGRectMake(x, y, w, h);
}

#ifndef DARLING_BUILDING_FOUNDATION
static inline bool NSPointInRect(NSPoint aPoint, NSRect aRect) {
  return aPoint.x >= aRect.origin.x &&
         aPoint.x < (aRect.origin.x + aRect.size.width) &&
         aPoint.y >= aRect.origin.y &&
         aPoint.y < (aRect.origin.y + aRect.size.height);
}

static inline NSRect NSInsetRect(NSRect aRect, CGFloat dX, CGFloat dY) {
  return NSMakeRect(aRect.origin.x + dX, aRect.origin.y + dY,
                    aRect.size.width - 2.0 * dX, aRect.size.height - 2.0 * dY);
}
#endif

#endif  // DARLING_EMBEDDED_COREGRAPHICS_COREGRAPHICS_H_
