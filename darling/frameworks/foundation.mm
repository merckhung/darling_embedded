// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded Foundation & CoreFoundation Framework implementation
// Independent implementation of a Foundation subset for ARM64 XNU/Darwin.

#define DARLING_BUILDING_FOUNDATION 1
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

// CFAllocator and __CFConstantStringClassReference are defined in CoreFoundation.

@class NSString;
extern "C" const char* _DarlingStringUTF8(NSString* s);
extern "C" int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
extern "C" id _DarlingParsePlist(const void* bytes, size_t len);

namespace {

class StringBuffer {
 public:
  StringBuffer() : data_(nullptr), len_(0), cap_(0) {}
  ~StringBuffer() {
    if (data_) free(data_);
  }

  void AppendChar(char c) {
    EnsureCapacity(len_ + 2);
    if (!data_) return;
    data_[len_++] = c;
    data_[len_] = '\0';
  }

  void Append(const char* s, size_t n) {
    if (!s || n == 0) return;
    EnsureCapacity(len_ + n + 1);
    if (!data_) return;
    memcpy(data_ + len_, s, n);
    len_ += n;
    data_[len_] = '\0';
  }

  void AppendCStr(const char* s) {
    if (!s) return;
    Append(s, strlen(s));
  }

  const char* c_str() const { return data_ ? data_ : ""; }
  size_t size() const { return len_; }

 private:
  void EnsureCapacity(size_t needed) {
    if (needed <= cap_) return;
    size_t next_cap = cap_ ? cap_ * 2 : 128;
    while (next_cap < needed) next_cap *= 2;
    char* next = static_cast<char*>(realloc(data_, next_cap));
    if (!next) return;
    data_ = next;
    cap_ = next_cap;
  }

  char* data_;
  size_t len_;
  size_t cap_;
};

char* DuplicateCStr(const char* s) {
  if (!s) s = "";
  size_t len = strlen(s);
  char* copy = static_cast<char*>(malloc(len + 1));
  if (copy) memcpy(copy, s, len + 1);
  return copy;
}

constexpr size_t kMaxTimers = 64;
NSTimer* g_active_timers[kMaxTimers];
size_t g_active_timer_count = 0;

struct DelayedPerform {
  id target;
  SEL selector;
  id argument;
  double fire_time;
  bool valid;
};

constexpr size_t kMaxDelayedPerforms = 64;
DelayedPerform g_delayed_performs[kMaxDelayedPerforms];
size_t g_delayed_perform_count = 0;

double CurrentMonotonicSeconds() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  return static_cast<double>(tv.tv_sec) +
         static_cast<double>(tv.tv_usec) / 1000000.0;
}

const char* SafeCString(id obj) {
  if (!obj) return "(null)";
  id desc = [obj description];
  if (!desc) return "(null)";
  const char* s = [reinterpret_cast<NSString*>(desc) UTF8String];
  return s ? s : "(null)";
}

