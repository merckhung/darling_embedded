// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef DARLING_EMBEDDED_COREFOUNDATION_COREFOUNDATION_H_
#define DARLING_EMBEDDED_COREFOUNDATION_COREFOUNDATION_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef const void* CFTypeRef;
typedef const struct __CFAllocator* CFAllocatorRef;
typedef const struct __CFString* CFStringRef;
typedef const struct __CFDictionary* CFDictionaryRef;
typedef const struct __CFArray* CFArrayRef;
typedef long CFIndex;
typedef uint32_t CFStringEncoding;

enum {
  kCFStringEncodingASCII = 0x0600,
  kCFStringEncodingUTF8 = 0x08000100,
};

extern const CFAllocatorRef kCFAllocatorDefault;
extern int __CFConstantStringClassReference[32];

extern const CFStringRef _kCFSystemVersionProductNameKey;
extern const CFStringRef _kCFSystemVersionProductVersionKey;
extern const CFStringRef _kCFSystemVersionBuildVersionKey;

#ifdef __OBJC__
#define CFSTR(cStr) ((CFStringRef)@cStr)
#else
CFStringRef __CFStringMakeConstantString(const char* cStr);
#define CFSTR(cStr) __CFStringMakeConstantString(cStr)
#endif

CFTypeRef CFRetain(CFTypeRef cf);
void CFRelease(CFTypeRef cf);
uint32_t CFStringGetSystemEncoding(void);
CFStringRef CFStringCreateWithCString(CFAllocatorRef alloc, const char* cStr,
                                      CFStringEncoding encoding);
CFStringRef CFStringCreateWithFormat(CFAllocatorRef alloc,
                                     CFDictionaryRef formatOptions,
                                     CFStringRef format, ...);
bool CFStringGetCString(CFStringRef theString, char* buffer, CFIndex bufferSize,
                        CFStringEncoding encoding);
const char* CFStringGetCStringPtr(CFStringRef theString,
                                  CFStringEncoding encoding);
CFIndex CFStringGetLength(CFStringRef theString);

const void* CFDictionaryGetValue(CFDictionaryRef theDict, const void* key);
CFIndex CFDictionaryGetCount(CFDictionaryRef theDict);

CFDictionaryRef _CFCopySystemVersionDictionary(void);
CFDictionaryRef _CFCopyServerVersionDictionary(void);

#ifdef __cplusplus
}
#endif

#endif  // DARLING_EMBEDDED_COREFOUNDATION_COREFOUNDATION_H_
