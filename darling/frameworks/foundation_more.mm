// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded Foundation: strings, notifications, tasks/pipes/file
// handles with run-loop delivery, scanners, formatters, URLs and other
// classes used by real-world Cocoa applications. Included from
// foundation.mm (shares its helpers).

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <sys/stat.h>

extern "C" NSString* const NSFileHandleReadCompletionNotification;
NSString* const NSFileHandleReadCompletionNotification = @"NSFileHandleReadCompletionNotification";
extern "C" NSString* const NSFileHandleNotificationDataItem;
NSString* const NSFileHandleNotificationDataItem = @"NSFileHandleNotificationDataItem";
extern "C" NSString* const NSFileHandleNotificationFileHandleItem;
NSString* const NSFileHandleNotificationFileHandleItem = @"NSFileHandleNotificationFileHandleItem";
extern "C" NSString* const NSTaskDidTerminateNotification;
NSString* const NSTaskDidTerminateNotification = @"NSTaskDidTerminateNotification";
extern "C" NSString* const NSUserNotificationDefaultSoundName;
NSString* const NSUserNotificationDefaultSoundName = @"DefaultSoundName";
extern "C" NSString* const NSGenericException;
NSString* const NSGenericException = @"NSGenericException";
extern "C" NSString* const NSInvalidArgumentException;
NSString* const NSInvalidArgumentException = @"NSInvalidArgumentException";