void FormatWithVaList(const char* fmt, va_list ap, StringBuffer* out) {
  if (!fmt || !out) return;
  const char* p = fmt;
  while (*p) {
    if (*p != '%') {
      out->AppendChar(*p++);
      continue;
    }
    ++p;
    if (*p == '\0') break;
    if (*p == '%') {
      out->AppendChar('%');
      ++p;
      continue;
    }
    if (*p == '@') {
      id obj = va_arg(ap, id);
      out->AppendCStr(SafeCString(obj));
      ++p;
      continue;
    }

    char spec[64];
    size_t idx = 0;
    spec[idx++] = '%';
    int length_mod = 0;
    while (*p && idx + 2 < sizeof(spec)) {
      char c = *p++;
      spec[idx++] = c;
      if (c == 'l') {
        length_mod++;
        continue;
      }
      if (c == 'z' || c == 't') {
        length_mod = 1;
        continue;
      }
      if (c == 'h') {
        continue;
      }
      if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
        break;
      }
    }
    spec[idx] = '\0';
    char conv = spec[idx - 1];
    char buf[512];
    buf[0] = '\0';
    switch (conv) {
      case 's': {
        const char* s = va_arg(ap, const char*);
        snprintf(buf, sizeof(buf), spec, s ? s : "(null)");
        break;
      }
      case 'd':
      case 'i':
      case 'c': {
        if (length_mod >= 2) {
          long long v = va_arg(ap, long long);
          snprintf(buf, sizeof(buf), spec, v);
        } else if (length_mod == 1) {
          long v = va_arg(ap, long);
          snprintf(buf, sizeof(buf), spec, v);
        } else {
          int v = va_arg(ap, int);
          snprintf(buf, sizeof(buf), spec, v);
        }
        break;
      }
      case 'u':
      case 'x':
      case 'X':
      case 'o': {
        if (length_mod >= 2) {
          unsigned long long v = va_arg(ap, unsigned long long);
          snprintf(buf, sizeof(buf), spec, v);
        } else if (length_mod == 1) {
          unsigned long v = va_arg(ap, unsigned long);
          snprintf(buf, sizeof(buf), spec, v);
        } else {
          unsigned int v = va_arg(ap, unsigned int);
          snprintf(buf, sizeof(buf), spec, v);
        }
        break;
      }
      case 'f':
      case 'F':
      case 'e':
      case 'E':
      case 'g':
      case 'G': {
        double v = va_arg(ap, double);
        snprintf(buf, sizeof(buf), spec, v);
        break;
      }
      case 'p': {
        void* v = va_arg(ap, void*);
        snprintf(buf, sizeof(buf), spec, v);
        break;
      }
      default:
        break;
    }
    out->AppendCStr(buf);
  }
}

}  // namespace



@implementation NSAutoreleasePool

+ (void)addObject:(id)anObject {
  (void)anObject;
}

- (void)addObject:(id)anObject {
  (void)anObject;
}

- (void)drain {
}

@end

@implementation NSString

+ (instancetype)string {
  return [self stringWithUTF8String:""];
}

+ (instancetype)stringWithUTF8String:(const char*)nullTerminatedCString {
  return [[[self alloc] initWithUTF8String:nullTerminatedCString] autorelease];
}

+ (instancetype)stringWithCString:(const char*)cString
                         encoding:(NSUInteger)enc {
  (void)enc;
  return [self stringWithUTF8String:cString];
}

- (instancetype)copy {
  return [self retain];
}

+ (instancetype)stringWithFormat:(NSString*)format, ... {
  if (!format) return [self string];
  va_list ap;
  va_start(ap, format);
  StringBuffer formatted;
  FormatWithVaList([format UTF8String], ap, &formatted);
  va_end(ap);
  return [self stringWithUTF8String:formatted.c_str()];
}

- (instancetype)initWithUTF8String:(const char*)nullTerminatedCString {
  self = [super init];
  if (self) {
    const char* src = nullTerminatedCString ? nullTerminatedCString : "";
    size_t len = strlen(src);
    char* copy = DuplicateCStr(src);
    _flags = 0;
    _cstr = copy ? copy : "";
    _length = static_cast<long>(len);
  }
  return self;
}

- (instancetype)initWithFormat:(NSString*)format, ... {
  if (!format) return [self initWithUTF8String:""];
  va_list ap;
  va_start(ap, format);
  StringBuffer formatted;
  FormatWithVaList([format UTF8String], ap, &formatted);
  va_end(ap);
  return [self initWithUTF8String:formatted.c_str()];
}

- (const char*)UTF8String {
  return _DarlingStringUTF8(self);
}

- (NSUInteger)length {
  if (_length > 0) return static_cast<NSUInteger>(_length);
  return strlen([self UTF8String]);
}

- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (!object) return NO;
  if ([object respondsToSelector:@selector(UTF8String)]) {
    return [self isEqualToString:reinterpret_cast<NSString*>(object)];
  }
  return NO;
}

- (BOOL)isEqualToString:(NSString*)aString {
  if (self == aString) return YES;
  if (!aString) return NO;
  const char* a = [self UTF8String];
  const char* b = [aString UTF8String];
  if (!a || !b) return NO;
  return strcmp(a, b) == 0 ? YES : NO;
}

- (int)intValue {
  return atoi([self UTF8String]);
}

- (double)doubleValue {
  return atof([self UTF8String]);
}

