// SPDX-License-Identifier: GPL-3.0-or-later
#import <objc/objc.h>
#import <objc/message.h>
#include <stdio.h>

__attribute__((objc_root_class))
@interface NSObject {
 @public
  Class isa;
}
+ (Class)class;
+ (Class)superclass;
+ (instancetype)alloc;
+ (instancetype)new;
- (instancetype)init;
- (void)dealloc;
- (id)retain;
- (oneway void)release;
- (id)autorelease;
- (unsigned long)retainCount;
- (Class)class;
- (Class)superclass;
- (BOOL)isEqual:(id)object;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (id)performSelector:(SEL)aSelector;
- (id)performSelector:(SEL)aSelector withObject:(id)object;
- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;
- (id)copy;
- (id)description;
@end

@implementation NSObject

+ (Class)class {
  return self;
}

+ (Class)superclass {
  return class_getSuperclass(self);
}

+ (instancetype)alloc {
  return objc_alloc(self);
}

+ (instancetype)new {
  return [[self alloc] init];
}

- (instancetype)init {
  return self;
}

- (void)dealloc {
}

- (id)retain {
  return self;
}

- (oneway void)release {
}

- (id)autorelease {
  return self;
}

- (unsigned long)retainCount {
  return 1;
}

- (Class)class {
  return self ? object_getClass(self) : nullptr;
}

- (Class)superclass {
  return self ? class_getSuperclass(object_getClass(self)) : nullptr;
}

- (BOOL)isEqual:(id)object {
  return self == object;
}

- (BOOL)isKindOfClass:(Class)aClass {
  return objc_opt_isKindOfClass(self, aClass) ? YES : NO;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
  return objc_opt_respondsToSelector(self, aSelector) ? YES : NO;
}

- (id)performSelector:(SEL)aSelector {
  if (!aSelector) return nullptr;
  typedef id (*MsgFn)(id, SEL);
  return reinterpret_cast<MsgFn>(objc_msgSend)(self, aSelector);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object {
  if (!aSelector) return nullptr;
  typedef id (*MsgFn)(id, SEL, id);
  return reinterpret_cast<MsgFn>(objc_msgSend)(self, aSelector, object);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2 {
  if (!aSelector) return nullptr;
  typedef id (*MsgFn)(id, SEL, id, id);
  return reinterpret_cast<MsgFn>(objc_msgSend)(self, aSelector, object1, object2);
}

- (id)copy {
  return [self retain];
}

- (id)description {
  Class cls = object_getClass(self);
  const char* name = class_getName(cls);
  Class strCls = objc_getClass("NSString");
  if (strCls) {
    char buf[128];
    snprintf(buf, sizeof(buf), "<%s: %p>", name ? name : "NSObject", static_cast<void*>(self));
    typedef id (*MsgFn)(id, SEL, const char*);
    return reinterpret_cast<MsgFn>(objc_msgSend)(strCls, sel_registerName("stringWithUTF8String:"), buf);
  }
  return nil;
}

@end