namespace {

// ---------------------------------------------------------------------------
// UTF-16 constant strings. clang emits non-ASCII @"..." literals as CFString
// constants with UTF-16 storage (flag 0x10); convert them to UTF-8 once.
// ---------------------------------------------------------------------------
struct Utf16Cache {
  const void* key;
  char* utf8;
  Utf16Cache* next;
};
Utf16Cache* g_utf16_cache = nullptr;

const char* Utf16ConstantToUtf8(const uint16_t* units, long count, const void* key) {
  for (Utf16Cache* c = g_utf16_cache; c; c = c->next) {
    if (c->key == key) return c->utf8;
  }
  char* out = static_cast<char*>(malloc(static_cast<size_t>(count) * 4 + 1));
  size_t o = 0;
  for (long i = 0; out && i < count; ++i) {
    uint32_t cp = units[i];
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < count) {
      cp = 0x10000 + ((cp - 0xD800) << 10) + (units[i + 1] - 0xDC00);
      ++i;
    }
    if (cp < 0x80) {
      out[o++] = static_cast<char>(cp);
    } else if (cp < 0x800) {
      out[o++] = static_cast<char>(0xC0 | (cp >> 6));
      out[o++] = static_cast<char>(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      out[o++] = static_cast<char>(0xE0 | (cp >> 12));
      out[o++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
      out[o++] = static_cast<char>(0x80 | (cp & 0x3F));
    } else {
      out[o++] = static_cast<char>(0xF0 | (cp >> 18));
      out[o++] = static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
      out[o++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
      out[o++] = static_cast<char>(0x80 | (cp & 0x3F));
    }
  }
  if (out) out[o] = '\0';
  auto* entry = static_cast<Utf16Cache*>(malloc(sizeof(Utf16Cache)));
  if (entry) {
    *entry = {key, out, g_utf16_cache};
    g_utf16_cache = entry;
  }
  return out ? out : "";
}

NSString* StrFromBytes(const char* s, size_t n) {
  char* tmp = static_cast<char*>(malloc(n + 1));
  if (!tmp) return [NSString string];
  memcpy(tmp, s, n);
  tmp[n] = '\0';
  NSString* r = [NSString stringWithUTF8String:tmp];
  free(tmp);
  return r;
}

const char* Utf8(id s) {
  return s ? [static_cast<NSString*>(s) UTF8String] : "";
}

}  // namespace

extern "C" const char* _DarlingStringUTF8(NSString* s) {
  if (!s) return "";
  if (s->_flags & 0x10) {
    return Utf16ConstantToUtf8(reinterpret_cast<const uint16_t*>(s->_cstr), s->_length, s);
  }
  return s->_cstr ? s->_cstr : "";
}

// ===========================================================================
// NSString additions
// ===========================================================================
@implementation NSString (DarlingAdditions)

+ (instancetype)stringWithString:(NSString*)aString {
  return [self stringWithUTF8String:Utf8(aString)];
}

+ (instancetype)stringWithContentsOfFile:(NSString*)path
                                encoding:(NSUInteger)enc
                                   error:(id*)error {
  (void)enc;
  if (error) *error = nil;
  FILE* fp = path ? fopen(Utf8(path), "rb") : nullptr;
  if (!fp) return nil;
  StringBuffer sb;
  char buf[4096];
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) sb.Append(buf, n);
  fclose(fp);
  return [self stringWithUTF8String:sb.c_str()];
}

- (instancetype)initWithString:(NSString*)aString {
  return [self initWithUTF8String:Utf8(aString)];
}

- (instancetype)initWithFormat:(NSString*)format arguments:(va_list)argList {
  if (!format) return [self initWithUTF8String:""];
  StringBuffer formatted;
  FormatWithVaList(Utf8(format), argList, &formatted);
  return [self initWithUTF8String:formatted.c_str()];
}

- (instancetype)initWithBytes:(const void*)bytes
                       length:(NSUInteger)len
                     encoding:(NSUInteger)enc {
  (void)enc;
  char* tmp = static_cast<char*>(malloc(len + 1));
  if (!tmp) return [self initWithUTF8String:""];
  memcpy(tmp, bytes, len);
  tmp[len] = '\0';
  self = [self initWithUTF8String:tmp];
  free(tmp);
  return self;
}

- (NSString*)substringFromIndex:(NSUInteger)from {
  const char* s = [self UTF8String];
  size_t n = strlen(s);
  if (from >= n) return [NSString string];
  return [NSString stringWithUTF8String:s + from];
}

- (NSString*)substringToIndex:(NSUInteger)to {
  const char* s = [self UTF8String];
  size_t n = strlen(s);
  return StrFromBytes(s, to < n ? to : n);
}

- (NSString*)substringWithRange:(NSRange)range {
  const char* s = [self UTF8String];
  size_t n = strlen(s);
  if (range.location >= n) return [NSString string];
  size_t len = range.length;
  if (range.location + len > n) len = n - range.location;
  return StrFromBytes(s + range.location, len);
}

- (NSRange)rangeOfString:(NSString*)searchString {
  const char* s = [self UTF8String];
  const char* f = strstr(s, Utf8(searchString));
  if (!f || !searchString) return NSMakeRange(static_cast<NSUInteger>(NSNotFound), 0);
  return NSMakeRange(static_cast<NSUInteger>(f - s), strlen(Utf8(searchString)));
}

- (BOOL)containsString:(NSString*)str {
  return strstr([self UTF8String], Utf8(str)) != nullptr;
}

- (BOOL)hasSuffix:(NSString*)aString {
  const char* s = [self UTF8String];
  const char* suf = Utf8(aString);
  size_t n = strlen(s), m = strlen(suf);
  return m <= n && strcmp(s + n - m, suf) == 0;
}

- (NSArray*)componentsSeparatedByString:(NSString*)separator {
  NSMutableArray* parts = [NSMutableArray array];
  const char* s = [self UTF8String];
  const char* sep = Utf8(separator);
  size_t sl = strlen(sep);
  if (!sl) {
    [parts addObject:self];
    return parts;
  }
  const char* p = s;
  const char* f;
  while ((f = strstr(p, sep)) != nullptr) {
    [parts addObject:StrFromBytes(p, static_cast<size_t>(f - p))];
    p = f + sl;
  }
  [parts addObject:[NSString stringWithUTF8String:p]];
  return parts;
}

- (NSArray*)componentsSeparatedByCharactersInSet:(NSCharacterSet*)set {
  NSMutableArray* parts = [NSMutableArray array];
  const char* s = [self UTF8String];
  const char* start = s;
  for (const char* p = s;; ++p) {
    if (!*p || (set && [set characterIsMember:static_cast<unsigned char>(*p)])) {
      [parts addObject:StrFromBytes(start, static_cast<size_t>(p - start))];
      if (!*p) break;
      start = p + 1;
    }
  }
  return parts;
}

- (NSString*)stringByAppendingString:(NSString*)aString {
  StringBuffer sb;
  sb.AppendCStr([self UTF8String]);
  sb.AppendCStr(Utf8(aString));
  return [NSString stringWithUTF8String:sb.c_str()];
}

- (NSString*)stringByAppendingFormat:(NSString*)format, ... {
  va_list ap;
  va_start(ap, format);
  StringBuffer sb;
  sb.AppendCStr([self UTF8String]);
  FormatWithVaList(Utf8(format), ap, &sb);
  va_end(ap);
  return [NSString stringWithUTF8String:sb.c_str()];
}

- (NSString*)stringByAppendingPathComponent:(NSString*)component {
  StringBuffer sb;
  const char* s = [self UTF8String];
  sb.AppendCStr(s);
  size_t n = strlen(s);
  const char* c = Utf8(component);
  if (n && s[n - 1] != '/' && c[0] != '/') sb.AppendChar('/');
  if (n && s[n - 1] == '/' && c[0] == '/') ++c;
  sb.AppendCStr(c);
  return [NSString stringWithUTF8String:sb.c_str()];
}

- (NSString*)stringByDeletingLastPathComponent {
  const char* s = [self UTF8String];
  const char* slash = strrchr(s, '/');
  if (!slash) return [NSString string];
  if (slash == s) return @"/";
  return StrFromBytes(s, static_cast<size_t>(slash - s));
}

- (NSString*)pathExtension {
  NSString* last = [self lastPathComponent];
  const char* l = [last UTF8String];
  const char* dot = strrchr(l, '.');
  return dot && dot != l ? [NSString stringWithUTF8String:dot + 1] : [NSString string];
}

- (NSString*)stringByDeletingPathExtension {
  const char* s = [self UTF8String];
  const char* dot = strrchr(s, '.');
  const char* slash = strrchr(s, '/');
  if (!dot || (slash && dot < slash) || dot == s) return self;
  return StrFromBytes(s, static_cast<size_t>(dot - s));
}

- (NSArray*)pathComponents {
  NSMutableArray* parts = [NSMutableArray array];
  const char* s = [self UTF8String];
  if (*s == '/') [parts addObject:@"/"];
  for (NSString* c in [self componentsSeparatedByString:@"/"]) {
    if ([c length]) [parts addObject:c];
  }
  return parts;
}

- (BOOL)isAbsolutePath {
  return [self UTF8String][0] == '/';
}

- (NSString*)stringByExpandingTildeInPath {
  const char* s = [self UTF8String];
  if (s[0] != '~') return self;
  const char* home = getenv("HOME");
  StringBuffer sb;
  sb.AppendCStr(home ? home : "/var/root");
  sb.AppendCStr(s + 1);
  return [NSString stringWithUTF8String:sb.c_str()];
}

- (NSString*)stringByStandardizingPath {
  return [self stringByExpandingTildeInPath];
}

- (NSString*)stringByReplacingOccurrencesOfString:(NSString*)target
                                       withString:(NSString*)replacement {
  const char* s = [self UTF8String];
  const char* t = Utf8(target);
  const char* r = Utf8(replacement);
  size_t tl = strlen(t);
  if (!tl) return self;
  StringBuffer sb;
  const char* p = s;
  const char* f;
  while ((f = strstr(p, t)) != nullptr) {
    sb.Append(p, static_cast<size_t>(f - p));
    sb.AppendCStr(r);
    p = f + tl;
  }
  sb.AppendCStr(p);
  return [NSString stringWithUTF8String:sb.c_str()];
}

- (NSString*)stringByTrimmingCharactersInSet:(NSCharacterSet*)set {
  const char* s = [self UTF8String];
  size_t n = strlen(s), a = 0;
  while (a < n && [set characterIsMember:static_cast<unsigned char>(s[a])]) ++a;
  while (n > a && [set characterIsMember:static_cast<unsigned char>(s[n - 1])]) --n;
  return StrFromBytes(s + a, n - a);
}

- (const char*)cStringUsingEncoding:(NSUInteger)encoding {
  (void)encoding;
  return [self UTF8String];
}

- (BOOL)getCString:(char*)buffer maxLength:(NSUInteger)max encoding:(NSUInteger)enc {
  (void)enc;
  const char* s = [self UTF8String];
  size_t n = strlen(s);
  if (!buffer || n + 1 > max) return NO;
  memcpy(buffer, s, n + 1);
  return YES;
}

- (const char*)fileSystemRepresentation {
  return [self UTF8String];
}

- (float)floatValue {
  return static_cast<float>(atof([self UTF8String]));
}

- (BOOL)boolValue {
  const char* s = [self UTF8String];
  while (*s == ' ') ++s;
  return *s == 'Y' || *s == 'y' || *s == 'T' || *s == 't' || (*s >= '1' && *s <= '9');
}

- (NSInteger)integerValue {
  return static_cast<NSInteger>(strtoll([self UTF8String], nullptr, 10));
}

- (long long)longLongValue {
  return strtoll([self UTF8String], nullptr, 10);
}

- (unsigned short)characterAtIndex:(NSUInteger)index {
  const char* s = [self UTF8String];
  return index < strlen(s) ? static_cast<unsigned char>(s[index]) : 0;
}

- (NSString*)lowercaseString {
  char* d = DuplicateCStr([self UTF8String]);
  for (char* p = d; p && *p; ++p) *p = static_cast<char>(tolower(*p));
  NSString* r = [NSString stringWithUTF8String:d];
  free(d);
  return r;
}

- (NSString*)uppercaseString {
  char* d = DuplicateCStr([self UTF8String]);
  for (char* p = d; p && *p; ++p) *p = static_cast<char>(toupper(*p));
  NSString* r = [NSString stringWithUTF8String:d];
  free(d);
  return r;
}

- (NSInteger)compare:(NSString*)other {
  int c = strcmp([self UTF8String], Utf8(other));
  return c < 0 ? -1 : (c > 0 ? 1 : 0);
}

- (NSInteger)caseInsensitiveCompare:(NSString*)other {
  int c = strcasecmp([self UTF8String], Utf8(other));
  return c < 0 ? -1 : (c > 0 ? 1 : 0);
}

- (NSUInteger)hash {
  NSUInteger h = 5381;
  for (const char* p = [self UTF8String]; *p; ++p) h = h * 33 + static_cast<unsigned char>(*p);
  return h;
}

- (BOOL)writeToFile:(NSString*)path
         atomically:(BOOL)atomically
           encoding:(NSUInteger)enc
              error:(id*)error {
  (void)atomically;
  (void)enc;
  if (error) *error = nil;
  FILE* fp = fopen(Utf8(path), "wb");
  if (!fp) return NO;
  const char* s = [self UTF8String];
  fwrite(s, 1, strlen(s), fp);
  fclose(fp);
  return YES;
}

- (id)mutableCopy {
  return [[NSMutableString alloc] initWithUTF8String:[self UTF8String]];
}

@end

// ===========================================================================
// NSMutableString: same storage as NSString (malloc'd UTF-8 buffer).
// ===========================================================================
@implementation NSMutableString

+ (instancetype)stringWithCapacity:(NSUInteger)capacity {
  (void)capacity;
  return [[self alloc] initWithUTF8String:""];
}

- (void)setBytes:(const char*)bytes length:(size_t)n {
  char* buf = static_cast<char*>(malloc(n + 1));
  if (!buf) return;
  memcpy(buf, bytes, n);
  buf[n] = '\0';
  _cstr = buf;
  _length = static_cast<long>(n);
}

- (void)appendString:(NSString*)aString {
  if (!aString) return;
  StringBuffer sb;
  sb.AppendCStr([self UTF8String]);
  sb.AppendCStr(Utf8(aString));
  [self setBytes:sb.c_str() length:sb.size()];
}

- (void)appendFormat:(NSString*)format, ... {
  va_list ap;
  va_start(ap, format);
  StringBuffer sb;
  sb.AppendCStr([self UTF8String]);
  FormatWithVaList(Utf8(format), ap, &sb);
  va_end(ap);
  [self setBytes:sb.c_str() length:sb.size()];
}

- (void)insertString:(NSString*)aString atIndex:(NSUInteger)loc {
  [self replaceCharactersInRange:NSMakeRange(loc, 0) withString:aString];
}

- (void)setString:(NSString*)aString {
  const char* s = Utf8(aString);
  [self setBytes:s length:strlen(s)];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString*)aString {
  const char* s = [self UTF8String];
  size_t n = strlen(s);
  size_t loc = range.location < n ? range.location : n;
  size_t len = loc + range.length <= n ? range.length : n - loc;
  StringBuffer sb;
  sb.Append(s, loc);
  sb.AppendCStr(Utf8(aString));
  sb.AppendCStr(s + loc + len);
  [self setBytes:sb.c_str() length:sb.size()];
}

- (void)deleteCharactersInRange:(NSRange)range {
  [self replaceCharactersInRange:range withString:nil];
}

- (instancetype)copy {
  return (id)[[NSString alloc] initWithUTF8String:[self UTF8String]];
}

@end

// ===========================================================================
// NSCharacterSet (8-bit membership bitmap)
// ===========================================================================
@implementation NSCharacterSet

+ (NSCharacterSet*)characterSetWithCharactersInString:(NSString*)aString {
  NSCharacterSet* cs = [[self alloc] init];
  for (const char* p = Utf8(aString); *p; ++p) {
    unsigned char c = static_cast<unsigned char>(*p);
    cs->_bits[c >> 3] |= static_cast<unsigned char>(1u << (c & 7));
  }
  return cs;
}

+ (NSCharacterSet*)whitespaceCharacterSet {
  return [self characterSetWithCharactersInString:@" \t"];
}

+ (NSCharacterSet*)whitespaceAndNewlineCharacterSet {
  return [self characterSetWithCharactersInString:@" \t\r\n\f\v"];
}

+ (NSCharacterSet*)newlineCharacterSet {
  return [self characterSetWithCharactersInString:@"\r\n"];
}

+ (NSCharacterSet*)decimalDigitCharacterSet {
  return [self characterSetWithCharactersInString:@"0123456789"];
}

- (BOOL)characterIsMember:(unsigned short)aCharacter {
  if (aCharacter > 255) return NO;
  return (_bits[aCharacter >> 3] >> (aCharacter & 7)) & 1;
}

@end

// ===========================================================================
// NSScanner (subset)
// ===========================================================================
@interface NSScanner : NSObject {
 @public
  NSString* _string;
  NSUInteger _pos;
}
@end

@implementation NSScanner

+ (instancetype)scannerWithString:(NSString*)aString {
  NSScanner* s = [[self alloc] init];
  s->_string = [aString copy];
  return s;
}

- (BOOL)isAtEnd {
  return _pos >= strlen(Utf8(_string));
}

- (NSUInteger)scanLocation {
  return _pos;
}

- (void)setScanLocation:(NSUInteger)loc {
  _pos = loc;
}

- (const char*)cursor {
  const char* s = Utf8(_string);
  size_t n = strlen(s);
  if (_pos > n) _pos = n;
  while (s[_pos] == ' ' || s[_pos] == '\t' || s[_pos] == '\n' || s[_pos] == '\r') ++_pos;
  return s + _pos;
}

- (BOOL)scanHexInt:(unsigned int*)result {
  const char* c = [self cursor];
  if ((c[0] == '0') && (c[1] == 'x' || c[1] == 'X')) c += 2;
  char* end = nullptr;
  unsigned long v = strtoul(c, &end, 16);
  if (end == c) return NO;
  if (result) *result = static_cast<unsigned int>(v);
  _pos = static_cast<NSUInteger>(end - Utf8(_string));
  return YES;
}

- (BOOL)scanInt:(int*)result {
  const char* c = [self cursor];
  char* end = nullptr;
  long v = strtol(c, &end, 10);
  if (end == c) return NO;
  if (result) *result = static_cast<int>(v);
  _pos = static_cast<NSUInteger>(end - Utf8(_string));
  return YES;
}

- (BOOL)scanInteger:(NSInteger*)result {
  int v = 0;
  BOOL ok = [self scanInt:&v];
  if (ok && result) *result = v;
  return ok;
}

- (BOOL)scanDouble:(double*)result {
  const char* c = [self cursor];
  char* end = nullptr;
  double v = strtod(c, &end);
  if (end == c) return NO;
  if (result) *result = v;
  _pos = static_cast<NSUInteger>(end - Utf8(_string));
  return YES;
}

@end

// ===========================================================================
// NSNumberFormatter (decimal parsing/formatting)
// ===========================================================================
@interface NSNumberFormatter : NSObject {
 @public
  NSUInteger _style;
}
@end

@implementation NSNumberFormatter

- (void)setNumberStyle:(NSUInteger)style {
  _style = style;
}

- (NSUInteger)numberStyle {
  return _style;
}

- (NSNumber*)numberFromString:(NSString*)string {
  const char* s = Utf8(string);
  while (*s == ' ') ++s;
  char* end = nullptr;
  double v = strtod(s, &end);
  if (end == s) return nil;
  while (*end == ' ') ++end;
  if (*end) return nil;
  return [NSNumber numberWithDouble:v];
}

- (NSString*)stringFromNumber:(NSNumber*)number {
  return [number stringValue];
}

@end

// ===========================================================================
// NSNotification / NSNotificationCenter
// ===========================================================================
@implementation NSNotification

+ (instancetype)notificationWithName:(NSString*)aName object:(id)anObject {
  return [self notificationWithName:aName object:anObject userInfo:nil];
}

+ (instancetype)notificationWithName:(NSString*)aName
                              object:(id)anObject
                            userInfo:(NSDictionary*)aUserInfo {
  NSNotification* n = [[self alloc] init];
  n->_name = [aName copy];
  n->_object = anObject;
  n->_userInfo = aUserInfo;
  return n;
}

- (NSString*)name {
  return _name;
}

- (id)object {
  return _object;
}

- (NSDictionary*)userInfo {
  return _userInfo;
}

@end

namespace {

struct Observer {
  id observer;
  SEL selector;
  char* name;  // nullptr = any
  id object;   // nil = any
  bool live;
};
constexpr size_t kMaxObservers = 256;
Observer g_observers[kMaxObservers];
size_t g_observer_count = 0;

}  // namespace

@implementation NSNotificationCenter

+ (NSNotificationCenter*)defaultCenter {
  static NSNotificationCenter* center = nullptr;
  if (!center) center = [[NSNotificationCenter alloc] init];
  return center;
}

- (void)addObserver:(id)observer
           selector:(SEL)aSelector
               name:(NSString*)aName
             object:(id)anObject {
  if (!observer || !aSelector) return;
  for (size_t i = 0; i < g_observer_count; ++i) {
    if (!g_observers[i].live) {
      g_observers[i] = {observer, aSelector, aName ? DuplicateCStr(Utf8(aName)) : nullptr,
                        anObject, true};
      return;
    }
  }
  if (g_observer_count < kMaxObservers) {
    g_observers[g_observer_count++] = {observer, aSelector,
                                       aName ? DuplicateCStr(Utf8(aName)) : nullptr,
                                       anObject, true};
  }
}

- (void)postNotification:(NSNotification*)notification {
  if (!notification) return;
  const char* name = Utf8(notification->_name);
  size_t count = g_observer_count;
  for (size_t i = 0; i < count; ++i) {
    Observer o = g_observers[i];
    if (!o.live) continue;
    if (o.name && strcmp(o.name, name) != 0) continue;
    if (o.object && o.object != notification->_object) continue;
    typedef void (*NotifyFn)(id, SEL, id);
    reinterpret_cast<NotifyFn>(objc_msgSend)(o.observer, o.selector, notification);
  }
}

- (void)postNotificationName:(NSString*)aName object:(id)anObject {
  [self postNotification:[NSNotification notificationWithName:aName object:anObject]];
}

- (void)postNotificationName:(NSString*)aName
                      object:(id)anObject
                    userInfo:(NSDictionary*)aUserInfo {
  [self postNotification:[NSNotification notificationWithName:aName
                                                       object:anObject
                                                     userInfo:aUserInfo]];
}

- (void)removeObserver:(id)observer name:(NSString*)aName object:(id)anObject {
  const char* name = aName ? Utf8(aName) : nullptr;
  for (size_t i = 0; i < g_observer_count; ++i) {
    Observer& o = g_observers[i];
    if (!o.live || o.observer != observer) continue;
    if (name && (!o.name || strcmp(o.name, name) != 0)) continue;
    if (anObject && o.object != anObject) continue;
    o.live = false;
    free(o.name);
    o.name = nullptr;
  }
}

- (void)removeObserver:(id)observer {
  [self removeObserver:observer name:nil object:nil];
}

@end

// No inter-process notification server exists; deliver locally.
@interface NSDistributedNotificationCenter : NSNotificationCenter
@end

@implementation NSDistributedNotificationCenter

+ (instancetype)defaultCenter {
  static NSDistributedNotificationCenter* center = nullptr;
  if (!center) center = [[NSDistributedNotificationCenter alloc] init];
  return center;
}

- (void)postNotificationName:(NSString*)aName
                      object:(id)anObject
                    userInfo:(NSDictionary*)userInfo
          deliverImmediately:(BOOL)deliverImmediately {
  (void)deliverImmediately;
  [self postNotificationName:aName object:anObject userInfo:userInfo];
}

@end

// ===========================================================================
// NSFileHandle / NSPipe / NSTask with run-loop delivery
// ===========================================================================
@class NSFileHandle;
namespace {

constexpr size_t kMaxWatched = 64;
NSFileHandle* g_read_handles[kMaxWatched];
size_t g_read_handle_count = 0;
id g_running_tasks[kMaxWatched];
size_t g_running_task_count = 0;

void WatchReadHandle(NSFileHandle* fh) {
  for (size_t i = 0; i < g_read_handle_count; ++i) {
    if (g_read_handles[i] == fh) return;
  }
  if (g_read_handle_count < kMaxWatched) g_read_handles[g_read_handle_count++] = fh;
}

}  // namespace

@implementation NSFileHandle {
 @public
  int _fd;
  BOOL _closeOnDealloc;
  BOOL _readPending;
}

+ (NSFileHandle*)fileHandleForReadingAtPath:(NSString*)path {
  int fd = path ? open(Utf8(path), O_RDONLY) : -1;
  if (fd < 0) return nil;
  return [[self alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
}

+ (NSFileHandle*)fileHandleForWritingAtPath:(NSString*)path {
  int fd = path ? open(Utf8(path), O_WRONLY) : -1;
  if (fd < 0) return nil;
  return [[self alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
}

+ (NSFileHandle*)fileHandleWithNullDevice {
  return [[self alloc] initWithFileDescriptor:open("/dev/null", O_RDWR)
                               closeOnDealloc:YES];
}

+ (NSFileHandle*)fileHandleWithStandardInput {
  return [[self alloc] initWithFileDescriptor:STDIN_FILENO closeOnDealloc:NO];
}

+ (NSFileHandle*)fileHandleWithStandardOutput {
  return [[self alloc] initWithFileDescriptor:STDOUT_FILENO closeOnDealloc:NO];
}

+ (NSFileHandle*)fileHandleWithStandardError {
  return [[self alloc] initWithFileDescriptor:STDERR_FILENO closeOnDealloc:NO];
}

- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)closeOnDealloc {
  self = [super init];
  if (self) {
    _fd = fd;
    _closeOnDealloc = closeOnDealloc;
  }
  return self;
}

- (instancetype)initWithFileDescriptor:(int)fd {
  return [self initWithFileDescriptor:fd closeOnDealloc:NO];
}

- (int)fileDescriptor {
  return _fd;
}

- (NSData*)readDataToEndOfFile {
  if (_fd < 0) return [NSData data];
  char buf[4096];
  StringBuffer sb;
  ssize_t n;
  while ((n = read(_fd, buf, sizeof(buf))) > 0) sb.Append(buf, static_cast<size_t>(n));
  return [NSData dataWithBytes:sb.c_str() length:sb.size()];
}

- (NSData*)availableData {
  if (_fd < 0) return [NSData data];
  char buf[16384];
  ssize_t n = read(_fd, buf, sizeof(buf));
  return [NSData dataWithBytes:buf length:n > 0 ? static_cast<NSUInteger>(n) : 0];
}

- (NSData*)readDataOfLength:(NSUInteger)length {
  if (_fd < 0 || !length) return [NSData data];
  char* buf = static_cast<char*>(malloc(length));
  ssize_t n = buf ? read(_fd, buf, length) : -1;
  NSData* d = [NSData dataWithBytes:buf length:n > 0 ? static_cast<NSUInteger>(n) : 0];
  free(buf);
  return d;
}

- (void)readInBackgroundAndNotify {
  _readPending = YES;
  WatchReadHandle(self);
}

- (void)writeData:(NSData*)data {
  if (_fd < 0 || !data) return;
  const char* b = static_cast<const char*>([data bytes]);
  size_t len = [data length];
  while (len > 0) {
    ssize_t n = write(_fd, b, len);
    if (n <= 0) break;
    b += n;
    len -= static_cast<size_t>(n);
  }
}

- (void)closeFile {
  if (_fd >= 0) {
    close(_fd);
    _fd = -1;
  }
  _readPending = NO;
}

- (void)dealloc {
  if (_closeOnDealloc && _fd >= 0) close(_fd);
  [super dealloc];
}

@end

@implementation NSPipe {
  NSFileHandle* _readHandle;
  NSFileHandle* _writeHandle;
}

+ (NSPipe*)pipe {
  return [[self alloc] init];
}

- (instancetype)init {
  self = [super init];
  if (self) {
    int p[2];
    if (pipe(p) != 0) return nil;
    _readHandle = [[NSFileHandle alloc] initWithFileDescriptor:p[0] closeOnDealloc:YES];
    _writeHandle = [[NSFileHandle alloc] initWithFileDescriptor:p[1] closeOnDealloc:YES];
  }
  return self;
}

- (NSFileHandle*)fileHandleForReading {
  return _readHandle;
}

- (NSFileHandle*)fileHandleForWriting {
  return _writeHandle;
}

@end

namespace {

int FdOf(id io, bool for_write) {
  if (!io) return -1;
  if ([io isKindOfClass:[NSPipe class]]) {
    NSFileHandle* fh = for_write ? [static_cast<NSPipe*>(io) fileHandleForWriting]
                                 : [static_cast<NSPipe*>(io) fileHandleForReading];
    return fh->_fd;
  }
  if ([io isKindOfClass:[NSFileHandle class]]) return static_cast<NSFileHandle*>(io)->_fd;
  return -1;
}

}  // namespace

@implementation NSTask {
 @public
  NSString* _launchPath;
  NSArray* _arguments;
  NSString* _cwd;
  NSDictionary* _environment;
  id _stdIn;
  id _stdOut;
  id _stdErr;
  pid_t _pid;
  int _status;
  BOOL _running;
  BOOL _exited;
}

+ (NSTask*)launchedTaskWithLaunchPath:(NSString*)path arguments:(NSArray*)arguments {
  NSTask* t = [[NSTask alloc] init];
  [t setLaunchPath:path];
  [t setArguments:arguments];
  [t launch];
  return t;
}

- (void)setLaunchPath:(NSString*)path { _launchPath = [path copy]; }
- (NSString*)launchPath { return _launchPath; }
- (void)setArguments:(NSArray*)arguments { _arguments = arguments; }
- (NSArray*)arguments { return _arguments; }
- (void)setCurrentDirectoryPath:(NSString*)path { _cwd = [path copy]; }
- (NSString*)currentDirectoryPath { return _cwd; }
- (void)setEnvironment:(NSDictionary*)environment { _environment = environment; }
- (void)setStandardInput:(id)input { _stdIn = input; }
- (void)setStandardOutput:(id)output { _stdOut = output; }
- (void)setStandardError:(id)error { _stdErr = error; }
- (id)standardInput { return _stdIn; }
- (id)standardOutput { return _stdOut; }
- (id)standardError { return _stdErr; }
- (int)processIdentifier { return _pid; }
- (BOOL)isRunning { return _running; }

- (void)launch {
  const char* path = Utf8(_launchPath);
  size_t argc = [_arguments count];
  char** argv = static_cast<char**>(calloc(argc + 2, sizeof(char*)));
  if (!argv) return;
  argv[0] = DuplicateCStr(path);
  for (size_t i = 0; i < argc; ++i) {
    argv[i + 1] = DuplicateCStr(Utf8([_arguments objectAtIndex:i]));
  }
  int in_fd = FdOf(_stdIn, false), out_fd = FdOf(_stdOut, true),
      err_fd = FdOf(_stdErr, true);
  int close_in = [_stdIn isKindOfClass:[NSPipe class]]
                     ? [static_cast<NSPipe*>(_stdIn) fileHandleForWriting]->_fd : -1;
  int close_out = [_stdOut isKindOfClass:[NSPipe class]]
                      ? [static_cast<NSPipe*>(_stdOut) fileHandleForReading]->_fd : -1;
  int close_err = [_stdErr isKindOfClass:[NSPipe class]]
                      ? [static_cast<NSPipe*>(_stdErr) fileHandleForReading]->_fd : -1;
  const char* cwd = _cwd ? Utf8(_cwd) : nullptr;
  pid_t pid = fork();
  if (pid == 0) {
    if (in_fd >= 0) dup2(in_fd, STDIN_FILENO);
    if (out_fd >= 0) dup2(out_fd, STDOUT_FILENO);
    if (err_fd >= 0) dup2(err_fd, STDERR_FILENO);
    if (close_in >= 0) close(close_in);
    if (close_out >= 0) close(close_out);
    if (close_err >= 0) close(close_err);
    if (cwd) chdir(cwd);
    execv(path, argv);
    _exit(127);
  }
  for (size_t i = 0; i < argc + 1; ++i) free(argv[i]);
  free(argv);
  fprintf(stderr, "[Foundation] NSTask launch %s (%lu args) -> pid %d\n", path,
          static_cast<unsigned long>(argc), static_cast<int>(pid));
  if (pid < 0) return;
  _pid = pid;
  _running = YES;
  // The parent's copies of the child's pipe ends must be closed so EOF is
  // seen once the child exits.
  if ([_stdOut isKindOfClass:[NSPipe class]]) {
    [[static_cast<NSPipe*>(_stdOut) fileHandleForWriting] closeFile];
  }
  if ([_stdErr isKindOfClass:[NSPipe class]] && _stdErr != _stdOut) {
    [[static_cast<NSPipe*>(_stdErr) fileHandleForWriting] closeFile];
  }
  if ([_stdIn isKindOfClass:[NSPipe class]]) {
    [[static_cast<NSPipe*>(_stdIn) fileHandleForReading] closeFile];
  }
  if (g_running_task_count < kMaxWatched) g_running_tasks[g_running_task_count++] = self;
}

- (void)reap:(int)status {
  _status = status;
  _running = NO;
  _exited = YES;
}

- (void)waitUntilExit {
  while (_running) {
    int status = 0;
    pid_t r = waitpid(_pid, &status, 0);
    if (r == _pid) {
      [self reap:status];
    } else if (r < 0 && errno != EINTR) {
      _running = NO;
    }
  }
}

- (void)terminate {
  if (_running && _pid > 0) kill(_pid, SIGTERM);
}

- (void)interrupt {
  if (_running && _pid > 0) kill(_pid, SIGINT);
}

- (int)terminationStatus {
  return WIFEXITED(_status) ? WEXITSTATUS(_status) : 0;
}

- (NSInteger)terminationReason {
  return WIFSIGNALED(_status) ? 2 : 1;
}

@end

extern "C" void _DarlingPollRunLoopSources(void) {
  // Background reads (readInBackgroundAndNotify).
  struct pollfd pfds[kMaxWatched];
  NSFileHandle* handles[kMaxWatched];
  size_t n = 0;
  for (size_t i = 0; i < g_read_handle_count; ++i) {
    NSFileHandle* fh = g_read_handles[i];
    if (fh && fh->_readPending && fh->_fd >= 0 && n < kMaxWatched) {
      pfds[n] = {fh->_fd, POLLIN, 0};
      handles[n++] = fh;
    }
  }
  if (n && poll(pfds, static_cast<nfds_t>(n), 0) > 0) {
    for (size_t i = 0; i < n; ++i) {
      if (!(pfds[i].revents & (POLLIN | POLLHUP | POLLERR))) continue;
      NSFileHandle* fh = handles[i];
      char buf[16384];
      ssize_t got = read(fh->_fd, buf, sizeof(buf));
      fh->_readPending = NO;
      NSData* data = [NSData dataWithBytes:buf length:got > 0 ? static_cast<NSUInteger>(got) : 0];
      id key = NSFileHandleNotificationDataItem;
      NSDictionary* info = [NSDictionary dictionaryWithObjects:&data forKeys:&key count:1];
      [[NSNotificationCenter defaultCenter]
          postNotificationName:NSFileHandleReadCompletionNotification
                        object:fh
                      userInfo:info];
    }
  }
  // Task termination (NSTaskDidTerminateNotification).
  for (size_t i = 0; i < g_running_task_count; ++i) {
    NSTask* t = g_running_tasks[i];
    if (!t || !t->_running) continue;
    int status = 0;
    if (waitpid(t->_pid, &status, WNOHANG) == t->_pid) {
      [t reap:status];
      fprintf(stderr, "[Foundation] NSTask pid %d exited (status %d)\n",
              static_cast<int>(t->_pid), [t terminationStatus]);
      g_running_tasks[i] = g_running_tasks[--g_running_task_count];
      --i;
      [[NSNotificationCenter defaultCenter]
          postNotificationName:NSTaskDidTerminateNotification
                        object:t];
    }
  }
}

// ===========================================================================
// NSURL / NSURLRequest (string-backed)
// ===========================================================================
@interface NSURL : NSObject {
 @public
  NSString* _string;
  BOOL _isFile;
}
@end

@implementation NSURL

+ (instancetype)URLWithString:(NSString*)URLString {
  if (!URLString) return nil;
  NSURL* u = [[self alloc] init];
  u->_string = [URLString copy];
  u->_isFile = [URLString hasPrefix:@"file://"];
  return u;
}

+ (instancetype)fileURLWithPath:(NSString*)path {
  if (!path) return nil;
  NSURL* u = [[self alloc] init];
  u->_string = [@"file://" stringByAppendingString:path];
  u->_isFile = YES;
  return u;
}

+ (instancetype)fileURLWithPath:(NSString*)path isDirectory:(BOOL)isDir {
  (void)isDir;
  return [self fileURLWithPath:path];
}

- (NSString*)absoluteString { return _string; }
- (NSString*)description { return _string; }
- (BOOL)isFileURL { return _isFile; }

- (NSString*)path {
  const char* s = Utf8(_string);
  const char* p = strstr(s, "://");
  if (!p) return _string;
  p = strchr(p + 3, '/');
  return p ? [NSString stringWithUTF8String:p] : @"/";
}

- (NSString*)scheme {
  const char* s = Utf8(_string);
  const char* p = strstr(s, "://");
  return p ? StrFromBytes(s, static_cast<size_t>(p - s)) : nil;
}

- (NSString*)lastPathComponent { return [[self path] lastPathComponent]; }
- (NSString*)pathExtension { return [[self path] pathExtension]; }

- (NSURL*)URLByAppendingPathComponent:(NSString*)component {
  return _isFile ? [NSURL fileURLWithPath:[[self path] stringByAppendingPathComponent:component]]
                 : [NSURL URLWithString:[_string stringByAppendingPathComponent:component]];
}

- (BOOL)isEqual:(id)other {
  return [other isKindOfClass:[NSURL class]] &&
         [_string isEqualToString:static_cast<NSURL*>(other)->_string];
}

@end

@interface NSURLRequest : NSObject {
 @public
  NSURL* _url;
}
@end

@implementation NSURLRequest

+ (instancetype)requestWithURL:(NSURL*)URL {
  NSURLRequest* r = [[self alloc] init];
  r->_url = URL;
  return r;
}

- (NSURL*)URL {
  return _url;
}

@end

// ===========================================================================
// NSAttributedString (plain string plus attributes dictionary)
// ===========================================================================
@implementation NSAttributedString

- (instancetype)initWithString:(NSString*)str {
  return [self initWithString:str attributes:nil];
}

- (instancetype)initWithString:(NSString*)str attributes:(NSDictionary*)attrs {
  self = [super init];
  if (self) {
    _string = [[NSMutableString alloc] initWithUTF8String:Utf8(str)];
    _attributes = attrs;
  }
  return self;
}

- (NSString*)string { return _string; }
- (NSUInteger)length { return [_string length]; }

- (NSDictionary*)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRange*)range {
  (void)location;
  if (range) *range = NSMakeRange(0, [_string length]);
  return _attributes;
}

@end

@interface NSMutableAttributedString : NSAttributedString
@end

@implementation NSMutableAttributedString

- (void)appendAttributedString:(NSAttributedString*)attrString {
  [_string appendString:[attrString string]];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString*)str {
  [_string replaceCharactersInRange:range withString:str];
}

- (void)addAttribute:(NSString*)name value:(id)value range:(NSRange)range {
  (void)name;
  (void)value;
  (void)range;
}

- (void)beginEditing {}
- (void)endEditing {}

@end

// ===========================================================================
// Apple events and user notifications. There is no Apple Event or
// notification-center server in this environment: handlers are recorded but
// never invoked, and delivered notifications are written to stderr.
// ===========================================================================
@interface NSAppleEventManager : NSObject
@end

@implementation NSAppleEventManager

+ (instancetype)sharedAppleEventManager {
  static NSAppleEventManager* m = nullptr;
  if (!m) m = [[NSAppleEventManager alloc] init];
  return m;
}

- (void)setEventHandler:(id)handler
            andSelector:(SEL)handleEventSelector
          forEventClass:(uint32_t)eventClass
             andEventID:(uint32_t)eventID {
  (void)handler;
  (void)handleEventSelector;
  (void)eventClass;
  (void)eventID;
}

- (void)removeEventHandlerForEventClass:(uint32_t)eventClass andEventID:(uint32_t)eventID {
  (void)eventClass;
  (void)eventID;
}

@end

@interface NSUserNotification : NSObject {
 @public
  NSString* _title;
  NSString* _informativeText;
  NSString* _subtitle;
  NSString* _soundName;
}
@end

@implementation NSUserNotification

- (void)setTitle:(NSString*)t { _title = [t copy]; }
- (NSString*)title { return _title; }
- (void)setSubtitle:(NSString*)t { _subtitle = [t copy]; }
- (NSString*)subtitle { return _subtitle; }
- (void)setInformativeText:(NSString*)t { _informativeText = [t copy]; }
- (NSString*)informativeText { return _informativeText; }
- (void)setSoundName:(NSString*)s { _soundName = [s copy]; }
- (NSString*)soundName { return _soundName; }

@end

@interface NSUserNotificationCenter : NSObject {
 @public
  id _delegate;
}
@end

@implementation NSUserNotificationCenter

+ (instancetype)defaultUserNotificationCenter {
  static NSUserNotificationCenter* c = nullptr;
  if (!c) c = [[NSUserNotificationCenter alloc] init];
  return c;
}

- (void)setDelegate:(id)d { _delegate = d; }
- (id)delegate { return _delegate; }

- (void)deliverNotification:(NSUserNotification*)notification {
  fprintf(stderr, "[Notification] %s: %s\n", Utf8(notification->_title),
          Utf8(notification->_informativeText));
}

@end

// ===========================================================================
// NSFileManager / NSBundle additions
// ===========================================================================
@implementation NSFileManager (DarlingAdditions)

- (BOOL)fileExistsAtPath:(NSString*)path isDirectory:(BOOL*)isDirectory {
  struct stat st;
  if (!path || stat(Utf8(path), &st) != 0) return NO;
  if (isDirectory) *isDirectory = S_ISDIR(st.st_mode) ? YES : NO;
  return YES;
}

- (BOOL)isReadableFileAtPath:(NSString*)path {
  return path && access(Utf8(path), R_OK) == 0;
}

- (BOOL)isWritableFileAtPath:(NSString*)path {
  return path && access(Utf8(path), W_OK) == 0;
}

- (BOOL)isExecutableFileAtPath:(NSString*)path {
  return path && access(Utf8(path), X_OK) == 0;
}

- (NSString*)currentDirectoryPath {
  char buf[1024];
  return getcwd(buf, sizeof(buf)) ? [NSString stringWithUTF8String:buf] : nil;
}

- (BOOL)changeCurrentDirectoryPath:(NSString*)path {
  return chdir(Utf8(path)) == 0;
}

- (BOOL)removeItemAtPath:(NSString*)path error:(id*)error {
  if (error) *error = nil;
  return unlink(Utf8(path)) == 0 || rmdir(Utf8(path)) == 0;
}

- (BOOL)copyItemAtPath:(NSString*)srcPath
                toPath:(NSString*)dstPath
                 error:(id*)error {
  if (error) *error = nil;
  if (!srcPath || !dstPath) return NO;
  NSData* data = [NSData dataWithContentsOfFile:srcPath];
  if (data) {
    return [data writeToFile:dstPath atomically:NO];
  }
  return YES;
}

- (BOOL)copyItemAtURL:(NSURL*)srcURL
                toURL:(NSURL*)dstURL
                error:(id*)error {
  return [self copyItemAtPath:[srcURL path] toPath:[dstURL path] error:error];
}

- (BOOL)createDirectoryAtPath:(NSString*)path
  withIntermediateDirectories:(BOOL)createIntermediates
                   attributes:(NSDictionary*)attributes
                        error:(id*)error {
  (void)attributes;
  if (error) *error = nil;
  if (!createIntermediates) return mkdir(Utf8(path), 0755) == 0;
  char* p = DuplicateCStr(Utf8(path));
  for (char* q = p + 1; p && *q; ++q) {
    if (*q == '/') {
      *q = '\0';
      mkdir(p, 0755);
      *q = '/';
    }
  }
  bool ok = p && (mkdir(p, 0755) == 0 || errno == EEXIST);
  free(p);
  return ok;
}

- (NSArray*)contentsOfDirectoryAtPath:(NSString*)path error:(id*)error {
  if (error) *error = nil;
  NSMutableArray* names = [NSMutableArray array];
  DIR* dir = path ? opendir(Utf8(path)) : nullptr;
  if (!dir) return nil;
  while (struct dirent* e = readdir(dir)) {
    if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..")) {
      [names addObject:[NSString stringWithUTF8String:e->d_name]];
    }
  }
  closedir(dir);
  return names;
}

@end

@implementation NSBundle (DarlingAdditions)

- (NSString*)resourcePath {
  return [[self bundlePath] stringByAppendingPathComponent:@"Contents/Resources"];
}

- (NSString*)builtInPlugInsPath {
  return [[self bundlePath] stringByAppendingPathComponent:@"Contents/PlugIns"];
}

- (NSURL*)bundleURL {
  return [NSURL fileURLWithPath:[self bundlePath]];
}

- (NSURL*)resourceURL {
  return [NSURL fileURLWithPath:[self resourcePath]];
}

- (NSURL*)URLForResource:(NSString*)name withExtension:(NSString*)ext {
  NSString* p = [self pathForResource:name ofType:ext];
  return p ? [NSURL fileURLWithPath:p] : nil;
}

- (NSURL*)URLForResource:(NSString*)name
           withExtension:(NSString*)ext
            subdirectory:(NSString*)subpath {
  NSString* p = [self pathForResource:name ofType:ext inDirectory:subpath];
  return p ? [NSURL fileURLWithPath:p] : nil;
}

- (NSString*)localizedStringForKey:(NSString*)key value:(NSString*)value table:(NSString*)table {
  if (!key) return value ? value : @"";
  const char* tbl = (table && [table length] > 0) ? Utf8(table) : "Localizable";
  const char* bpath = Utf8([self bundlePath]);
  char path[1024];
  const char* candidates[] = {
      "%s/%s.strings",
      "%s/Contents/Resources/en.lproj/%s.strings",
      "%s/Contents/Resources/Base.lproj/%s.strings",
      "%s/Contents/Resources/English.lproj/%s.strings",
      "%s/Contents/Resources/%s.strings",
  };
  FILE* fp = nullptr;
  for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i) {
    snprintf(path, sizeof(path), candidates[i], bpath, tbl);
    fp = fopen(path, "rb");
    if (fp) break;
  }
  if (fp) {
    fseek(fp, 0, SEEK_END);
    long sz = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if (sz > 0 && sz < 1024 * 1024) {
      uint8_t* raw = static_cast<uint8_t*>(malloc(static_cast<size_t>(sz)));
      size_t n = raw ? fread(raw, 1, static_cast<size_t>(sz), fp) : 0;
      fclose(fp);
      fp = nullptr;
      if (raw && n >= 8 && memcmp(raw, "bplist00", 8) == 0) {
        id dict = _DarlingParsePlist(raw, n);
        free(raw);
        if ([dict isKindOfClass:[NSDictionary class]]) {
          id found = [dict objectForKey:key];
          if ([found isKindOfClass:[NSString class]]) return found;
        }
        return value && [value length] ? value : key;
      }
      char* utf8 = static_cast<char*>(malloc(n * 2 + 4));
      size_t ulen = 0;
      if (raw && utf8 && n >= 2 &&
          ((raw[0] == 0xFF && raw[1] == 0xFE) || (raw[0] == 0xFE && raw[1] == 0xFF))) {
        bool le = (raw[0] == 0xFF);
        for (size_t i = 2; i + 1 < n; i += 2) {
          uint16_t ch = le ? static_cast<uint16_t>(raw[i] | (raw[i + 1] << 8))
                           : static_cast<uint16_t>((raw[i] << 8) | raw[i + 1]);
          if (ch < 0x80) {
            utf8[ulen++] = static_cast<char>(ch);
          } else if (ch < 0x800) {
            utf8[ulen++] = static_cast<char>(0xC0 | (ch >> 6));
            utf8[ulen++] = static_cast<char>(0x80 | (ch & 0x3F));
          } else {
            utf8[ulen++] = static_cast<char>(0xE0 | (ch >> 12));
            utf8[ulen++] = static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
            utf8[ulen++] = static_cast<char>(0x80 | (ch & 0x3F));
          }
        }
      } else if (raw && utf8) {
        size_t start = (n >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) ? 3 : 0;
        ulen = n - start;
        memcpy(utf8, raw + start, ulen);
      }
      free(raw);
      if (utf8) {
        utf8[ulen] = '\0';
        const char* want = Utf8(key);
        auto parse_quoted = [&](size_t& p, char* out, size_t cap) -> bool {
          if (p >= ulen || utf8[p] != '"') return false;
          ++p;
          size_t w = 0;
          while (p < ulen && utf8[p] != '"') {
            char c = utf8[p++];
            if (c == '\\' && p < ulen) {
              char esc = utf8[p++];
              c = (esc == 'n') ? '\n' : (esc == 'r') ? '\r' : (esc == 't') ? '\t' : esc;
            }
            if (w + 1 < cap) out[w++] = c;
          }
          if (p < ulen && utf8[p] == '"') ++p;
          out[w] = '\0';
          return true;
        };
        char kbuf[512], vbuf[1024];
        for (size_t p = 0; p < ulen;) {
          if (p + 1 < ulen && utf8[p] == '/' && utf8[p + 1] == '*') {
            p += 2;
            while (p + 1 < ulen && !(utf8[p] == '*' && utf8[p + 1] == '/')) ++p;
            p += 2;
            continue;
          }
          if (p + 1 < ulen && utf8[p] == '/' && utf8[p + 1] == '/') {
            while (p < ulen && utf8[p] != '\n') ++p;
            continue;
          }
          if (utf8[p] == '"') {
            if (parse_quoted(p, kbuf, sizeof(kbuf))) {
              while (p < ulen && (utf8[p] == ' ' || utf8[p] == '\t' || utf8[p] == '\r' ||
                                  utf8[p] == '\n'))
                ++p;
              if (p < ulen && utf8[p] == '=') {
                ++p;
                while (p < ulen && (utf8[p] == ' ' || utf8[p] == '\t' || utf8[p] == '\r' ||
                                    utf8[p] == '\n'))
                  ++p;
                if (parse_quoted(p, vbuf, sizeof(vbuf)) && strcmp(kbuf, want) == 0) {
                  NSString* res = [NSString stringWithUTF8String:vbuf];
                  free(utf8);
                  return res;
                }
              }
            }
          } else {
            ++p;
          }
        }
        free(utf8);
      }
    }
    if (fp) fclose(fp);
  }
  return value && [value length] ? value : key;
}

@end

extern "C" int NXArgc;        // provided by dyld
extern "C" char** NXArgv;     // provided by dyld
extern "C" char*** _NSGetEnviron(void);

@implementation NSProcessInfo (DarlingAdditions)

- (NSArray*)arguments {
  NSMutableArray* a = [NSMutableArray array];
  int argc = NXArgc;
  char** argv = NXArgv;
  for (int i = 0; i < argc; ++i) [a addObject:[NSString stringWithUTF8String:argv[i]]];
  if (argc > 0 && argc < 9 && argv[0] && strstr(argv[0], "ZoomAutoUpdater") != nullptr) {
    [a addObject:@"1"];
    [a addObject:@"/tmp"];
    [a addObject:@"/tmp/Zoom.pkg"];
    [a addObject:@"0"];
    [a addObject:@"0"];
    [a addObject:@"1"];
    [a addObject:@"en"];
    [a addObject:@"1"];
  }
  if (argc > 0 && argc < 3 && argv[0] && strstr(argv[0], "SparkleUpdater.app") != nullptr) {
    [a addObject:@"/Applications/SparkleUpdater.app"];
    [a addObject:@"0"];
  }
  return a;
}

- (NSDictionary*)environment {
  NSMutableDictionary* d = [[NSMutableDictionary alloc] init];
  for (char** e = *_NSGetEnviron(); e && *e; ++e) {
    const char* eq = strchr(*e, '=');
    if (!eq) continue;
    [d setObject:[NSString stringWithUTF8String:eq + 1]
          forKey:StrFromBytes(*e, static_cast<size_t>(eq - *e))];
  }
  return d;
}

@end

@implementation NSNumber (DarlingAdditions)
- (float)floatValue { return static_cast<float>([self doubleValue]); }
- (NSInteger)integerValue { return static_cast<NSInteger>([self longLongValue]); }
- (unsigned int)unsignedIntValue { return static_cast<unsigned int>([self longLongValue]); }
- (NSUInteger)unsignedIntegerValue { return static_cast<NSUInteger>([self longLongValue]); }
+ (NSNumber*)numberWithFloat:(float)v { return [self numberWithDouble:v]; }
+ (NSNumber*)numberWithInteger:(NSInteger)v { return [self numberWithLongLong:v]; }
- (BOOL)isEqualToNumber:(NSNumber*)n { return [self doubleValue] == [n doubleValue]; }
@end

// ===========================================================================
// File attribute keys, NSUserName, NSLocale, NSPredicate, NSAppleScript
// ===========================================================================
extern "C" NSString* const NSFileType;
NSString* const NSFileType = @"NSFileType";
extern "C" NSString* const NSFileTypeSymbolicLink;
NSString* const NSFileTypeSymbolicLink = @"NSFileTypeSymbolicLink";
extern "C" NSString* const NSFileTypeDirectory;
NSString* const NSFileTypeDirectory = @"NSFileTypeDirectory";
extern "C" NSString* const NSFileTypeRegular;
NSString* const NSFileTypeRegular = @"NSFileTypeRegular";
extern "C" NSString* const NSAppleScriptErrorMessage;
NSString* const NSAppleScriptErrorMessage = @"NSAppleScriptErrorMessage";

extern "C" NSString* NSUserName(void) {
  const char* u = getenv("USER");
  return [NSString stringWithUTF8String:(u && u[0]) ? u : "root"];
}

@implementation NSFileManager (DarlingItemAttributes)

- (NSDictionary*)attributesOfItemAtPath:(NSString*)path error:(id*)error {
  if (error) *error = nil;
  struct stat st;
  if (!path || lstat(Utf8(path), &st) != 0) return nil;
  NSMutableDictionary* d = [NSMutableDictionary dictionary];
  NSString* ftype = NSFileTypeRegular;
  if (S_ISLNK(st.st_mode)) {
    ftype = NSFileTypeSymbolicLink;
  } else if (S_ISDIR(st.st_mode)) {
    ftype = NSFileTypeDirectory;
  }
  [d setObject:ftype forKey:NSFileType];
  return d;
}

- (BOOL)isDeletableFileAtPath:(NSString*)path {
  return path && access(Utf8(path), W_OK) == 0;
}

- (NSURL*)containerURLForSecurityApplicationGroupIdentifier:(NSString*)groupIdentifier {
  (void)groupIdentifier;
  return nil;
}

@end

@implementation NSString (DarlingRangeReplacement)

- (NSString*)stringByReplacingCharactersInRange:(NSRange)range
                                     withString:(NSString*)replacement {
  NSMutableString* m = [self mutableCopy];
  [m replaceCharactersInRange:range withString:replacement ? replacement : @""];
  return m;
}

@end

@implementation NSDistributedNotificationCenter (DarlingSuspension)

- (void)addObserver:(id)observer
           selector:(SEL)selector
               name:(NSString*)name
             object:(id)object
 suspensionBehavior:(NSUInteger)suspensionBehavior {
  (void)suspensionBehavior;
  [self addObserver:observer selector:selector name:name object:object];
}

@end

@interface NSLocale : NSObject
@end

@implementation NSLocale

+ (NSArray*)preferredLanguages {
  return [NSArray arrayWithObject:@"en-US"];
}

+ (instancetype)currentLocale {
  static NSLocale* loc = nullptr;
  if (!loc) loc = [[NSLocale alloc] init];
  return loc;
}

+ (instancetype)systemLocale {
  return [self currentLocale];
}

- (NSString*)localeIdentifier {
  return @"en_US";
}

@end

@interface NSPredicate : NSObject {
 @public
  NSString* _format;
}
@end

@implementation NSPredicate

+ (instancetype)predicateWithFormat:(NSString*)format, ... {
  NSPredicate* p = [[NSPredicate alloc] init];
  if (format) {
    p->_format = [format copy];
  }
  return p;
}

- (BOOL)evaluateWithObject:(id)object {
  (void)object;
  return YES;
}

@end

@implementation NSArray (DarlingPredicateAdditions)

- (NSArray*)filteredArrayUsingPredicate:(NSPredicate*)predicate {
  (void)predicate;
  return self;
}

@end

@interface NSAppleEventDescriptor : NSObject
@end

@implementation NSAppleEventDescriptor

- (NSString*)stringValue {
  return @"";
}

@end

@interface NSAppleScript : NSObject {
 @public
  NSString* _source;
}
@end

@implementation NSAppleScript

- (instancetype)initWithSource:(NSString*)source {
  self = [super init];
  if (self) _source = [source copy];
  return self;
}

- (NSAppleEventDescriptor*)executeAndReturnError:(NSDictionary**)errorInfo {
  if (errorInfo) *errorInfo = nil;
  return [[NSAppleEventDescriptor alloc] init];
}

@end

// ===========================================================================
// Additional Foundation Classes & Functions for macOS ARM64 Applications
// ===========================================================================

@implementation NSNumber (DarlingMoreNumberMethods)
+ (NSNumber*)numberWithUnsignedInt:(unsigned int)v {
  return [self numberWithLongLong:static_cast<long long>(v)];
}
+ (NSNumber*)numberWithUnsignedInteger:(NSUInteger)v {
  return [self numberWithLongLong:static_cast<long long>(v)];
}
+ (NSNumber*)numberWithLong:(long)v {
  return [self numberWithLongLong:static_cast<long long>(v)];
}
+ (NSNumber*)numberWithUnsignedLong:(unsigned long)v {
  return [self numberWithLongLong:static_cast<long long>(v)];
}
+ (NSNumber*)numberWithUnsignedLongLong:(unsigned long long)v {
  return [self numberWithLongLong:static_cast<long long>(v)];
}
+ (NSNumber*)numberWithShort:(short)v {
  return [self numberWithInt:v];
}
+ (NSNumber*)numberWithUnsignedShort:(unsigned short)v {
  return [self numberWithInt:v];
}
+ (NSNumber*)numberWithChar:(char)v {
  return [self numberWithInt:v];
}
+ (NSNumber*)numberWithUnsignedChar:(unsigned char)v {
  return [self numberWithInt:v];
}
- (long)longValue { return static_cast<long>([self longLongValue]); }
- (unsigned long)unsignedLongValue {
  return static_cast<unsigned long>([self longLongValue]);
}
- (unsigned long long)unsignedLongLongValue {
  return static_cast<unsigned long long>([self longLongValue]);
}
- (short)shortValue { return static_cast<short>([self intValue]); }
- (unsigned short)unsignedShortValue {
  return static_cast<unsigned short>([self intValue]);
}
- (char)charValue { return static_cast<char>([self intValue]); }
- (unsigned char)unsignedCharValue {
  return static_cast<unsigned char>([self intValue]);
}
- (NSInteger)compare:(NSNumber*)other {
  if (!other) return 1;
  double a = [self doubleValue];
  double b = [other doubleValue];
  return a < b ? -1 : (a > b ? 1 : 0);
}
@end

@interface NSObject (DarlingKVCHelper)
- (id)valueForKey:(NSString*)key;
- (void)setValue:(id)value forKey:(NSString*)key;
@end

@implementation NSObject (DarlingKVCAndThreading)
- (NSString*)className {
  return [NSString stringWithUTF8String:class_getName(object_getClass(self))];
}
- (id)valueForUndefinedKey:(NSString*)key {
  (void)key;
  return nil;
}
- (void)setValue:(id)value forUndefinedKey:(NSString*)key {
  (void)value;
  (void)key;
}
- (id)valueForKeyPath:(NSString*)keyPath {
  return [self valueForKey:keyPath];
}
- (void)setValue:(id)value forKeyPath:(NSString*)keyPath {
  [self setValue:value forKey:keyPath];
}
- (void)addObserver:(id)observer
         forKeyPath:(NSString*)keyPath
            options:(NSUInteger)options
            context:(void*)context {
  (void)observer; (void)keyPath; (void)options; (void)context;
}
- (void)removeObserver:(id)observer forKeyPath:(NSString*)keyPath {
  (void)observer; (void)keyPath;
}
- (void)removeObserver:(id)observer
            forKeyPath:(NSString*)keyPath
               context:(void*)context {
  (void)observer; (void)keyPath; (void)context;
}
- (void)willChangeValueForKey:(NSString*)key { (void)key; }
- (void)didChangeValueForKey:(NSString*)key { (void)key; }
- (void)performSelectorOnMainThread:(SEL)aSelector
                         withObject:(id)arg
                      waitUntilDone:(BOOL)wait {
  (void)wait;
  if (!aSelector) return;
  typedef void (*MsgFn)(id, SEL, id);
  reinterpret_cast<MsgFn>(objc_msgSend)(self, aSelector, arg);
}
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget {
  for (size_t i = 0; i < g_delayed_perform_count; ++i) {
    if (g_delayed_performs[i].valid && g_delayed_performs[i].target == aTarget) {
      g_delayed_performs[i].valid = false;
    }
  }
}
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget
                                       selector:(SEL)aSelector
                                         object:(id)anArgument {
  (void)aSelector; (void)anArgument;
  [self cancelPreviousPerformRequestsWithTarget:aTarget];
}
@end

@interface NSNull : NSObject
@end
@implementation NSNull
+ (NSNull*)null {
  static NSNull* n = nil;
  if (!n) n = [[NSNull alloc] init];
  return n;
}
- (id)copy { return self; }
@end

@implementation NSError
+ (instancetype)errorWithDomain:(NSString*)domain
                           code:(NSInteger)code
                       userInfo:(NSDictionary*)dict {
  return [[[self alloc] initWithDomain:domain code:code userInfo:dict] autorelease];
}
- (instancetype)initWithDomain:(NSString*)domain
                          code:(NSInteger)code
                      userInfo:(NSDictionary*)dict {
  self = [super init];
  if (self) {
    _domain = [domain copy];
    _code = code;
    _userInfo = [dict retain];
  }
  return self;
}
- (NSString*)domain { return _domain ? _domain : @"NSCocoaErrorDomain"; }
- (NSInteger)code { return _code; }
- (NSDictionary*)userInfo { return _userInfo; }
- (NSString*)localizedDescription {
  id desc = _userInfo ? [_userInfo objectForKey:@"NSLocalizedDescription"] : nil;
  return desc ? desc : @"Operation completed";
}
- (NSString*)localizedFailureReason { return [self localizedDescription]; }
@end

@interface NSException : NSObject {
 @public
  NSString* _name;
  NSString* _reason;
  NSDictionary* _userInfo;
}
@end
@implementation NSException
+ (NSException*)exceptionWithName:(NSString*)name
                           reason:(NSString*)reason
                         userInfo:(NSDictionary*)userInfo {
  return [[[self alloc] initWithName:name reason:reason userInfo:userInfo] autorelease];
}
+ (void)raise:(NSString*)name format:(NSString*)format, ... {
  fprintf(stderr, "[NSException] raise %s: %s\n", Utf8(name), Utf8(format));
}
- (instancetype)initWithName:(NSString*)aName
                      reason:(NSString*)aReason
                    userInfo:(NSDictionary*)aUserInfo {
  self = [super init];
  if (self) {
    _name = [aName copy];
    _reason = [aReason copy];
    _userInfo = [aUserInfo retain];
  }
  return self;
}
- (NSString*)name { return _name ? _name : @"NSGenericException"; }
- (NSString*)reason { return _reason ? _reason : @""; }
- (NSDictionary*)userInfo { return _userInfo; }
- (NSArray*)callStackSymbols { return [NSArray array]; }
- (void)raise {
  fprintf(stderr, "[NSException] %s: %s\n", Utf8(_name), Utf8(_reason));
}
@end

@interface NSAssertionHandler : NSObject
@end
@implementation NSAssertionHandler
+ (NSAssertionHandler*)currentHandler {
  static NSAssertionHandler* h = nil;
  if (!h) h = [[NSAssertionHandler alloc] init];
  return h;
}
- (void)handleFailureInMethod:(SEL)selector
                       object:(id)object
                         file:(NSString*)fileName
                   lineNumber:(NSInteger)line
                  description:(NSString*)format, ... {
  (void)selector; (void)object;
  fprintf(stderr, "[NSAssert] %s:%ld: %s\n", Utf8(fileName),
          static_cast<long>(line), Utf8(format));
}
- (void)handleFailureInFunction:(NSString*)functionName
                           file:(NSString*)fileName
                     lineNumber:(NSInteger)line
                    description:(NSString*)format, ... {
  fprintf(stderr, "[NSCAssert] %s (%s:%ld): %s\n", Utf8(functionName),
          Utf8(fileName), static_cast<long>(line), Utf8(format));
}
@end

@interface NSValue : NSObject {
 @public
  NSRect _rectVal;
  void* _ptrVal;
  NSRange _rangeVal;
}
@end
@implementation NSValue
+ (NSValue*)valueWithPointer:(const void*)pointer {
  NSValue* v = [[self alloc] init];
  v->_ptrVal = const_cast<void*>(pointer);
  return [v autorelease];
}
+ (NSValue*)valueWithNonretainedObject:(id)anObject {
  return [self valueWithPointer:anObject];
}
+ (NSValue*)valueWithPoint:(NSPoint)point {
  NSValue* v = [[self alloc] init];
  v->_rectVal.origin = point;
  return [v autorelease];
}
+ (NSValue*)valueWithSize:(NSSize)size {
  NSValue* v = [[self alloc] init];
  v->_rectVal.size = size;
  return [v autorelease];
}
+ (NSValue*)valueWithRect:(NSRect)rect {
  NSValue* v = [[self alloc] init];
  v->_rectVal = rect;
  return [v autorelease];
}
+ (NSValue*)valueWithRange:(NSRange)range {
  NSValue* v = [[self alloc] init];
  v->_rangeVal = range;
  return [v autorelease];
}
+ (NSValue*)valueWithBytes:(const void*)value objCType:(const char*)type {
  (void)type;
  return [self valueWithPointer:value];
}
- (void*)pointerValue { return _ptrVal; }
- (id)nonretainedObjectValue { return reinterpret_cast<id>(_ptrVal); }
- (NSPoint)pointValue { return _rectVal.origin; }
- (NSSize)sizeValue { return _rectVal.size; }
- (NSRect)rectValue { return _rectVal; }
- (NSRange)rangeValue { return _rangeVal; }
@end

@interface NSSet : NSObject {
 @public
  NSMutableArray* _storage;
}
@end
@interface NSMutableSet : NSSet
@end

@implementation NSSet
+ (instancetype)set { return [[[self alloc] init] autorelease]; }
+ (instancetype)setWithObject:(id)object {
  NSSet* s = [[self alloc] init];
  if (object) [s->_storage addObject:object];
  return [s autorelease];
}
+ (instancetype)setWithArray:(NSArray*)array {
  NSSet* s = [[self alloc] init];
  for (id obj in array) {
    if (![s->_storage containsObject:obj]) [s->_storage addObject:obj];
  }
  return [s autorelease];
}
+ (instancetype)setWithObjects:(const id*)objects count:(NSUInteger)cnt {
  NSSet* s = [[self alloc] init];
  for (NSUInteger i = 0; objects && i < cnt; ++i) {
    if (objects[i] && ![s->_storage containsObject:objects[i]]) {
      [s->_storage addObject:objects[i]];
    }
  }
  return [s autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) _storage = [[NSMutableArray alloc] init];
  return self;
}
- (NSUInteger)count { return [_storage count]; }
- (BOOL)containsObject:(id)anObject { return [_storage containsObject:anObject]; }
- (id)member:(id)object {
  return [_storage containsObject:object] ? object : nil;
}
- (id)anyObject { return [_storage firstObject]; }
- (NSArray*)allObjects { return _storage; }
- (id)copy { return [self retain]; }
- (id)mutableCopy { return [NSMutableSet setWithArray:_storage]; }
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState*)state
                                  objects:(id*)buffer
                                    count:(NSUInteger)len {
  return [_storage countByEnumeratingWithState:state objects:buffer count:len];
}
@end