- (instancetype)initWithData:(id)data encoding:(NSUInteger)encoding {
  (void)encoding;
  if (!data) return [self initWithUTF8String:""];
  if ([data respondsToSelector:@selector(bytes)] &&
      [data respondsToSelector:@selector(length)]) {
    typedef const void* (*BytesFn)(id, SEL);
    typedef NSUInteger (*LenFn)(id, SEL);
    const char* bytes = reinterpret_cast<const char*>(
        reinterpret_cast<BytesFn>(objc_msgSend)(data, sel_registerName("bytes")));
    NSUInteger len = reinterpret_cast<LenFn>(objc_msgSend)(
        data, sel_registerName("length"));
    if (bytes && len > 0) {
      char* buf = static_cast<char*>(malloc(len + 1));
      if (buf) {
        memcpy(buf, bytes, len);
        buf[len] = '\0';
        self = [self initWithUTF8String:buf];
        free(buf);
        return self;
      }
    }
  }
  return [self initWithUTF8String:""];
}

- (id)dataUsingEncoding:(NSUInteger)encoding {
  (void)encoding;
  const char* s = [self UTF8String];
  if (!s) return [NSData data];
  return [NSData dataWithBytes:s length:strlen(s)];
}

- (BOOL)hasPrefix:(NSString*)aString {
  if (!aString) return NO;
  const char* self_str = [self UTF8String];
  const char* prefix = [aString UTF8String];
  if (!self_str || !prefix) return NO;
  return strncmp(self_str, prefix, strlen(prefix)) == 0 ? YES : NO;
}

- (NSString*)lastPathComponent {
  const char* s = [self UTF8String];
  if (!s || !s[0]) return self;
  const char* slash = strrchr(s, '/');
  if (slash && *(slash + 1)) {
    return [NSString stringWithUTF8String:slash + 1];
  }
  return self;
}

- (id)description {
  return self;
}

@end

@implementation NSConstantString
@end

@implementation NSObject (NSDelayedPerforming)

- (void)performSelector:(SEL)aSelector
             withObject:(id)anArgument
             afterDelay:(NSTimeInterval)delay {
  const char* sel_str = reinterpret_cast<const char*>(aSelector);
  fprintf(stderr, "[Foundation] performSelector:%s withObject:%p afterDelay:%f on %p\n",
          sel_str ? sel_str : "<null>", anArgument, delay, self);
  if (!aSelector) return;
  double fire_time = CurrentMonotonicSeconds() + (delay > 0.0 ? delay : 0.0);
  for (size_t i = 0; i < g_delayed_perform_count; ++i) {
    if (!g_delayed_performs[i].valid) {
      g_delayed_performs[i].target = [self retain];
      g_delayed_performs[i].selector = aSelector;
      g_delayed_performs[i].argument = [anArgument retain];
      g_delayed_performs[i].fire_time = fire_time;
      g_delayed_performs[i].valid = true;
      return;
    }
  }
  if (g_delayed_perform_count < kMaxDelayedPerforms) {
    g_delayed_performs[g_delayed_perform_count].target = [self retain];
    g_delayed_performs[g_delayed_perform_count].selector = aSelector;
    g_delayed_performs[g_delayed_perform_count].argument = [anArgument retain];
    g_delayed_performs[g_delayed_perform_count].fire_time = fire_time;
    g_delayed_performs[g_delayed_perform_count].valid = true;
    g_delayed_perform_count++;
  }
}

@end

@implementation NSNumber

+ (NSNumber*)numberWithInt:(int)value {
  NSNumber* n = [[NSNumber alloc] init];
  n->_intVal = value;
  n->_doubleVal = static_cast<double>(value);
  n->_isFloat = NO;
  return n;
}

+ (NSNumber*)numberWithLongLong:(long long)value {
  NSNumber* n = [[NSNumber alloc] init];
  n->_intVal = value;
  n->_doubleVal = static_cast<double>(value);
  n->_isFloat = NO;
  return n;
}

+ (NSNumber*)numberWithDouble:(double)value {
  NSNumber* n = [[NSNumber alloc] init];
  n->_doubleVal = value;
  n->_intVal = static_cast<long long>(value);
  n->_isFloat = YES;
  return n;
}

+ (NSNumber*)numberWithBool:(BOOL)value {
  return [self numberWithInt:(value ? 1 : 0)];
}

- (int)intValue {
  return static_cast<int>(_intVal);
}

- (long long)longLongValue {
  return _intVal;
}

