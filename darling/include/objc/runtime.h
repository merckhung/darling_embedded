// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef DARLING_EMBEDDED_OBJC_RUNTIME_H_
#define DARLING_EMBEDDED_OBJC_RUNTIME_H_

#include <objc/objc.h>
#include <stddef.h>

typedef struct objc_ivar* Ivar;

#ifdef __cplusplus
extern "C" {
#endif
Ivar class_getInstanceVariable(Class cls, const char* name);
ptrdiff_t ivar_getOffset(Ivar ivar);
const char* ivar_getName(Ivar ivar);
const char* ivar_getTypeEncoding(Ivar ivar);
id object_getIvar(id obj, Ivar ivar);
void object_setIvar(id obj, Ivar ivar, id value);
#ifdef __cplusplus
}
#endif

#endif  // DARLING_EMBEDDED_OBJC_RUNTIME_H_