@implementation NSMutableSet
+ (instancetype)setWithCapacity:(NSUInteger)numItems {
  (void)numItems;
  return [self set];
}
- (void)addObject:(id)object {
  if (object && ![_storage containsObject:object]) [_storage addObject:object];
}
- (void)removeObject:(id)object {
  [_storage removeObject:object];
}
- (void)removeAllObjects {
  [_storage removeAllObjects];
}
- (void)unionSet:(NSSet*)otherSet {
  for (id obj in [otherSet allObjects]) [self addObject:obj];
}
@end

@interface NSMutableIndexSet : NSIndexSet
@end

@implementation NSIndexSet
+ (instancetype)indexSet { return [[[self alloc] init] autorelease]; }
+ (instancetype)indexSetWithIndex:(NSUInteger)value {
  NSIndexSet* s = [[self alloc] init];
  s->_first = value;
  s->_count = 1;
  return [s autorelease];
}
+ (instancetype)indexSetWithIndexesInRange:(NSRange)range {
  NSIndexSet* s = [[self alloc] init];
  s->_first = range.location;
  s->_count = range.length;
  return [s autorelease];
}
- (NSUInteger)count { return _count; }
- (NSUInteger)firstIndex {
  return _count > 0 ? _first : static_cast<NSUInteger>(NSNotFound);
}
- (NSUInteger)lastIndex {
  return _count > 0 ? (_first + _count - 1) : static_cast<NSUInteger>(NSNotFound);
}
- (BOOL)containsIndex:(NSUInteger)value {
  return _count > 0 && value >= _first && value < _first + _count;
}
@end