- (double)doubleValue {
  return _doubleVal;
}

- (BOOL)boolValue {
  return _intVal != 0 ? YES : NO;
}

- (NSString*)stringValue {
  char buf[64];
  if (_isFloat) {
    snprintf(buf, sizeof(buf), "%.4g", _doubleVal);
  } else {
    snprintf(buf, sizeof(buf), "%lld", _intVal);
  }
  return [NSString stringWithUTF8String:buf];
}

- (id)description {
  return [self stringValue];
}

@end

@implementation NSBundle

+ (NSBundle*)mainBundle {
  static NSBundle* main_bundle = nullptr;
  if (!main_bundle) {
    const char* bundle_env = getenv("DARLING_APP_BUNDLE");
    char derived[1024];
    if (!bundle_env || !bundle_env[0]) {
      // .../Name.app/Contents/MacOS/Name -> .../Name.app
      uint32_t size = sizeof(derived);
      if (_NSGetExecutablePath(derived, &size) == 0) {
        char* macos = strstr(derived, ".app/Contents/MacOS/");
        if (macos) {
          macos[4] = '\0';
          bundle_env = derived;
        }
      }
    }
    NSString* path = [NSString
        stringWithUTF8String:(bundle_env && bundle_env[0]) ? bundle_env : "/"];
    main_bundle = [[NSBundle alloc] initWithPath:path];
  }
  return main_bundle;
}

+ (NSBundle*)bundleWithPath:(NSString*)path {
  return [[[self alloc] initWithPath:path] autorelease];
}

+ (NSBundle*)bundleForClass:(Class)aClass {
  (void)aClass;
  return [self mainBundle];
}

+ (NSBundle*)bundleWithIdentifier:(NSString*)identifier {
  (void)identifier;
  return [self mainBundle];
}

+ (NSBundle*)bundleWithURL:(id)url {
  if (!url) return [self mainBundle];
  if ([url respondsToSelector:@selector(path)]) {
    return [self bundleWithPath:[url performSelector:@selector(path)]];
  }
  return [self mainBundle];
}

- (BOOL)load { return YES; }
- (BOOL)isLoaded { return YES; }

- (instancetype)initWithPath:(NSString*)path {
  self = [super init];
  if (self) {
    _bundlePath = path ? path : @"/";
    NSString* plistPath = [NSString
        stringWithFormat:@"%@/Contents/Info.plist", _bundlePath];
    _infoDict = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!_infoDict) {
      _infoDict = [[NSMutableDictionary alloc] init];
    }
  }
  return self;
}

- (NSString*)bundlePath {
  return _bundlePath;
}

- (NSString*)executablePath {
  id execName = [self objectForInfoDictionaryKey:@"CFBundleExecutable"];
  if (execName) {
    return [NSString
        stringWithFormat:@"%@/Contents/MacOS/%@", _bundlePath, execName];
  }
  return _bundlePath;
}

- (NSString*)bundleIdentifier {
  id ident = [self objectForInfoDictionaryKey:@"CFBundleIdentifier"];
  return ident ? reinterpret_cast<NSString*>(ident)
               : @"org.darlinghq.embedded.app";
}

- (NSString*)pathForResource:(NSString*)name ofType:(NSString*)ext {
  if (!name) return nullptr;
  char buf[512];
  if (ext && [ext length] > 0) {
    snprintf(buf, sizeof(buf), "%s/Contents/Resources/%s.%s", [_bundlePath UTF8String],
             [name UTF8String], [ext UTF8String]);
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
    snprintf(buf, sizeof(buf), "%s/Contents/Resources/Base.lproj/%s.%s",
             [_bundlePath UTF8String], [name UTF8String], [ext UTF8String]);
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
    snprintf(buf, sizeof(buf), "%s/Contents/Resources/en.lproj/%s.%s",
             [_bundlePath UTF8String], [name UTF8String], [ext UTF8String]);
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
    snprintf(buf, sizeof(buf), "%s/Contents/Resources/English.lproj/%s.%s",
             [_bundlePath UTF8String], [name UTF8String], [ext UTF8String]);
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
  } else {
    snprintf(buf, sizeof(buf), "%s/Contents/Resources/%s", [_bundlePath UTF8String],
             [name UTF8String]);
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
    snprintf(buf, sizeof(buf), "%s/Contents/Resources/Base.lproj/%s",
             [_bundlePath UTF8String], [name UTF8String]);
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
    snprintf(buf, sizeof(buf), "%s/Contents/Resources/en.lproj/%s",
             [_bundlePath UTF8String], [name UTF8String]);
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
  }
  return nullptr;
}

