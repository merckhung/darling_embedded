// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef DARLING_EMBEDDED_OBJC_OBJC_H_
#define DARLING_EMBEDDED_OBJC_OBJC_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct objc_class* Class;
typedef struct objc_object* id;
typedef const char* SEL;
typedef id (*IMP)(id, SEL, ...);
typedef bool BOOL;

#define YES ((BOOL)1)
#define NO ((BOOL)0)

#ifndef nil
#ifdef __cplusplus
#define nil nullptr
#else
#define nil ((id)0)
#endif
#endif

#ifndef Nil
#ifdef __cplusplus
#define Nil nullptr
#else
#define Nil ((Class)0)
#endif
#endif

struct objc_object {
  Class isa;
};

struct objc_super2 {
  id receiver;
  Class current_class;
};

SEL sel_registerName(const char* name);
const char* sel_getName(SEL sel);
bool sel_isEqual(SEL lhs, SEL rhs);

Class objc_getClass(const char* name);
Class objc_lookUpClass(const char* name);
Class objc_getMetaClass(const char* name);
const char* class_getName(Class cls);
Class class_getSuperclass(Class cls);
size_t class_getInstanceSize(Class cls);
bool class_respondsToSelector(Class cls, SEL sel);
IMP class_getMethodImplementation(Class cls, SEL sel);

Class object_getClass(id obj);
Class object_setClass(id obj, Class cls);

id objc_alloc(Class cls);
id objc_alloc_init(Class cls);
id objc_retain(id obj);
void objc_release(id obj);
id objc_autorelease(id obj);
void* objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void* pool);
void objc_storeStrong(id* location, id obj);
Class objc_opt_class(id obj);
bool objc_opt_isKindOfClass(id obj, Class cls);
bool objc_opt_respondsToSelector(id obj, SEL sel);

#ifdef __cplusplus
}
#endif

#endif  // DARLING_EMBEDDED_OBJC_OBJC_H_