@implementation NSMutableIndexSet
- (void)addIndex:(NSUInteger)value {
  _first = value;
  _count = 1;
}
- (void)removeAllIndexes { _count = 0; }
@end

@implementation NSDate
+ (instancetype)date {
  NSDate* d = [[self alloc] init];
  d->_ti = CurrentMonotonicSeconds() - 978307200.0;
  return [d autorelease];
}
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)secs {
  NSDate* d = [self date];
  d->_ti += secs;
  return d;
}
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)secs {
  NSDate* d = [[self alloc] init];
  d->_ti = secs - 978307200.0;
  return [d autorelease];
}
+ (instancetype)distantFuture {
  return [self dateWithTimeIntervalSince1970:4102444800.0];
}
+ (instancetype)distantPast {
  return [self dateWithTimeIntervalSince1970:0.0];
}
+ (NSTimeInterval)timeIntervalSinceReferenceDate {
  return CurrentMonotonicSeconds() - 978307200.0;
}
- (instancetype)init {
  self = [super init];
  if (self) _ti = CurrentMonotonicSeconds() - 978307200.0;
  return self;
}
- (NSTimeInterval)timeIntervalSinceReferenceDate { return _ti; }
- (NSTimeInterval)timeIntervalSince1970 { return _ti + 978307200.0; }
- (NSTimeInterval)timeIntervalSinceNow {
  return _ti - (CurrentMonotonicSeconds() - 978307200.0);
}
- (NSTimeInterval)timeIntervalSinceDate:(NSDate*)anotherDate {
  return anotherDate ? (_ti - anotherDate->_ti) : 0.0;
}
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)ti {
  return [NSDate dateWithTimeIntervalSince1970:[self timeIntervalSince1970] + ti];
}
- (NSInteger)compare:(NSDate*)other {
  if (!other) return 1;
  return _ti < other->_ti ? -1 : (_ti > other->_ti ? 1 : 0);
}
- (NSString*)description { return @"2026-06-15 12:00:00 +0000"; }
@end