- (NSString*)pathForResource:(NSString*)name
                      ofType:(NSString*)ext
                 inDirectory:(NSString*)subpath {
  if (subpath && [subpath length] > 0) {
    char buf[512];
    if (ext && [ext length] > 0) {
      snprintf(buf, sizeof(buf), "%s/Contents/Resources/%s/%s.%s",
               [_bundlePath UTF8String], [subpath UTF8String],
               [name UTF8String], [ext UTF8String]);
    } else {
      snprintf(buf, sizeof(buf), "%s/Contents/Resources/%s/%s",
               [_bundlePath UTF8String], [subpath UTF8String],
               [name UTF8String]);
    }
    if (access(buf, F_OK) == 0) return [NSString stringWithUTF8String:buf];
  }
  return [self pathForResource:name ofType:ext];
}

- (NSArray*)pathsForResourcesOfType:(NSString*)ext
                        inDirectory:(NSString*)subpath {
  (void)ext;
  (void)subpath;
  return [NSArray array];
}

- (NSDictionary*)infoDictionary {
  return _infoDict;
}

- (id)objectForInfoDictionaryKey:(NSString*)key {
  return _infoDict ? [_infoDict objectForKey:key] : nullptr;
}

@end

@implementation NSProcessInfo

+ (NSProcessInfo*)processInfo {
  static NSProcessInfo* info = nullptr;
  if (!info) {
    info = [[NSProcessInfo alloc] init];
  }
  return info;
}

- (NSString*)processName {
  if (_processName) return _processName;
  const char* prog = getprogname();
  return [NSString stringWithUTF8String:(prog && prog[0]) ? prog : "DarlingApp"];
}

- (NSString*)hostName {
  char buf[128] = {0};
  if (gethostname(buf, sizeof(buf) - 1) == 0 && buf[0] != '\0') {
    return [NSString stringWithUTF8String:buf];
  }
  return @"darwin-arm64.local";
}

- (NSString*)operatingSystemVersionString {
  char ostype[64] = "Darwin";
  char osrelease[64] = "25.5.0";
  char machine[64] = "arm64";
  size_t len = sizeof(ostype) - 1;
  sysctlbyname("kern.ostype", ostype, &len, nullptr, 0);
  len = sizeof(osrelease) - 1;
  sysctlbyname("kern.osrelease", osrelease, &len, nullptr, 0);
  len = sizeof(machine) - 1;
  sysctlbyname("hw.machine", machine, &len, nullptr, 0);
  return [NSString
      stringWithFormat:@"Mac OS X 10.15.7 (%s %s %s / Darling)", ostype,
                       osrelease, machine];
}

- (NSUInteger)processorCount {
  int ncpu = 4;
  size_t len = sizeof(ncpu);
  if (sysctlbyname("hw.ncpu", &ncpu, &len, nullptr, 0) != 0 || ncpu < 1) {
    ncpu = 4;
  }
  return static_cast<NSUInteger>(ncpu);
}

- (unsigned long long)physicalMemory {
  uint64_t mem = 0;
  size_t len = sizeof(mem);
  if (sysctlbyname("hw.memsize", &mem, &len, nullptr, 0) != 0 || mem == 0) {
    mem = 2ULL * 1024ULL * 1024ULL * 1024ULL;
  }
  return static_cast<unsigned long long>(mem);
}

- (NSTimeInterval)systemUptime {
  struct timeval boottime = {0, 0};
  size_t len = sizeof(boottime);
  int mib[2] = {CTL_KERN, KERN_BOOTTIME};
  if (sysctl(mib, 2, &boottime, &len, nullptr, 0) == 0 &&
      boottime.tv_sec > 0) {
    struct timeval now;
    gettimeofday(&now, nullptr);
    double diff = static_cast<double>(now.tv_sec - boottime.tv_sec) +
                  static_cast<double>(now.tv_usec - boottime.tv_usec) / 1e6;
    if (diff >= 0.0) return diff;
  }
  static double start_time = CurrentMonotonicSeconds();
  return CurrentMonotonicSeconds() - start_time + 1.0;
}

