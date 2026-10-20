// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef DARLING_EMBEDDED_OBJC_MESSAGE_H_
#define DARLING_EMBEDDED_OBJC_MESSAGE_H_

#include <objc/objc.h>

#ifdef __cplusplus
extern "C" {
#endif

id objc_msgSend(id self, SEL op, ...);
id objc_msgSendSuper2(struct objc_super2* super, SEL op, ...);

#ifdef __cplusplus
}
#endif

#endif  // DARLING_EMBEDDED_OBJC_MESSAGE_H_