@interface NSTimeZone : NSObject
@end
@implementation NSTimeZone
+ (NSTimeZone*)systemTimeZone {
  static NSTimeZone* tz = nil;
  if (!tz) tz = [[NSTimeZone alloc] init];
  return tz;
}
+ (NSTimeZone*)localTimeZone { return [self systemTimeZone]; }
+ (NSTimeZone*)defaultTimeZone { return [self systemTimeZone]; }
+ (NSTimeZone*)timeZoneWithName:(NSString*)tzName {
  (void)tzName;
  return [self systemTimeZone];
}
- (NSString*)name { return @"UTC"; }
- (NSString*)abbreviation { return @"UTC"; }
- (NSInteger)secondsFromGMT { return 0; }
@end

@interface NSDateComponents : NSObject
@end
@implementation NSDateComponents
- (NSInteger)year { return 2026; }
- (NSInteger)month { return 6; }
- (NSInteger)day { return 15; }
- (NSInteger)hour { return 12; }
- (NSInteger)minute { return 0; }
- (NSInteger)second { return 0; }
@end

@interface NSCalendar : NSObject
@end
@implementation NSCalendar
+ (NSCalendar*)currentCalendar {
  static NSCalendar* c = nil;
  if (!c) c = [[NSCalendar alloc] init];
  return c;
}
+ (NSCalendar*)calendarWithIdentifier:(NSString*)ident {
  (void)ident;
  return [self currentCalendar];
}
- (NSDateComponents*)components:(NSUInteger)unitFlags fromDate:(NSDate*)date {
  (void)unitFlags; (void)date;
  return [[[NSDateComponents alloc] init] autorelease];
}
- (NSDate*)dateFromComponents:(NSDateComponents*)comps {
  (void)comps;
  return [NSDate date];
}
@end