- (int)processIdentifier {
  return static_cast<int>(getpid());
}

@end

@implementation NSTimer

+ (NSTimer*)timerWithTimeInterval:(NSTimeInterval)ti
                           target:(id)aTarget
                         selector:(SEL)aSelector
                         userInfo:(id)userInfo
                          repeats:(BOOL)yesOrNo {
  return [self scheduledTimerWithTimeInterval:ti
                                       target:aTarget
                                     selector:aSelector
                                     userInfo:userInfo
                                      repeats:yesOrNo];
}

+ (NSTimer*)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                    target:(id)aTarget
                                  selector:(SEL)aSelector
                                  userInfo:(id)userInfo
                                   repeats:(BOOL)yesOrNo {
  NSTimer* timer = [[NSTimer alloc] init];
  timer->_interval = (ti > 0.005) ? ti : 0.005;
  timer->_nextFire = CurrentMonotonicSeconds() + timer->_interval;
  timer->_target = aTarget;
  timer->_selector = aSelector;
  timer->_userInfo = userInfo;
  timer->_repeats = yesOrNo;
  timer->_valid = YES;
  if (g_active_timer_count < kMaxTimers) {
    g_active_timers[g_active_timer_count++] = timer;
  }
  return timer;
}

- (void)fire {
  if (!_valid || !_target || !_selector) return;
  typedef void (*TimerMsgFn)(id, SEL, id);
  reinterpret_cast<TimerMsgFn>(objc_msgSend)(_target, _selector, self);
  if (!_repeats) {
    _valid = NO;
  }
}

- (void)invalidate {
  _valid = NO;
}

- (BOOL)isValid {
  return _valid;
}

- (id)userInfo {
  return _userInfo;
}

@end

@implementation NSData

+ (instancetype)data {
  return [[[self alloc] init] autorelease];
}

+ (instancetype)dataWithBytes:(const void*)bytes length:(NSUInteger)length {
  return [[[self alloc] initWithBytes:bytes length:length] autorelease];
}

+ (instancetype)dataWithBytesNoCopy:(void*)bytes
                             length:(NSUInteger)length
                       freeWhenDone:(BOOL)b {
  (void)b;
  return [self dataWithBytes:bytes length:length];
}

+ (instancetype)dataWithData:(NSData*)aData {
  if (!aData) return [self data];
  return [self dataWithBytes:[aData bytes] length:[aData length]];
}

+ (instancetype)dataWithContentsOfFile:(NSString*)path {
  return [[[self alloc] initWithContentsOfFile:path] autorelease];
}

+ (instancetype)dataWithContentsOfFile:(NSString*)path
                               options:(NSUInteger)readOptionsMask
                                 error:(id*)errorPtr {
  (void)readOptionsMask;
  if (errorPtr) *errorPtr = nil;
  return [self dataWithContentsOfFile:path];
}

+ (instancetype)dataWithContentsOfURL:(id)url {
  if (!url) return nil;
  if ([url respondsToSelector:@selector(path)]) {
    return [self dataWithContentsOfFile:[url performSelector:@selector(path)]];
  }
  return nil;
}

+ (instancetype)dataWithContentsOfURL:(id)url
                              options:(NSUInteger)readOptionsMask
                                error:(id*)errorPtr {
  (void)readOptionsMask;
  if (errorPtr) *errorPtr = nil;
  return [self dataWithContentsOfURL:url];
}

- (instancetype)initWithBytes:(const void*)bytes length:(NSUInteger)length {
  self = [super init];
  if (self && bytes && length > 0) {
    void* copy = malloc(length);
    if (copy) {
      memcpy(copy, bytes, length);
      _bytes = copy;
      _length = length;
    }
  }
  return self;
}

- (instancetype)initWithData:(NSData*)data {
  return [self initWithBytes:data ? [data bytes] : nullptr
                      length:data ? [data length] : 0];
}