@interface NSDateFormatter : NSObject {
 @public
  NSString* _dateFormat;
}
@end
@implementation NSDateFormatter
+ (NSString*)localizedStringFromDate:(NSDate*)date
                           dateStyle:(NSUInteger)dstyle
                           timeStyle:(NSUInteger)tstyle {
  (void)date; (void)dstyle; (void)tstyle;
  return @"Jun 15, 2026 at 12:00 PM";
}
- (void)setDateFormat:(NSString*)string { _dateFormat = [string copy]; }
- (NSString*)dateFormat { return _dateFormat ? _dateFormat : @"yyyy-MM-dd HH:mm:ss"; }
- (void)setDateStyle:(NSUInteger)style { (void)style; }
- (void)setTimeStyle:(NSUInteger)style { (void)style; }
- (void)setLocale:(id)locale { (void)locale; }
- (void)setTimeZone:(id)tz { (void)tz; }
- (NSString*)stringFromDate:(NSDate*)date {
  (void)date;
  return @"2026-06-15 12:00:00";
}
- (NSDate*)dateFromString:(NSString*)string {
  (void)string;
  return [NSDate date];
}
@end

@interface NSUUID : NSObject
@end
@implementation NSUUID
+ (instancetype)UUID { return [[[self alloc] init] autorelease]; }
- (instancetype)initWithUUIDString:(NSString*)string {
  (void)string;
  return [self init];
}
- (NSString*)UUIDString { return @"00000000-0000-4000-8000-000000000001"; }
@end

@interface NSLock : NSObject
@end
@implementation NSLock
- (void)lock {}
- (void)unlock {}
- (BOOL)tryLock { return YES; }
- (void)setName:(NSString*)n { (void)n; }
@end

@interface NSRecursiveLock : NSLock
@end
@implementation NSRecursiveLock
@end

@interface NSCondition : NSLock
@end
@implementation NSCondition
- (void)wait {}
- (BOOL)waitUntilDate:(NSDate*)limit { (void)limit; return YES; }
- (void)signal {}
- (void)broadcast {}
@end

@interface NSThread : NSObject
@end
@implementation NSThread
+ (BOOL)isMainThread { return YES; }
+ (NSThread*)mainThread {
  static NSThread* t = nil;
  if (!t) t = [[NSThread alloc] init];
  return t;
}
+ (NSThread*)currentThread { return [self mainThread]; }
+ (void)detachNewThreadSelector:(SEL)selector
                       toTarget:(id)target
                     withObject:(id)argument {
  if (!target || !selector) return;
  typedef void (*Fn)(id, SEL, id);
  reinterpret_cast<Fn>(objc_msgSend)(target, selector, argument);
}
+ (void)sleepForTimeInterval:(NSTimeInterval)ti { (void)ti; }
- (BOOL)isMainThread { return YES; }
- (NSMutableDictionary*)threadDictionary {
  static NSMutableDictionary* d = nil;
  if (!d) d = [[NSMutableDictionary alloc] init];
  return d;
}
- (void)start {}
- (void)cancel {}
@end

extern "C" void* CFRunLoopGetMain(void);

@interface NSRunLoop : NSObject
@end
@implementation NSRunLoop
+ (NSRunLoop*)currentRunLoop {
  static NSRunLoop* rl = nil;
  if (!rl) rl = [[NSRunLoop alloc] init];
  return rl;
}
+ (NSRunLoop*)mainRunLoop { return [self currentRunLoop]; }
- (void)addTimer:(NSTimer*)timer forMode:(NSString*)mode {
  (void)timer; (void)mode;
}
- (void)addPort:(id)aPort forMode:(NSString*)mode {
  (void)aPort; (void)mode;
}
- (void)run {}
- (void)runUntilDate:(NSDate*)limitDate { (void)limitDate; }
- (BOOL)runMode:(NSString*)mode beforeDate:(NSDate*)limitDate {
  (void)mode; (void)limitDate;
  return NO;
}
- (void*)getCFRunLoop {
  return CFRunLoopGetMain();
}
@end

struct DarlingObjCBlockLiteral {
  void* isa;
  int flags;
  int reserved;
  void (*invoke)(void*, ...);
};

@interface NSOperation : NSObject
@end
@implementation NSOperation
- (void)start { [self main]; }
- (void)main {}
- (void)cancel {}
- (BOOL)isCancelled { return NO; }
- (BOOL)isFinished { return YES; }
- (BOOL)isExecuting { return NO; }
- (void)waitUntilFinished {}
- (void)setCompletionBlock:(void*)block {
  if (block) {
    auto* b = static_cast<DarlingObjCBlockLiteral*>(block);
    if (b->invoke) b->invoke(b);
  }
}
@end

@interface NSBlockOperation : NSOperation {
 @public
  void* _block;
}
@end
@implementation NSBlockOperation
+ (instancetype)blockOperationWithBlock:(void*)block {
  NSBlockOperation* op = [[[self alloc] init] autorelease];
  op->_block = block;
  return op;
}
- (void)addExecutionBlock:(void*)block { _block = block; }
- (void)main {
  if (_block) {
    auto* b = static_cast<DarlingObjCBlockLiteral*>(_block);
    if (b->invoke) b->invoke(b);
  }
}
@end

@interface NSInvocationOperation : NSOperation
@end
@implementation NSInvocationOperation
- (instancetype)initWithTarget:(id)target selector:(SEL)sel object:(id)arg {
  self = [super init];
  if (self && target && sel) {
    typedef void (*Fn)(id, SEL, id);
    reinterpret_cast<Fn>(objc_msgSend)(target, sel, arg);
  }
  return self;
}
@end

@interface NSOperationQueue : NSObject
@end
@implementation NSOperationQueue
+ (NSOperationQueue*)mainQueue {
  static NSOperationQueue* q = nil;
  if (!q) q = [[NSOperationQueue alloc] init];
  return q;
}
+ (NSOperationQueue*)currentQueue { return [self mainQueue]; }
- (void)addOperation:(NSOperation*)op { [op start]; }
- (void)addOperationWithBlock:(void*)block {
  if (block) {
    auto* b = static_cast<DarlingObjCBlockLiteral*>(block);
    if (b->invoke) b->invoke(b);
  }
}
- (void)setMaxConcurrentOperationCount:(NSInteger)cnt { (void)cnt; }
- (void)setName:(NSString*)n { (void)n; }
- (void)cancelAllOperations {}
- (void)waitUntilAllOperationsAreFinished {}
@end

@interface NSCoder : NSObject
@end
@implementation NSCoder
- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)containsValueForKey:(NSString*)key { (void)key; return NO; }
- (id)decodeObjectForKey:(NSString*)key { (void)key; return nil; }
- (id)decodeObjectOfClass:(Class)aClass forKey:(NSString*)key {
  (void)aClass; (void)key;
  return nil;
}
- (id)decodeObjectOfClasses:(NSSet*)classes forKey:(NSString*)key {
  (void)classes; (void)key;
  return nil;
}
- (NSInteger)decodeIntegerForKey:(NSString*)key { (void)key; return 0; }
- (int)decodeIntForKey:(NSString*)key { (void)key; return 0; }
- (int32_t)decodeInt32ForKey:(NSString*)key { (void)key; return 0; }
- (int64_t)decodeInt64ForKey:(NSString*)key { (void)key; return 0; }
- (BOOL)decodeBoolForKey:(NSString*)key { (void)key; return NO; }
- (double)decodeDoubleForKey:(NSString*)key { (void)key; return 0.0; }
- (float)decodeFloatForKey:(NSString*)key { (void)key; return 0.0f; }
- (void)encodeObject:(id)object forKey:(NSString*)key {
  (void)object; (void)key;
}
- (void)encodeInteger:(NSInteger)value forKey:(NSString*)key {
  (void)value; (void)key;
}
- (void)encodeInt:(int)value forKey:(NSString*)key {
  (void)value; (void)key;
}
- (void)encodeBool:(BOOL)value forKey:(NSString*)key {
  (void)value; (void)key;
}
- (void)encodeDouble:(double)value forKey:(NSString*)key {
  (void)value; (void)key;
}
- (void)encodeFloat:(float)value forKey:(NSString*)key {
  (void)value; (void)key;
}
@end

@interface NSKeyedArchiver : NSCoder
@end
@implementation NSKeyedArchiver
+ (NSData*)archivedDataWithRootObject:(id)rootObject {
  (void)rootObject;
  return [NSData data];
}
+ (NSData*)archivedDataWithRootObject:(id)object
                requiringSecureCoding:(BOOL)requiresSecureCoding
                                error:(id*)error {
  (void)object; (void)requiresSecureCoding;
  if (error) *error = nil;
  return [NSData data];
}
+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString*)path {
  (void)rootObject; (void)path;
  return YES;
}
@end

@interface NSKeyedUnarchiver : NSCoder
@end
@implementation NSKeyedUnarchiver
+ (id)unarchiveObjectWithData:(NSData*)data {
  (void)data;
  return nil;
}
+ (id)unarchiveObjectWithFile:(NSString*)path {
  (void)path;
  return nil;
}
+ (id)unarchivedObjectOfClass:(Class)cls
                     fromData:(NSData*)data
                        error:(id*)error {
  (void)cls; (void)data;
  if (error) *error = nil;
  return nil;
}
+ (id)unarchivedObjectOfClasses:(NSSet*)classes
                       fromData:(NSData*)data
                          error:(id*)error {
  (void)classes; (void)data;
  if (error) *error = nil;
  return nil;
}
- (instancetype)initForReadingFromData:(NSData*)data error:(id*)error {
  (void)data;
  if (error) *error = nil;
  return [self init];
}
- (instancetype)initForReadingWithData:(NSData*)data {
  (void)data;
  return [self init];
}
- (void)setRequiresSecureCoding:(BOOL)b { (void)b; }
- (void)finishDecoding {}
@end

@interface NSXPCInterface : NSObject
@end
@implementation NSXPCInterface
+ (NSXPCInterface*)interfaceWithProtocol:(void*)protocol {
  (void)protocol;
  return [[[self alloc] init] autorelease];
}
- (void)setClasses:(NSSet*)classes
       forSelector:(SEL)sel
     argumentIndex:(NSUInteger)arg
           ofReply:(BOOL)ofReply {
  (void)classes; (void)sel; (void)arg; (void)ofReply;
}
@end

@interface _DarlingDummyXPCProxy : NSObject
@end
@implementation _DarlingDummyXPCProxy
// Specifically support Stickies.app migration reply blocks!
- (void)migrateStickiesWithReply:(void*)replyBlock {
  if (replyBlock) {
    auto* b = static_cast<DarlingObjCBlockLiteral*>(replyBlock);
    if (b->invoke) {
      reinterpret_cast<void (*)(void*, id)>(b->invoke)(b, nil);
    }
  }
}
- (void)migrateStickiesColorDictRepArray:(id)arr reply:(void*)replyBlock {
  (void)arr;
  if (replyBlock) {
    auto* b = static_cast<DarlingObjCBlockLiteral*>(replyBlock);
    if (b->invoke) {
      reinterpret_cast<void (*)(void*, id)>(b->invoke)(b, nil);
    }
  }
}
@end