- (instancetype)initWithContentsOfFile:(NSString*)path {
  if (!path) {
    [self release];
    return nil;
  }
  FILE* fp = fopen([path UTF8String], "rb");
  if (!fp) {
    [self release];
    return nil;
  }
  fseek(fp, 0, SEEK_END);
  long sz = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (sz <= 0) {
    fclose(fp);
    return [self init];
  }
  void* buf = malloc(static_cast<size_t>(sz));
  size_t n = buf ? fread(buf, 1, static_cast<size_t>(sz), fp) : 0;
  fclose(fp);
  self = [super init];
  if (self && buf) {
    _bytes = buf;
    _length = n;
  } else if (buf) {
    free(buf);
  }
  return self;
}

- (instancetype)initWithContentsOfFile:(NSString*)path
                               options:(NSUInteger)readOptionsMask
                                 error:(id*)errorPtr {
  (void)readOptionsMask;
  if (errorPtr) *errorPtr = nil;
  return [self initWithContentsOfFile:path];
}

- (const void*)bytes {
  return _bytes;
}

- (NSUInteger)length {
  return _length;
}

- (void)getBytes:(void*)buffer length:(NSUInteger)length {
  if (!buffer || !_bytes || length == 0) return;
  NSUInteger n = length < _length ? length : _length;
  memcpy(buffer, _bytes, n);
}

- (void)getBytes:(void*)buffer range:(NSRange)range {
  if (!buffer || !_bytes || range.location >= _length) return;
  NSUInteger n = range.length;
  if (range.location + n > _length) n = _length - range.location;
  memcpy(buffer, static_cast<const char*>(_bytes) + range.location, n);
}

- (NSData*)subdataWithRange:(NSRange)range {
  if (!_bytes || range.location >= _length) return [NSData data];
  NSUInteger n = range.length;
  if (range.location + n > _length) n = _length - range.location;
  return [NSData dataWithBytes:static_cast<const char*>(_bytes) + range.location
                        length:n];
}

- (BOOL)isEqualToData:(NSData*)other {
  if (self == other) return YES;
  if (!other || _length != [other length]) return NO;
  if (_length == 0) return YES;
  return memcmp(_bytes, [other bytes], _length) == 0 ? YES : NO;
}

- (BOOL)writeToFile:(NSString*)path atomically:(BOOL)useAuxiliaryFile {
  (void)useAuxiliaryFile;
  if (!path) return NO;
  FILE* fp = fopen([path UTF8String], "wb");
  if (!fp) return NO;
  if (_bytes && _length > 0) fwrite(_bytes, 1, _length, fp);
  fclose(fp);
  return YES;
}

- (BOOL)writeToFile:(NSString*)path
            options:(NSUInteger)writeOptionsMask
              error:(id*)errorPtr {
  (void)writeOptionsMask;
  if (errorPtr) *errorPtr = nil;
  return [self writeToFile:path atomically:YES];
}

- (id)copy { return [self retain]; }
- (id)mutableCopy {
  return [[NSMutableData alloc] initWithBytes:_bytes length:_length];
}

- (void)dealloc {
  if (_bytes) free(const_cast<void*>(_bytes));
  [super dealloc];
}

@end

@implementation NSMutableData

+ (instancetype)dataWithCapacity:(NSUInteger)aNumItems {
  (void)aNumItems;
  return [[[self alloc] init] autorelease];
}

+ (instancetype)dataWithLength:(NSUInteger)length {
  return [[[self alloc] initWithLength:length] autorelease];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
  (void)capacity;
  return [self init];
}

- (instancetype)initWithLength:(NSUInteger)length {
  self = [super init];
  if (self && length > 0) {
    _bytes = calloc(1, length);
    _length = _bytes ? length : 0;
  }
  return self;
}

- (void*)mutableBytes {
  return const_cast<void*>(_bytes);
}

- (void)setLength:(NSUInteger)length {
  if (length == 0) {
    if (_bytes) free(const_cast<void*>(_bytes));
    _bytes = nullptr;
    _length = 0;
    return;
  }
  void* next = realloc(const_cast<void*>(_bytes), length);
  if (!next) return;
  if (length > _length) {
    memset(static_cast<char*>(next) + _length, 0, length - _length);
  }
  _bytes = next;
  _length = length;
}

- (void)appendBytes:(const void*)bytes length:(NSUInteger)length {
  if (!bytes || length == 0) return;
  NSUInteger old_len = _length;
  [self setLength:old_len + length];
  if (_length >= old_len + length) {
    memcpy(static_cast<char*>(const_cast<void*>(_bytes)) + old_len, bytes, length);
  }
}