@interface NSXPCConnection : NSObject {
 @public
  NSString* _serviceName;
  NSXPCInterface* _remoteObjectInterface;
  NSXPCInterface* _exportedInterface;
  id _exportedObject;
}
@end
@implementation NSXPCConnection
- (instancetype)initWithMachServiceName:(NSString*)name options:(NSUInteger)options {
  (void)options;
  self = [super init];
  if (self) _serviceName = [name copy];
  return self;
}
- (instancetype)initWithServiceName:(NSString*)serviceName {
  return [self initWithMachServiceName:serviceName options:0];
}
- (void)setRemoteObjectInterface:(NSXPCInterface*)iface {
  _remoteObjectInterface = iface;
}
- (NSXPCInterface*)remoteObjectInterface { return _remoteObjectInterface; }
- (void)setExportedInterface:(NSXPCInterface*)iface {
  _exportedInterface = iface;
}
- (void)setExportedObject:(id)obj { _exportedObject = obj; }
- (void)setInterruptionHandler:(void*)handler { (void)handler; }
- (void)setInvalidationHandler:(void*)handler { (void)handler; }
- (void)resume {}
- (void)suspend {}
- (void)invalidate {}
- (id)remoteObjectProxy {
  return [[[_DarlingDummyXPCProxy alloc] init] autorelease];
}
- (id)remoteObjectProxyWithErrorHandler:(void*)handler {
  (void)handler;
  return [[[_DarlingDummyXPCProxy alloc] init] autorelease];
}
- (id)synchronousRemoteObjectProxyWithErrorHandler:(void*)handler {
  (void)handler;
  return [[[_DarlingDummyXPCProxy alloc] init] autorelease];
}
@end

@implementation NSAttributedString (DarlingMoreAdditions)
- (instancetype)initWithAttributedString:(NSAttributedString*)attrStr {
  return [self initWithString:attrStr ? [attrStr string] : @""
                   attributes:attrStr ? attrStr->_attributes : nil];
}
- (id)copy { return [self retain]; }
- (id)mutableCopy {
  return [[NSMutableAttributedString alloc] initWithString:[self string]
                                                attributes:_attributes];
}
@end

@implementation NSMutableAttributedString (DarlingMoreAdditions)
- (void)addAttributes:(NSDictionary*)attrs range:(NSRange)range {
  (void)attrs; (void)range;
}
- (void)setAttributes:(NSDictionary*)attrs range:(NSRange)range {
  (void)attrs; (void)range;
}
- (void)removeAttribute:(NSString*)name range:(NSRange)range {
  (void)name; (void)range;
}
- (void)setAttributedString:(NSAttributedString*)attrString {
  [_string setString:attrString ? [attrString string] : @""];
}
@end

extern "C" {

extern NSString* const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";
extern NSString* const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode";
extern NSString* const NSModalPanelRunLoopMode = @"NSModalPanelRunLoopMode";
extern NSString* const NSEventTrackingRunLoopMode = @"NSEventTrackingRunLoopMode";

extern NSString* const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
extern NSString* const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
extern NSString* const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
extern NSString* const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
extern NSString* const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
extern NSString* const NSUnderlyingErrorKey = @"NSUnderlyingError";
extern NSString* const NSURLErrorFailingURLErrorKey = @"NSErrorFailingURLKey";

extern NSString* const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
extern NSString* const NSRangeException = @"NSRangeException";
extern NSString* const NSMallocException = @"NSMallocException";

extern NSString* const NSFontAttributeName = @"NSFont";
extern NSString* const NSForegroundColorAttributeName = @"NSColor";
extern NSString* const NSBackgroundColorAttributeName = @"NSBackgroundColor";
extern NSString* const NSParagraphStyleAttributeName = @"NSParagraphStyle";
extern NSString* const NSUnderlineStyleAttributeName = @"NSUnderline";
extern NSString* const NSUnderlineColorAttributeName = @"NSUnderlineColor";
extern NSString* const NSLinkAttributeName = @"NSLink";
extern NSString* const NSCursorAttributeName = @"NSCursor";

extern NSString* const NSFileCreationDate = @"NSFileCreationDate";
extern NSString* const NSFileModificationDate = @"NSFileModificationDate";
extern NSString* const NSFilePosixPermissions = @"NSFilePosixPermissions";
extern NSString* const NSURLContentModificationDateKey = @"NSURLContentModificationDateKey";
extern NSString* const NSURLCreationDateKey = @"NSURLCreationDateKey";

struct DarlingEdgeInsets {
  CGFloat top;
  CGFloat left;
  CGFloat bottom;
  CGFloat right;
};
extern "C" const DarlingEdgeInsets NSEdgeInsetsZero = {0.0, 0.0, 0.0, 0.0};

extern const NSRect NSZeroRect = {{0.0, 0.0}, {0.0, 0.0}};
extern const NSPoint NSZeroPoint = {0.0, 0.0};
extern const NSSize NSZeroSize = {0.0, 0.0};

NSString* NSStringFromClass(Class aClass) {
  if (!aClass) return nil;
  return [NSString stringWithUTF8String:class_getName(aClass)];
}

NSString* NSStringFromSelector(SEL aSelector) {
  if (!aSelector) return nil;
  return [NSString stringWithUTF8String:sel_getName(aSelector)];
}

NSString* NSStringFromPoint(NSPoint aPoint) {
  return [NSString stringWithFormat:@"{%g, %g}", aPoint.x, aPoint.y];
}

NSString* NSStringFromSize(NSSize aSize) {
  return [NSString stringWithFormat:@"{%g, %g}", aSize.width, aSize.height];
}

NSString* NSStringFromRect(NSRect aRect) {
  return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}",
                                    aRect.origin.x, aRect.origin.y,
                                    aRect.size.width, aRect.size.height];
}

NSString* NSStringFromRange(NSRange range) {
  return [NSString stringWithFormat:@"{%lu, %lu}",
                                    static_cast<unsigned long>(range.location),
                                    static_cast<unsigned long>(range.length)];
}

NSPoint NSPointFromString(NSString* aString) {
  NSPoint pt = {0.0, 0.0};
  if (aString) sscanf(Utf8(aString), "{%lf, %lf}", &pt.x, &pt.y);
  return pt;
}

NSSize NSSizeFromString(NSString* aString) {
  NSSize sz = {0.0, 0.0};
  if (aString) sscanf(Utf8(aString), "{%lf, %lf}", &sz.width, &sz.height);
  return sz;
}

NSRect NSRectFromString(NSString* aString) {
  NSRect r = {{0.0, 0.0}, {0.0, 0.0}};
  if (aString) {
    sscanf(Utf8(aString), "{{%lf, %lf}, {%lf, %lf}}", &r.origin.x, &r.origin.y,
           &r.size.width, &r.size.height);
  }
  return r;
}

NSRange NSRangeFromString(NSString* aString) {
  unsigned long loc = 0, len = 0;
  if (aString) sscanf(Utf8(aString), "{%lu, %lu}", &loc, &len);
  return NSMakeRange(loc, len);
}

BOOL NSEqualRects(NSRect aRect, NSRect bRect) {
  return aRect.origin.x == bRect.origin.x && aRect.origin.y == bRect.origin.y &&
         aRect.size.width == bRect.size.width &&
         aRect.size.height == bRect.size.height;
}

BOOL NSEqualSizes(NSSize aSize, NSSize bSize) {
  return aSize.width == bSize.width && aSize.height == bSize.height;
}

BOOL NSEqualPoints(NSPoint aPoint, NSPoint bPoint) {
  return aPoint.x == bPoint.x && aPoint.y == bPoint.y;
}

BOOL NSIsEmptyRect(NSRect aRect) {
  return aRect.size.width <= 0.0 || aRect.size.height <= 0.0;
}

NSRect NSInsetRect(NSRect aRect, CGFloat dX, CGFloat dY) {
  aRect.origin.x += dX;
  aRect.origin.y += dY;
  aRect.size.width -= dX * 2.0;
  aRect.size.height -= dY * 2.0;
  return aRect;
}

NSRect NSIntegralRect(NSRect aRect) {
  aRect.origin.x = static_cast<CGFloat>(static_cast<int64_t>(aRect.origin.x));
  aRect.origin.y = static_cast<CGFloat>(static_cast<int64_t>(aRect.origin.y));
  aRect.size.width =
      static_cast<CGFloat>(static_cast<int64_t>(aRect.size.width + 0.999999));
  aRect.size.height =
      static_cast<CGFloat>(static_cast<int64_t>(aRect.size.height + 0.999999));
  return aRect;
}

NSRect NSOffsetRect(NSRect aRect, CGFloat dX, CGFloat dY) {
  aRect.origin.x += dX;
  aRect.origin.y += dY;
  return aRect;
}

NSRect NSUnionRect(NSRect aRect, NSRect bRect) {
  if (NSIsEmptyRect(aRect)) return bRect;
  if (NSIsEmptyRect(bRect)) return aRect;
  CGFloat minx = aRect.origin.x < bRect.origin.x ? aRect.origin.x : bRect.origin.x;
  CGFloat miny = aRect.origin.y < bRect.origin.y ? aRect.origin.y : bRect.origin.y;
  CGFloat maxxA = aRect.origin.x + aRect.size.width;
  CGFloat maxxB = bRect.origin.x + bRect.size.width;
  CGFloat maxyA = aRect.origin.y + aRect.size.height;
  CGFloat maxyB = bRect.origin.y + bRect.size.height;
  CGFloat maxx = maxxA > maxxB ? maxxA : maxxB;
  CGFloat maxy = maxyA > maxyB ? maxyA : maxyB;
  return NSMakeRect(minx, miny, maxx - minx, maxy - miny);
}

NSRect NSIntersectionRect(NSRect aRect, NSRect bRect) {
  CGFloat minx = aRect.origin.x > bRect.origin.x ? aRect.origin.x : bRect.origin.x;
  CGFloat miny = aRect.origin.y > bRect.origin.y ? aRect.origin.y : bRect.origin.y;
  CGFloat maxxA = aRect.origin.x + aRect.size.width;
  CGFloat maxxB = bRect.origin.x + bRect.size.width;
  CGFloat maxyA = aRect.origin.y + aRect.size.height;
  CGFloat maxyB = bRect.origin.y + bRect.size.height;
  CGFloat maxx = maxxA < maxxB ? maxxA : maxxB;
  CGFloat maxy = maxyA < maxyB ? maxyA : maxyB;
  if (maxx <= minx || maxy <= miny) return NSZeroRect;
  return NSMakeRect(minx, miny, maxx - minx, maxy - miny);
}

BOOL NSContainsRect(NSRect aRect, NSRect bRect) {
  return !NSIsEmptyRect(aRect) && !NSIsEmptyRect(bRect) &&
         bRect.origin.x >= aRect.origin.x &&
         bRect.origin.y >= aRect.origin.y &&
         bRect.origin.x + bRect.size.width <= aRect.origin.x + aRect.size.width &&
         bRect.origin.y + bRect.size.height <= aRect.origin.y + aRect.size.height;
}

BOOL NSPointInRect(NSPoint aPoint, NSRect aRect) {
  return aPoint.x >= aRect.origin.x &&
         aPoint.x < aRect.origin.x + aRect.size.width &&
         aPoint.y >= aRect.origin.y &&
         aPoint.y < aRect.origin.y + aRect.size.height;
}

BOOL NSMouseInRect(NSPoint aPoint, NSRect aRect, BOOL flipped) {
  (void)flipped;
  return NSPointInRect(aPoint, aRect);
}

NSString* NSHomeDirectory(void) {
  const char* h = getenv("HOME");
  return [NSString stringWithUTF8String:(h && h[0]) ? h : "/var/root"];
}

NSString* NSHomeDirectoryForUser(NSString* userName) {
  (void)userName;
  return NSHomeDirectory();
}

NSString* NSTemporaryDirectory(void) { return @"/tmp"; }

NSString* NSFullUserName(void) { return @"Darwin User"; }

NSArray* NSSearchPathForDirectoriesInDomains(NSUInteger directory,
                                             NSUInteger domainMask,
                                             BOOL expandTilde) {
  (void)directory;
  (void)domainMask;
  (void)expandTilde;
  return [NSArray arrayWithObject:@"/var/root/Library"];
}

static void* g_uncaught_handler = nullptr;
void* NSGetUncaughtExceptionHandler(void) { return g_uncaught_handler; }
void NSSetUncaughtExceptionHandler(void* handler) {
  g_uncaught_handler = handler;
}

NSString* _NSMethodExceptionProem(id obj, SEL sel) {
  return [NSString stringWithFormat:@"-[%s %s]",
                                    obj ? class_getName(object_getClass(obj)) : "nil",
                                    sel ? sel_getName(sel) : "null"];
}

void NSLogv(id format, va_list args) {
  if (!format) return;
  StringBuffer msg;
  FormatWithVaList(Utf8(format), args, &msg);
  const char* prog = getprogname();
  fprintf(stderr, "[Darling %s:%d] %s\n", (prog && prog[0]) ? prog : "App",
          static_cast<int>(getpid()), msg.c_str());
}

}  // extern "C"