- (void)appendData:(NSData*)other {
  if (!other) return;
  [self appendBytes:[other bytes] length:[other length]];
}

@end

@implementation NSFileManager

+ (NSFileManager*)defaultManager {
  static NSFileManager* manager = nullptr;
  if (!manager) {
    manager = [[NSFileManager alloc] init];
  }
  return manager;
}

- (BOOL)fileExistsAtPath:(NSString*)path {
  if (!path) return NO;
  return access([path UTF8String], F_OK) == 0;
}

@end

@implementation NSPropertyListSerialization

+ (id)propertyListWithData:(NSData*)data
                   options:(NSUInteger)opt
                    format:(void*)format
                     error:(id*)error {
  (void)opt;
  if (error) *error = nil;
  if (format) *static_cast<NSUInteger*>(format) = 200;
  if (!data || [data length] == 0) return [NSDictionary dictionary];
  id parsed = _DarlingParsePlist([data bytes], [data length]);
  return parsed ? parsed : [NSDictionary dictionary];
}

+ (id)propertyListFromData:(NSData*)data
          mutabilityOption:(NSUInteger)opt
                    format:(void*)format
          errorDescription:(id*)errorString {
  if (errorString) *errorString = nil;
  return [self propertyListWithData:data options:opt format:format error:nullptr];
}

+ (NSData*)dataWithPropertyList:(id)plist
                         format:(NSUInteger)format
                        options:(NSUInteger)opt
                          error:(id*)error {
  (void)plist; (void)format; (void)opt;
  if (error) *error = nil;
  return [NSData data];
}

@end

namespace {

void BindCFConstantStringClass() {
  Class cls = objc_getClass("NSConstantString");
  if (!cls) cls = objc_getClass("NSString");
  if (cls) {
    memcpy(__CFConstantStringClassReference, cls, 40);
  }
}

__attribute__((constructor)) void InitializeDarlingFoundation() {
  BindCFConstantStringClass();
}

}  // namespace

extern "C" {

void _DarlingFireDueTimers(void) {
  double now = CurrentMonotonicSeconds();
  for (size_t i = 0; i < g_active_timer_count; ++i) {
    NSTimer* t = g_active_timers[i];
    if (!t || !t->_valid) continue;
    if (now >= t->_nextFire) {
      t->_nextFire = now + t->_interval;
      [t fire];
    }
  }

  size_t current_count = g_delayed_perform_count;
  for (size_t i = 0; i < current_count; ++i) {
    if (!g_delayed_performs[i].valid) continue;
    if (now >= g_delayed_performs[i].fire_time) {
      g_delayed_performs[i].valid = false;
      id target = g_delayed_performs[i].target;
      SEL sel = g_delayed_performs[i].selector;
      id arg = g_delayed_performs[i].argument;
      const char* sel_str = reinterpret_cast<const char*>(sel);
      fprintf(stderr, "[Foundation] firing delayed perform %s on %p\n",
              sel_str ? sel_str : "<null>", target);
      typedef void (*DelayedMsgFn)(id, SEL, id);
      reinterpret_cast<DelayedMsgFn>(objc_msgSend)(target, sel, arg);
      [target release];
      [arg release];
    }
  }
}

Class NSClassFromString(id aClassName) {
  if (!aClassName) return nullptr;
  return objc_getClass([reinterpret_cast<NSString*>(aClassName) UTF8String]);
}

SEL NSSelectorFromString(id aSelectorName) {
  if (!aSelectorName) return nullptr;
  return sel_registerName(
      [reinterpret_cast<NSString*>(aSelectorName) UTF8String]);
}

void NSLog(id format, ...) {
  if (!format) return;
  BindCFConstantStringClass();
  va_list ap;
  va_start(ap, format);
  StringBuffer msg;
  FormatWithVaList([reinterpret_cast<NSString*>(format) UTF8String], ap, &msg);
  va_end(ap);
  const char* prog = getprogname();
  fprintf(stderr, "[Darling %s:%d] %s\n",
          (prog && prog[0]) ? prog : "App", static_cast<int>(getpid()),
          msg.c_str());
  fflush(stderr);
}

}  // extern "C"

#include "foundation_more.mm"
