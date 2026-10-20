// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded CoreFoundation Framework (/System/Library/Frameworks/CoreFoundation.framework)
// Implements CoreFoundation types and toll-free bridged classes:
// NSArray, NSMutableArray, NSDictionary, NSMutableDictionary, NSUserDefaults,
// CFString, CFDictionary, and system version plists for XNU/Darwin ARM64.

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/objc.h>
#import <objc/runtime.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

int __CFConstantStringClassReference[32] = {0};

namespace {

class StringBuffer {
 public:
  StringBuffer() : data_(nullptr), size_(0), capacity_(0) {}
  ~StringBuffer() { free(data_); }

  void Append(const char* s, size_t len) {
    if (!s || len == 0) return;
    Ensure(size_ + len + 1);
    memcpy(data_ + size_, s, len);
    size_ += len;
    data_[size_] = '\0';
  }

  void AppendCStr(const char* s) {
    if (s) Append(s, strlen(s));
  }

  void AppendChar(char c) {
    Append(&c, 1);
  }

  const char* c_str() const { return data_ ? data_ : ""; }
  size_t size() const { return size_; }

 private:
  void Ensure(size_t need) {
    if (need <= capacity_) return;
    size_t next = capacity_ ? capacity_ * 2 : 64;
    while (next < need) next *= 2;
    data_ = static_cast<char*>(realloc(data_, next));
    capacity_ = next;
  }

  char* data_;
  size_t size_;
  size_t capacity_;
};

struct ObjectArrayStorage {
  id* items;
  size_t count;
  size_t capacity;
};

ObjectArrayStorage* CreateArrayStorage() {
  return static_cast<ObjectArrayStorage*>(calloc(1, sizeof(ObjectArrayStorage)));
}

void ArrayStoragePush(ObjectArrayStorage* st, id item) {
  if (!st || !item) return;
  if (st->count + 1 > st->capacity) {
    size_t next = st->capacity ? st->capacity * 2 : 16;
    auto* next_items =
        static_cast<id*>(realloc(st->items, next * sizeof(id)));
    if (!next_items) return;
    st->items = next_items;
    st->capacity = next;
  }
  st->items[st->count++] = item;
}

struct DictEntry {
  char* key;
  id value;
};

struct DictStorage {
  DictEntry* entries;
  size_t count;
  size_t capacity;
};

DictStorage* CreateDictStorage() {
  return static_cast<DictStorage*>(calloc(1, sizeof(DictStorage)));
}

char* DuplicateCStr(const char* s) {
  if (!s) s = "";
  size_t len = strlen(s);
  char* copy = static_cast<char*>(malloc(len + 1));
  if (copy) memcpy(copy, s, len + 1);
  return copy;
}

void DictStorageSet(DictStorage* d, const char* key, id val) {
  if (!d || !key || !val) return;
  for (size_t i = 0; i < d->count; ++i) {
    if (d->entries[i].key && strcmp(d->entries[i].key, key) == 0) {
      d->entries[i].value = val;
      return;
    }
  }
  if (d->count + 1 > d->capacity) {
    size_t next_cap = d->capacity ? d->capacity * 2 : 16;
    auto* next = static_cast<DictEntry*>(
        realloc(d->entries, next_cap * sizeof(DictEntry)));
    if (!next) return;
    d->entries = next;
    d->capacity = next_cap;
  }
  d->entries[d->count].key = DuplicateCStr(key);
  d->entries[d->count].value = val;
  d->count++;
}

id DictStorageGet(const DictStorage* d, const char* key) {
  if (!d || !key) return nullptr;
  for (size_t i = 0; i < d->count; ++i) {
    if (d->entries[i].key && strcmp(d->entries[i].key, key) == 0) {
      return d->entries[i].value;
    }
  }
  return nullptr;
}

inline bool ValidCFPtr(const void* p) {
  uintptr_t u = reinterpret_cast<uintptr_t>(p);
  return u >= 0x1000ULL && (u >> 48) == 0;
}

const char* SafeCString(id obj) {
  if (!ValidCFPtr(obj)) return "(null)";
  if ([obj respondsToSelector:@selector(UTF8String)]) {
    typedef const char* (*Utf8Fn)(id, SEL);
    return reinterpret_cast<Utf8Fn>(objc_msgSend)(obj, sel_registerName("UTF8String"));
  }
  id desc = [obj description];
  if (desc && [desc respondsToSelector:@selector(UTF8String)]) {
    typedef const char* (*Utf8Fn)(id, SEL);
    return reinterpret_cast<Utf8Fn>(objc_msgSend)(desc, sel_registerName("UTF8String"));
  }
  return "(null)";
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

void ReadWholeFile(const char* path, StringBuffer* out) {
  if (!path || !out) return;
  FILE* fp = fopen(path, "rb");
  if (!fp) return;
  char buf[1024];
  size_t n = 0;
  while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
    out->Append(buf, n);
  }
  fclose(fp);
}

id MakeNSString(const char* s) {
  Class cls = objc_getClass("NSString");
  if (!cls) return nil;
  typedef id (*MsgFn)(id, SEL, const char*);
  return reinterpret_cast<MsgFn>(objc_msgSend)(
      cls, sel_registerName("stringWithUTF8String:"), s ? s : "");
}

// ---------------------------------------------------------------------------
// XML property list parser (Apple "PropertyList-1.0" DTD): dict, array,
// string, key, integer, real, true, false, date (kept as string) and data
// (base64), with the standard XML character entities.
// ---------------------------------------------------------------------------
struct PlistCursor {
  const char* p;
  const char* end;
};

void PlistSkipMisc(PlistCursor* c) {
  while (c->p < c->end) {
    if (*c->p == ' ' || *c->p == '\t' || *c->p == '\n' || *c->p == '\r') {
      ++c->p;
    } else if (c->end - c->p >= 4 && strncmp(c->p, "<!--", 4) == 0) {
      const char* e = strstr(c->p, "-->");
      c->p = e ? e + 3 : c->end;
    } else if (c->end - c->p >= 2 && (strncmp(c->p, "<?", 2) == 0 ||
                                       strncmp(c->p, "<!", 2) == 0)) {
      const char* e = strchr(c->p, '>');
      c->p = e ? e + 1 : c->end;
    } else {
      break;
    }
  }
}

// Reads "<name>" / "<name/>" / "</name>"; returns false at end.
bool PlistReadTag(PlistCursor* c, char* name, size_t cap, bool* closing,
                  bool* empty) {
  PlistSkipMisc(c);
  if (c->p >= c->end || *c->p != '<') return false;
  ++c->p;
  *closing = false;
  if (*c->p == '/') {
    *closing = true;
    ++c->p;
  }
  size_t n = 0;
  while (c->p < c->end && *c->p != '>' && *c->p != ' ' && *c->p != '/') {
    if (n + 1 < cap) name[n++] = *c->p;
    ++c->p;
  }
  name[n] = '\0';
  *empty = false;
  while (c->p < c->end && *c->p != '>') {
    if (*c->p == '/') *empty = true;
    ++c->p;
  }
  if (c->p < c->end) ++c->p;
  return true;
}

void PlistDecodeEntities(const char* s, size_t n, StringBuffer* out) {
  for (size_t i = 0; i < n; ++i) {
    if (s[i] != '&') {
      out->AppendChar(s[i]);
      continue;
    }
    const char* semi = static_cast<const char*>(memchr(s + i, ';', n - i));
    if (!semi) {
      out->AppendChar('&');
      continue;
    }
    size_t len = static_cast<size_t>(semi - (s + i));
    if (len == 4 && !strncmp(s + i, "&amp", 4)) out->AppendChar('&');
    else if (len == 3 && !strncmp(s + i, "&lt", 3)) out->AppendChar('<');
    else if (len == 3 && !strncmp(s + i, "&gt", 3)) out->AppendChar('>');
    else if (len == 5 && !strncmp(s + i, "&quot", 5)) out->AppendChar('"');
    else if (len == 5 && !strncmp(s + i, "&apos", 5)) out->AppendChar('\'');
    else if (len > 2 && s[i + 1] == '#') {
      unsigned long cp = s[i + 2] == 'x' ? strtoul(s + i + 3, nullptr, 16)
                                         : strtoul(s + i + 2, nullptr, 10);
      char u[4];
      size_t k = 0;
      if (cp < 0x80) {
        u[k++] = static_cast<char>(cp);
      } else if (cp < 0x800) {
        u[k++] = static_cast<char>(0xC0 | (cp >> 6));
        u[k++] = static_cast<char>(0x80 | (cp & 0x3F));
      } else if (cp < 0x10000) {
        u[k++] = static_cast<char>(0xE0 | (cp >> 12));
        u[k++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        u[k++] = static_cast<char>(0x80 | (cp & 0x3F));
      } else {
        u[k++] = static_cast<char>(0xF0 | (cp >> 18));
        u[k++] = static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
        u[k++] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        u[k++] = static_cast<char>(0x80 | (cp & 0x3F));
      }
      out->Append(u, k);
    } else {
      out->Append(s + i, len + 1);
    }
    i += len;
  }
}

// Text content up to the closing tag (cursor is after the opening tag).
void PlistReadText(PlistCursor* c, StringBuffer* out) {
  const char* start = c->p;
  while (c->p < c->end && *c->p != '<') ++c->p;
  PlistDecodeEntities(start, static_cast<size_t>(c->p - start), out);
  char name[32];
  bool closing = false, empty = false;
  PlistReadTag(c, name, sizeof(name), &closing, &empty);
}

int Base64Value(char ch) {
  if (ch >= 'A' && ch <= 'Z') return ch - 'A';
  if (ch >= 'a' && ch <= 'z') return ch - 'a' + 26;
  if (ch >= '0' && ch <= '9') return ch - '0' + 52;
  if (ch == '+') return 62;
  if (ch == '/') return 63;
  return -1;
}

id PlistParseValue(PlistCursor* c, const char* tag, bool empty);

id PlistParseElement(PlistCursor* c) {
  char name[32];
  bool closing = false, empty = false;
  while (PlistReadTag(c, name, sizeof(name), &closing, &empty)) {
    if (closing) return nil;
    if (!strcmp(name, "plist")) continue;
    return PlistParseValue(c, name, empty);
  }
  return nil;
}

id PlistParseValue(PlistCursor* c, const char* tag, bool empty) {
  if (!strcmp(tag, "dict")) {
    NSMutableDictionary* d = [[NSMutableDictionary alloc] init];
    if (empty) return d;
    char name[32];
    bool closing = false, e2 = false;
    while (PlistReadTag(c, name, sizeof(name), &closing, &e2)) {
      if (closing) break;  // </dict>
      if (strcmp(name, "key") != 0) continue;
      StringBuffer key;
      if (!e2) PlistReadText(c, &key);
      id value = PlistParseElement(c);
      if (value) [d setObject:value forKey:MakeNSString(key.c_str())];
    }
    return d;
  }
  if (!strcmp(tag, "array")) {
    NSMutableArray* a = [[NSMutableArray alloc] init];
    if (empty) return a;
    while (true) {
      PlistCursor save = *c;
      char name[32];
      bool closing = false, e2 = false;
      if (!PlistReadTag(c, name, sizeof(name), &closing, &e2)) break;
      if (closing) break;  // </array>
      *c = save;
      id v = PlistParseElement(c);
      if (v) [a addObject:v];
    }
    return a;
  }
  if (!strcmp(tag, "true")) return [NSNumber numberWithBool:YES];
  if (!strcmp(tag, "false")) return [NSNumber numberWithBool:NO];
  StringBuffer text;
  if (!empty) PlistReadText(c, &text);
  if (!strcmp(tag, "integer")) {
    return [NSNumber numberWithLongLong:strtoll(text.c_str(), nullptr, 10)];
  }
  if (!strcmp(tag, "real")) {
    return [NSNumber numberWithDouble:strtod(text.c_str(), nullptr)];
  }
  if (!strcmp(tag, "data")) {
    StringBuffer bytes;
    unsigned acc = 0;
    int bits = 0;
    for (const char* q = text.c_str(); *q; ++q) {
      int v = Base64Value(*q);
      if (v < 0) continue;
      acc = (acc << 6) | static_cast<unsigned>(v);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        bytes.AppendChar(static_cast<char>((acc >> bits) & 0xFF));
      }
    }
    return [NSData dataWithBytes:bytes.c_str() length:bytes.size()];
  }
  return MakeNSString(text.c_str());  // string, date, unknown
}

id ParseXmlPlist(const char* xml, size_t len) {
  PlistCursor c = {xml, xml + len};
  return PlistParseElement(&c);
}

uint64_t ReadBE(const uint8_t* p, size_t n) {
  uint64_t v = 0;
  for (size_t i = 0; i < n; ++i) {
    v = (v << 8) | p[i];
  }
  return v;
}

id ParseBplistObj(const uint8_t* buf, size_t len, uint8_t offset_size,
                  uint8_t ref_size, uint64_t num_objects,
                  uint64_t offset_table_start, uint64_t obj_idx, int depth) {
  if (depth > 32 || obj_idx >= num_objects) return nil;
  uint64_t off_pos = offset_table_start + obj_idx * offset_size;
  if (off_pos + offset_size > len - 32) return nil;
  uint64_t off = ReadBE(buf + off_pos, offset_size);
  if (off >= len - 32) return nil;

  uint8_t marker = buf[off];
  uint8_t hi = (marker >> 4) & 0x0f;
  uint8_t lo = marker & 0x0f;

  auto read_count = [&](uint64_t* out_count, const uint8_t** out_payload) -> bool {
    if (lo != 0x0f) {
      *out_count = lo;
      *out_payload = buf + off + 1;
      return (*out_payload <= buf + len - 32);
    }
    if (off + 2 > len - 32) return false;
    uint8_t im = buf[off + 1];
    size_t ib = 1ULL << (im & 0x0f);
    if (ib > 8 || off + 2 + ib > len - 32) return false;
    *out_count = ReadBE(buf + off + 2, ib);
    *out_payload = buf + off + 2 + ib;
    return (*out_payload <= buf + len - 32);
  };

  switch (hi) {
    case 0x0:
      if (lo == 0x08) return [NSNumber numberWithBool:NO];
      if (lo == 0x09) return [NSNumber numberWithBool:YES];
      return nil;
    case 0x1: {
      size_t nbytes = 1ULL << lo;
      if (nbytes > 8 || off + 1 + nbytes > len - 32) return nil;
      uint64_t u = ReadBE(buf + off + 1, nbytes);
      int64_t v = static_cast<int64_t>(u);
      if (nbytes == 1) v = static_cast<int8_t>(u);
      else if (nbytes == 2) v = static_cast<int16_t>(u);
      else if (nbytes == 4) v = static_cast<int32_t>(u);
      return [NSNumber numberWithLongLong:v];
    }
    case 0x2: {
      size_t nbytes = 1ULL << lo;
      if (nbytes == 4 && off + 5 <= len - 32) {
        uint32_t u = static_cast<uint32_t>(ReadBE(buf + off + 1, 4));
        float f = 0.0f;
        memcpy(&f, &u, 4);
        return [NSNumber numberWithDouble:f];
      }
      if (nbytes == 8 && off + 9 <= len - 32) {
        uint64_t u = ReadBE(buf + off + 1, 8);
        double d = 0.0;
        memcpy(&d, &u, 8);
        return [NSNumber numberWithDouble:d];
      }
      return nil;
    }
    case 0x3: {
      if (off + 9 > len - 32) return nil;
      uint64_t u = ReadBE(buf + off + 1, 8);
      double d = 0.0;
      memcpy(&d, &u, 8);
      return [NSNumber numberWithDouble:d];
    }
    case 0x4: {
      uint64_t cnt = 0;
      const uint8_t* payload = nullptr;
      if (!read_count(&cnt, &payload) || payload + cnt > buf + len - 32) return nil;
      return [NSData dataWithBytes:payload length:static_cast<NSUInteger>(cnt)];
    }
    case 0x5: {
      uint64_t cnt = 0;
      const uint8_t* payload = nullptr;
      if (!read_count(&cnt, &payload) || payload + cnt > buf + len - 32) return nil;
      StringBuffer sb;
      sb.Append(reinterpret_cast<const char*>(payload), static_cast<size_t>(cnt));
      return MakeNSString(sb.c_str());
    }
    case 0x6: {
      uint64_t cnt = 0;
      const uint8_t* payload = nullptr;
      if (!read_count(&cnt, &payload) || payload + cnt * 2 > buf + len - 32) return nil;
      StringBuffer sb;
      for (uint64_t i = 0; i < cnt; ++i) {
        uint16_t ch = static_cast<uint16_t>((payload[i * 2] << 8) | payload[i * 2 + 1]);
        char u[4];
        size_t k = 0;
        if (ch < 0x80) {
          u[k++] = static_cast<char>(ch);
        } else if (ch < 0x800) {
          u[k++] = static_cast<char>(0xC0 | (ch >> 6));
          u[k++] = static_cast<char>(0x80 | (ch & 0x3F));
        } else {
          u[k++] = static_cast<char>(0xE0 | (ch >> 12));
          u[k++] = static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
          u[k++] = static_cast<char>(0x80 | (ch & 0x3F));
        }
        sb.Append(u, k);
      }
      return MakeNSString(sb.c_str());
    }
    case 0x8: {
      size_t nbytes = static_cast<size_t>(lo) + 1;
      if (nbytes > 8 || off + 1 + nbytes > len - 32) return nil;
      return [NSNumber numberWithLongLong:static_cast<long long>(ReadBE(buf + off + 1, nbytes))];
    }
    case 0xA:
    case 0xC: {
      uint64_t cnt = 0;
      const uint8_t* payload = nullptr;
      if (!read_count(&cnt, &payload) || payload + cnt * ref_size > buf + len - 32) return nil;
      NSMutableArray* a = [[NSMutableArray alloc] init];
      for (uint64_t i = 0; i < cnt; ++i) {
        uint64_t ref = ReadBE(payload + i * ref_size, ref_size);
        id elem = ParseBplistObj(buf, len, offset_size, ref_size, num_objects,
                                 offset_table_start, ref, depth + 1);
        if (elem) [a addObject:elem];
      }
      return a;
    }
    case 0xD: {
      uint64_t cnt = 0;
      const uint8_t* payload = nullptr;
      if (!read_count(&cnt, &payload) ||
          payload + cnt * 2 * ref_size > buf + len - 32) {
        return nil;
      }
      NSMutableDictionary* d = [[NSMutableDictionary alloc] init];
      for (uint64_t i = 0; i < cnt; ++i) {
        uint64_t kref = ReadBE(payload + i * ref_size, ref_size);
        uint64_t vref = ReadBE(payload + (cnt + i) * ref_size, ref_size);
        id k = ParseBplistObj(buf, len, offset_size, ref_size, num_objects,
                              offset_table_start, kref, depth + 1);
        id v = ParseBplistObj(buf, len, offset_size, ref_size, num_objects,
                              offset_table_start, vref, depth + 1);
        if (k && v) [d setObject:v forKey:k];
      }
      return d;
    }
    default:
      return nil;
  }
}

id ParseBplist(const uint8_t* buf, size_t len) {
  if (!buf || len < 40 || memcmp(buf, "bplist00", 8) != 0) return nil;
  const uint8_t* trailer = buf + len - 32;
  uint8_t offset_size = trailer[6];
  uint8_t ref_size = trailer[7];
  if ((offset_size != 1 && offset_size != 2 && offset_size != 4 && offset_size != 8) ||
      (ref_size != 1 && ref_size != 2 && ref_size != 4 && ref_size != 8)) {
    return nil;
  }
  uint64_t num_objects = ReadBE(trailer + 8, 8);
  uint64_t top_object = ReadBE(trailer + 16, 8);
  uint64_t offset_table_start = ReadBE(trailer + 24, 8);
  if (num_objects == 0 || offset_table_start >= len - 32) return nil;
  return ParseBplistObj(buf, len, offset_size, ref_size, num_objects,
                        offset_table_start, top_object, 0);
}

id ParsePlistBytes(const char* data, size_t len) {
  if (!data || len == 0) return nil;
  if (len >= 8 && memcmp(data, "bplist00", 8) == 0) {
    return ParseBplist(reinterpret_cast<const uint8_t*>(data), len);
  }
  return ParseXmlPlist(data, len);
}

void BindCFConstantStringClass() {
  Class cls = objc_getClass("NSConstantString");
  if (!cls) cls = objc_getClass("NSString");
  if (cls) {
    memcpy(__CFConstantStringClassReference, cls, 40);
  }
}

__attribute__((constructor)) void InitializeDarlingCoreFoundation() {
  BindCFConstantStringClass();
}

}  // namespace

@interface NSEnumerator : NSObject {
 @public
  NSArray* _items;
  NSUInteger _index;
}
- (id)nextObject;
- (NSArray*)allObjects;
@end

@implementation NSEnumerator
- (id)nextObject {
  if (!_items || _index >= [_items count]) return nil;
  return [_items objectAtIndex:_index++];
}
- (NSArray*)allObjects {
  if (!_items) return [NSArray array];
  return _items;
}
@end

@implementation NSArray

+ (instancetype)array {
  return [[[self alloc] init] autorelease];
}

+ (instancetype)arrayWithObjects:(const id*)objects count:(NSUInteger)cnt {
  NSArray* arr = [[self alloc] init];
  auto* st = static_cast<ObjectArrayStorage*>(arr->_items);
  for (NSUInteger i = 0; i < cnt; ++i) {
    if (objects[i]) ArrayStoragePush(st, objects[i]);
  }
  return arr;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _items = CreateArrayStorage();
  }
  return self;
}

- (NSUInteger)count {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  return st ? st->count : 0;
}

- (id)objectAtIndex:(NSUInteger)index {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (!st || index >= st->count) return nullptr;
  return st->items[index];
}

- (id)lastObject {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (!st || st->count == 0) return nullptr;
  return st->items[st->count - 1];
}

- (id)objectAtIndexedSubscript:(NSUInteger)idx {
  return [self objectAtIndex:idx];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState*)state
                                 objects:(id*)buffer
                                   count:(NSUInteger)len {
  (void)buffer;
  (void)len;
  if (!state) return 0;
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (!st || st->count == 0) return 0;
  if (state->state == 0) {
    state->mutationsPtr = &state->extra[0];
    state->itemsPtr = st->items;
    state->state = 1;
    return st->count;
  }
  return 0;
}

@end

@implementation NSArray (DarlingAdditions)

+ (instancetype)arrayWithObject:(id)anObject {
  return [self arrayWithObjects:&anObject count:anObject ? 1 : 0];
}

+ (instancetype)arrayWithArray:(NSArray*)array {
  NSArray* a = [[self alloc] init];
  auto* st = static_cast<ObjectArrayStorage*>(a->_items);
  for (NSUInteger i = 0; i < [array count]; ++i) {
    ArrayStoragePush(st, [array objectAtIndex:i]);
  }
  return a;
}

+ (instancetype)arrayWithContentsOfFile:(NSString*)path {
  if (!path) return nil;
  StringBuffer xml;
  ReadWholeFile([path UTF8String], &xml);
  id root = ParsePlistBytes(xml.c_str(), xml.size());
  return [root isKindOfClass:[NSArray class]] ? root : nil;
}

- (id)firstObject {
  return [self count] ? [self objectAtIndex:0] : nil;
}

- (NSEnumerator*)objectEnumerator {
  NSEnumerator* e = [[[NSEnumerator alloc] init] autorelease];
  e->_items = [self retain];
  e->_index = 0;
  return e;
}

- (NSEnumerator*)reverseObjectEnumerator {
  return [self objectEnumerator];
}

- (NSUInteger)indexOfObject:(id)anObject {
  for (NSUInteger i = 0; i < [self count]; ++i) {
    if ([[self objectAtIndex:i] isEqual:anObject]) return i;
  }
  return static_cast<NSUInteger>(-1);  // NSNotFound
}

- (BOOL)containsObject:(id)anObject {
  return [self indexOfObject:anObject] != static_cast<NSUInteger>(-1);
}

- (id)copy {
  return [NSArray arrayWithArray:self];
}

- (id)mutableCopy {
  return [NSMutableArray arrayWithArray:self];
}

- (NSArray*)arrayByAddingObject:(id)anObject {
  NSMutableArray* a = [NSMutableArray arrayWithArray:self];
  [a addObject:anObject];
  return a;
}

- (NSString*)componentsJoinedByString:(NSString*)separator {
  StringBuffer out;
  for (NSUInteger i = 0; i < [self count]; ++i) {
    if (i && separator) out.AppendCStr([separator UTF8String]);
    out.AppendCStr(SafeCString([self objectAtIndex:i]));
  }
  return MakeNSString(out.c_str());
}

- (id)description {
  StringBuffer out;
  out.AppendCStr("(\n");
  for (NSUInteger i = 0; i < [self count]; ++i) {
    out.AppendCStr("    ");
    out.AppendCStr(SafeCString([self objectAtIndex:i]));
    out.AppendCStr(i + 1 < [self count] ? ",\n" : "\n");
  }
  out.AppendCStr(")");
  return MakeNSString(out.c_str());
}

@end

@implementation NSMutableArray

+ (instancetype)arrayWithCapacity:(NSUInteger)numItems {
  (void)numItems;
  return [[self alloc] init];
}

- (void)addObject:(id)anObject {
  if (!anObject) return;
  if (!_items) _items = CreateArrayStorage();
  ArrayStoragePush(static_cast<ObjectArrayStorage*>(_items), anObject);
}

- (void)removeAllObjects {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (st) st->count = 0;
}

- (void)addObjectsFromArray:(NSArray*)otherArray {
  for (NSUInteger i = 0; i < [otherArray count]; ++i) {
    [self addObject:[otherArray objectAtIndex:i]];
  }
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index {
  if (!anObject) return;
  if (!_items) _items = CreateArrayStorage();
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (index > st->count) index = st->count;
  ArrayStoragePush(st, anObject);
  memmove(st->items + index + 1, st->items + index,
          (st->count - 1 - index) * sizeof(id));
  st->items[index] = anObject;
}

- (void)removeObjectAtIndex:(NSUInteger)index {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (!st || index >= st->count) return;
  memmove(st->items + index, st->items + index + 1,
          (st->count - index - 1) * sizeof(id));
  st->count--;
}

- (void)removeLastObject {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (st && st->count) st->count--;
}

- (void)removeObject:(id)anObject {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (!st) return;
  for (size_t i = st->count; i > 0; --i) {
    if ([st->items[i - 1] isEqual:anObject]) [self removeObjectAtIndex:i - 1];
  }
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (!st || index >= st->count || !anObject) return;
  st->items[index] = anObject;
}

- (void)setObject:(id)obj atIndexedSubscript:(NSUInteger)idx {
  auto* st = static_cast<ObjectArrayStorage*>(_items);
  if (st && idx == st->count) {
    [self addObject:obj];
  } else {
    [self replaceObjectAtIndex:idx withObject:obj];
  }
}

@end

@implementation NSDictionary

+ (instancetype)dictionary {
  return [[[self alloc] init] autorelease];
}

+ (instancetype)dictionaryWithObject:(id)object forKey:(id)key {
  return [self dictionaryWithObjects:&object forKeys:&key count:(object && key) ? 1 : 0];
}

+ (instancetype)dictionaryWithDictionary:(NSDictionary*)dict {
  return [[[self alloc] initWithDictionary:dict] autorelease];
}

+ (instancetype)dictionaryWithObjects:(const id*)objects
                              forKeys:(const id*)keys
                                count:(NSUInteger)cnt {
  NSMutableDictionary* dict = [[[NSMutableDictionary alloc] init] autorelease];
  if (objects && keys && cnt > 0) {
    for (NSUInteger i = 0; i < cnt; ++i) {
      if (keys[i] && objects[i]) {
        [dict setObject:objects[i] forKey:keys[i]];
      }
    }
  }
  return dict;
}

+ (instancetype)dictionaryWithContentsOfFile:(NSString*)path {
  if (!path) return nullptr;
  StringBuffer xml;
  ReadWholeFile([path UTF8String], &xml);
  if (xml.size() == 0) return nullptr;
  id root = ParsePlistBytes(xml.c_str(), xml.size());
  return [root isKindOfClass:[NSDictionary class]] ? root : nil;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _map = CreateDictStorage();
  }
  return self;
}

- (instancetype)initWithDictionary:(NSDictionary*)otherDictionary {
  self = [self init];
  if (self && otherDictionary) {
    auto* src = static_cast<const DictStorage*>(otherDictionary->_map);
    auto* dst = static_cast<DictStorage*>(_map);
    for (size_t i = 0; src && dst && i < src->count; ++i) {
      if (src->entries[i].key && src->entries[i].value) {
        DictStorageSet(dst, src->entries[i].key, src->entries[i].value);
      }
    }
  }
  return self;
}

- (instancetype)initWithObjects:(const id*)objects
                        forKeys:(const id*)keys
                          count:(NSUInteger)cnt {
  self = [self init];
  if (self && objects && keys) {
    auto* dst = static_cast<DictStorage*>(_map);
    for (NSUInteger i = 0; i < cnt; ++i) {
      if (keys[i] && objects[i]) {
        DictStorageSet(dst, SafeCString(keys[i]), objects[i]);
      }
    }
  }
  return self;
}

- (NSUInteger)count {
  auto* d = static_cast<DictStorage*>(_map);
  return d ? d->count : 0;
}

- (id)objectForKey:(id)aKey {
  if (!aKey || !_map) return nullptr;
  const char* k = SafeCString(aKey);
  return DictStorageGet(static_cast<const DictStorage*>(_map), k);
}

- (id)objectForKeyedSubscript:(id)aKey {
  return [self objectForKey:aKey];
}

- (NSArray*)allKeys {
  NSMutableArray* keys = [NSMutableArray array];
  auto* d = static_cast<DictStorage*>(_map);
  for (size_t i = 0; d && i < d->count; ++i) [keys addObject:MakeNSString(d->entries[i].key)];
  return keys;
}

- (NSArray*)allValues {
  NSMutableArray* values = [NSMutableArray array];
  auto* d = static_cast<DictStorage*>(_map);
  for (size_t i = 0; d && i < d->count; ++i) [values addObject:d->entries[i].value];
  return values;
}

- (NSArray*)keysSortedByValueUsingSelector:(SEL)comparator {
  (void)comparator;
  return [self allKeys];
}

- (NSEnumerator*)keyEnumerator {
  return [[self allKeys] objectEnumerator];
}

- (NSEnumerator*)objectEnumerator {
  return [[self allValues] objectEnumerator];
}

- (id)valueForKey:(NSString*)key {
  return [self objectForKey:key];
}

- (id)copy {
  return self;
}

- (id)mutableCopy {
  NSMutableDictionary* m = [[NSMutableDictionary alloc] init];
  auto* d = static_cast<DictStorage*>(_map);
  for (size_t i = 0; d && i < d->count; ++i) {
    DictStorageSet(static_cast<DictStorage*>(m->_map), d->entries[i].key,
                   d->entries[i].value);
  }
  return m;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState*)state
                                  objects:(id*)buffer
                                    count:(NSUInteger)len {
  if (!state || state->state) return 0;
  NSArray* keys = [self allKeys];
  NSUInteger n = [keys count] < len ? [keys count] : len;
  for (NSUInteger i = 0; i < n; ++i) buffer[i] = [keys objectAtIndex:i];
  state->state = 1;
  state->itemsPtr = buffer;
  state->mutationsPtr = &state->extra[0];
  return n;
}

@end

@implementation NSMutableDictionary

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  (void)numItems;
  return [[[self alloc] init] autorelease];
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  (void)numItems;
  return [self init];
}

- (void)addEntriesFromDictionary:(NSDictionary*)otherDictionary {
  if (!otherDictionary) return;
  if (!_map) _map = CreateDictStorage();
  auto* src = static_cast<const DictStorage*>(otherDictionary->_map);
  auto* dst = static_cast<DictStorage*>(_map);
  for (size_t i = 0; src && dst && i < src->count; ++i) {
    if (src->entries[i].key && src->entries[i].value) {
      DictStorageSet(dst, src->entries[i].key, src->entries[i].value);
    }
  }
}

- (void)removeAllObjects {
  auto* d = static_cast<DictStorage*>(_map);
  if (!d) return;
  for (size_t i = 0; i < d->count; ++i) {
    free(d->entries[i].key);
  }
  d->count = 0;
}

- (void)setObject:(id)anObject forKey:(id)aKey {
  if (!anObject || !aKey) return;
  if (!_map) _map = CreateDictStorage();
  DictStorageSet(static_cast<DictStorage*>(_map), SafeCString(aKey), anObject);
}

- (void)setObject:(id)anObject forKeyedSubscript:(id)aKey {
  [self setObject:anObject forKey:aKey];
}

- (void)removeObjectForKey:(id)aKey {
  auto* d = static_cast<DictStorage*>(_map);
  if (!d || !aKey) return;
  const char* k = SafeCString(aKey);
  for (size_t i = 0; i < d->count; ++i) {
    if (d->entries[i].key && strcmp(d->entries[i].key, k) == 0) {
      free(d->entries[i].key);
      d->entries[i] = d->entries[d->count - 1];
      d->count--;
      return;
    }
  }
}

- (void)setValue:(id)value forKey:(NSString*)key {
  if (value) [self setObject:value forKey:key];
  else [self removeObjectForKey:key];
}

@end

@implementation NSUserDefaults {
  NSMutableDictionary* _dict;
}

+ (NSUserDefaults*)standardUserDefaults {
  static NSUserDefaults* defs = nullptr;
  if (!defs) {
    defs = [[NSUserDefaults alloc] init];
  }
  return defs;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _dict = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)registerDefaults:(NSDictionary*)registrationDictionary {
  if (!registrationDictionary || !_dict) return;
  auto* src = static_cast<const DictStorage*>(registrationDictionary->_map);
  auto* dst = static_cast<DictStorage*>(_dict->_map);
  if (!dst) {
    _dict->_map = CreateDictStorage();
    dst = static_cast<DictStorage*>(_dict->_map);
  }
  if (src && dst) {
    for (size_t i = 0; i < src->count; ++i) {
      if (src->entries[i].key && !DictStorageGet(dst, src->entries[i].key)) {
        DictStorageSet(dst, src->entries[i].key, src->entries[i].value);
      }
    }
  }
}

- (id)objectForKey:(NSString*)defaultName {
  if (!defaultName || !_dict) return nullptr;
  return [_dict objectForKey:defaultName];
}

- (void)setObject:(id)value forKey:(NSString*)defaultName {
  if (!defaultName || !_dict) return;
  if (value) {
    [_dict setObject:value forKey:defaultName];
  }
}

- (void)setBool:(BOOL)value forKey:(NSString*)defaultName {
  [self setObject:[NSNumber numberWithBool:value] forKey:defaultName];
}

- (void)setInteger:(NSInteger)value forKey:(NSString*)defaultName {
  [self setObject:[NSNumber numberWithLongLong:value] forKey:defaultName];
}

- (NSInteger)integerForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  return [obj respondsToSelector:@selector(longLongValue)]
             ? static_cast<NSInteger>([obj longLongValue]) : 0;
}

- (float)floatForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  return [obj respondsToSelector:@selector(doubleValue)]
             ? static_cast<float>([obj doubleValue]) : 0.0f;
}

- (NSString*)stringForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  return [obj respondsToSelector:@selector(UTF8String)] ? obj : nil;
}

- (void)removeObjectForKey:(NSString*)defaultName {
  [_dict removeObjectForKey:defaultName];
}

- (BOOL)synchronize {
  return YES;
}

- (BOOL)boolForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  if (!obj) return NO;
  if ([obj isKindOfClass:[NSNumber class]]) {
    return [reinterpret_cast<NSNumber*>(obj) boolValue];
  }
  return NO;
}

@end

extern "C" {

// The empty-array and empty-dictionary singletons that clang emits for @[]
// and @{}. Their isa is set at load time.
struct DarlingEmptyArray {
  Class isa;
  void* items;
};
DarlingEmptyArray __NSArray0__ = {nullptr, nullptr};
DarlingEmptyArray __NSArray0__struct = {nullptr, nullptr};

struct DarlingEmptyDict {
  Class isa;
  void* map;
};
DarlingEmptyDict __NSDictionary0__ = {nullptr, nullptr};
DarlingEmptyDict __NSDictionary0__struct = {nullptr, nullptr};

__attribute__((constructor)) static void InitializeEmptyArray() {
  __NSArray0__.isa = objc_getClass("NSArray");
  __NSArray0__.items = CreateArrayStorage();
  __NSArray0__struct.isa = __NSArray0__.isa;
  __NSArray0__struct.items = __NSArray0__.items;
  __NSDictionary0__.isa = objc_getClass("NSDictionary");
  __NSDictionary0__.map = CreateDictStorage();
  __NSDictionary0__struct.isa = __NSDictionary0__.isa;
  __NSDictionary0__struct.map = __NSDictionary0__.map;
}

id _DarlingParsePlist(const void* bytes, size_t len) {
  return ParsePlistBytes(static_cast<const char*>(bytes), len);
}

CFStringRef __CFStringMakeConstantString(const char* cStr) {
  BindCFConstantStringClass();
  id s = MakeNSString(cStr ? cStr : "");
  return reinterpret_cast<CFStringRef>(s);
}

const CFStringRef _kCFSystemVersionProductNameKey =
    reinterpret_cast<CFStringRef>(@"ProductName");
const CFStringRef _kCFSystemVersionProductVersionKey =
    reinterpret_cast<CFStringRef>(@"ProductVersion");
const CFStringRef _kCFSystemVersionBuildVersionKey =
    reinterpret_cast<CFStringRef>(@"ProductBuildVersion");

CFTypeRef CFRetain(CFTypeRef cf) { return cf; }

void CFRelease(CFTypeRef /*cf*/) {}

uint32_t CFStringGetSystemEncoding(void) { return kCFStringEncodingUTF8; }

CFStringRef CFStringCreateWithCString(CFAllocatorRef /*alloc*/,
                                      const char* cStr,
                                      CFStringEncoding /*encoding*/) {
  BindCFConstantStringClass();
  id s = MakeNSString(cStr ? cStr : "");
  return reinterpret_cast<CFStringRef>([s retain]);
}

CFStringRef CFStringCreateWithFormat(CFAllocatorRef /*alloc*/,
                                     CFDictionaryRef /*formatOptions*/,
                                     CFStringRef format, ...) {
  BindCFConstantStringClass();
  if (!format) return __CFStringMakeConstantString("");
  va_list ap;
  va_start(ap, format);
  const char* fmt = CFStringGetCStringPtr(format, kCFStringEncodingUTF8);
  StringBuffer formatted;
  FormatWithVaList(fmt ? fmt : "", ap, &formatted);
  va_end(ap);
  id s = MakeNSString(formatted.c_str());
  return reinterpret_cast<CFStringRef>([s retain]);
}

bool CFStringGetCString(CFStringRef theString, char* buffer, CFIndex bufferSize,
                        CFStringEncoding /*encoding*/) {
  if (!theString || !buffer || bufferSize <= 0) return false;
  BindCFConstantStringClass();
  const char* s = SafeCString(reinterpret_cast<id>(const_cast<__CFString*>(theString)));
  if (!s) return false;
  snprintf(buffer, static_cast<size_t>(bufferSize), "%s", s);
  return true;
}

const char* CFStringGetCStringPtr(CFStringRef theString,
                                  CFStringEncoding /*encoding*/) {
  if (!theString) return nullptr;
  BindCFConstantStringClass();
  return SafeCString(reinterpret_cast<id>(const_cast<__CFString*>(theString)));
}

CFIndex CFStringGetLength(CFStringRef theString) {
  if (!theString) return 0;
  BindCFConstantStringClass();
  const char* s = SafeCString(reinterpret_cast<id>(const_cast<__CFString*>(theString)));
  return s ? static_cast<CFIndex>(strlen(s)) : 0;
}

const void* CFDictionaryGetValue(CFDictionaryRef theDict, const void* key) {
  if (!theDict || !key) return nullptr;
  BindCFConstantStringClass();
  auto* dict =
      reinterpret_cast<NSDictionary*>(const_cast<__CFDictionary*>(theDict));
  return [dict objectForKey:reinterpret_cast<id>(const_cast<void*>(key))];
}

CFIndex CFDictionaryGetCount(CFDictionaryRef theDict) {
  if (!theDict) return 0;
  BindCFConstantStringClass();
  auto* dict =
      reinterpret_cast<NSDictionary*>(const_cast<__CFDictionary*>(theDict));
  return static_cast<CFIndex>([dict count]);
}

CFDictionaryRef _CFCopySystemVersionDictionary(void) {
  BindCFConstantStringClass();
  id pathStr = MakeNSString("/System/Library/CoreServices/SystemVersion.plist");
  NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:pathStr];
  if (dict && [dict count] > 0) {
    return reinterpret_cast<CFDictionaryRef>(dict);
  }
  NSMutableDictionary* fallback = [[NSMutableDictionary alloc] init];
  id kProd = MakeNSString("ProductName");
  id vProd = MakeNSString("Mac OS X");
  id kVer = MakeNSString("ProductVersion");
  id vVer = MakeNSString("10.15.7");
  id kBld = MakeNSString("ProductBuildVersion");
  id vBld = MakeNSString("25F5042g");
  [fallback setObject:vProd forKey:kProd];
  [fallback setObject:vVer forKey:kVer];
  [fallback setObject:vBld forKey:kBld];
  return reinterpret_cast<CFDictionaryRef>(fallback);
}

CFDictionaryRef _CFCopyServerVersionDictionary(void) {
  BindCFConstantStringClass();
  id pathStr = MakeNSString("/System/Library/CoreServices/ServerVersion.plist");
  NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:pathStr];
  if (dict && [dict count] > 0) {
    return reinterpret_cast<CFDictionaryRef>(dict);
  }
  return nullptr;
}

}  // extern "C"

// ===========================================================================
// Constant literal classes (__objc_arrayobj, __objc_dictobj, __objc_intobj,
// __objc_floatobj, __objc_doubleobj) emitted by modern clang into __DATA_CONST
// ===========================================================================
@interface NSConstantArray : NSArray
@end

@implementation NSConstantArray
- (NSUInteger)count {
  return static_cast<NSUInteger>(reinterpret_cast<const uint64_t*>(self)[1]);
}
- (id)objectAtIndex:(NSUInteger)index {
  uint64_t cnt = reinterpret_cast<const uint64_t*>(self)[1];
  id const* objs = reinterpret_cast<id const* const*>(self)[2];
  return (objs && index < cnt) ? objs[index] : nil;
}
- (id)objectAtIndexedSubscript:(NSUInteger)idx {
  return [self objectAtIndex:idx];
}
- (id)firstObject {
  return [self count] > 0 ? [self objectAtIndex:0] : nil;
}
- (id)lastObject {
  NSUInteger c = [self count];
  return c > 0 ? [self objectAtIndex:c - 1] : nil;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState*)state
                                  objects:(id*)buffer
                                    count:(NSUInteger)len {
  (void)buffer;
  (void)len;
  if (!state || state->state != 0) return 0;
  uint64_t cnt = reinterpret_cast<const uint64_t*>(self)[1];
  id const* objs = reinterpret_cast<id const* const*>(self)[2];
  if (!objs || cnt == 0) return 0;
  state->mutationsPtr = &state->extra[0];
  state->itemsPtr = const_cast<id*>(objs);
  state->state = 1;
  return static_cast<NSUInteger>(cnt);
}
@end

@interface NSConstantDictionary : NSDictionary
@end

@implementation NSConstantDictionary
- (NSUInteger)count {
  return static_cast<NSUInteger>(reinterpret_cast<const uint64_t*>(self)[2]);
}
- (id)objectForKey:(id)aKey {
  if (!aKey) return nil;
  uint64_t cnt = reinterpret_cast<const uint64_t*>(self)[2];
  id const* keys = reinterpret_cast<id const* const*>(self)[3];
  id const* objs = reinterpret_cast<id const* const*>(self)[4];
  if (!keys || !objs) return nil;
  const char* want = SafeCString(aKey);
  for (uint64_t i = 0; i < cnt; ++i) {
    if (keys[i] && ([keys[i] isEqual:aKey] || strcmp(SafeCString(keys[i]), want) == 0)) {
      return objs[i];
    }
  }
  return nil;
}
- (id)objectForKeyedSubscript:(id)aKey {
  return [self objectForKey:aKey];
}
- (NSArray*)allKeys {
  uint64_t cnt = reinterpret_cast<const uint64_t*>(self)[2];
  id const* keys = reinterpret_cast<id const* const*>(self)[3];
  NSMutableArray* a = [NSMutableArray array];
  for (uint64_t i = 0; keys && i < cnt; ++i) {
    if (keys[i]) [a addObject:keys[i]];
  }
  return a;
}
- (NSArray*)allValues {
  uint64_t cnt = reinterpret_cast<const uint64_t*>(self)[2];
  id const* objs = reinterpret_cast<id const* const*>(self)[4];
  NSMutableArray* a = [NSMutableArray array];
  for (uint64_t i = 0; objs && i < cnt; ++i) {
    if (objs[i]) [a addObject:objs[i]];
  }
  return a;
}
@end

@interface NSConstantIntegerNumber : NSNumber
@end

@implementation NSConstantIntegerNumber
- (long long)longLongValue {
  return static_cast<long long>(reinterpret_cast<const int64_t*>(self)[2]);
}
- (int)intValue {
  return static_cast<int>([self longLongValue]);
}
- (NSInteger)integerValue {
  return static_cast<NSInteger>([self longLongValue]);
}
- (unsigned int)unsignedIntValue {
  return static_cast<unsigned int>([self longLongValue]);
}
- (NSUInteger)unsignedIntegerValue {
  return static_cast<NSUInteger>([self longLongValue]);
}
- (double)doubleValue {
  return static_cast<double>([self longLongValue]);
}
- (float)floatValue {
  return static_cast<float>([self longLongValue]);
}
- (BOOL)boolValue {
  return [self longLongValue] != 0 ? YES : NO;
}
- (NSString*)stringValue {
  char buf[64];
  snprintf(buf, sizeof(buf), "%lld", [self longLongValue]);
  return MakeNSString(buf);
}
@end

@interface NSConstantFloatNumber : NSNumber
@end

@implementation NSConstantFloatNumber
- (float)floatValue {
  float v = 0.0f;
  memcpy(&v, reinterpret_cast<const char*>(self) + 8, sizeof(float));
  return v;
}
- (double)doubleValue {
  return static_cast<double>([self floatValue]);
}
- (long long)longLongValue {
  return static_cast<long long>([self floatValue]);
}
- (int)intValue {
  return static_cast<int>([self floatValue]);
}
- (BOOL)boolValue {
  return [self floatValue] != 0.0f ? YES : NO;
}
- (NSString*)stringValue {
  char buf[64];
  snprintf(buf, sizeof(buf), "%g", [self doubleValue]);
  return MakeNSString(buf);
}
@end

@interface NSConstantDoubleNumber : NSNumber
@end

@implementation NSConstantDoubleNumber
- (double)doubleValue {
  double v = 0.0;
  memcpy(&v, reinterpret_cast<const char*>(self) + 8, sizeof(double));
  return v;
}
- (float)floatValue {
  return static_cast<float>([self doubleValue]);
}
- (long long)longLongValue {
  return static_cast<long long>([self doubleValue]);
}
- (int)intValue {
  return static_cast<int>([self doubleValue]);
}
- (BOOL)boolValue {
  return [self doubleValue] != 0.0 ? YES : NO;
}
- (NSString*)stringValue {
  char buf[64];
  snprintf(buf, sizeof(buf), "%g", [self doubleValue]);
  return MakeNSString(buf);
}
@end

@implementation NSArray (DarlingMoreAdditions)
+ (instancetype)arrayWithObjects:(id)firstObj, ... {
  NSMutableArray* a = [NSMutableArray array];
  if (!firstObj) return a;
  [a addObject:firstObj];
  va_list ap;
  va_start(ap, firstObj);
  while (id next = va_arg(ap, id)) {
    [a addObject:next];
  }
  va_end(ap);
  return a;
}
- (NSArray*)sortedArrayUsingSelector:(SEL)comparator {
  (void)comparator;
  return self;
}
- (NSArray*)subarrayWithRange:(NSRange)range {
  NSMutableArray* a = [NSMutableArray array];
  NSUInteger cnt = [self count];
  for (NSUInteger i = 0; i < range.length && range.location + i < cnt; ++i) {
    [a addObject:[self objectAtIndex:range.location + i]];
  }
  return a;
}
- (void)enumerateObjectsUsingBlock:(void*)block {
  if (!block) return;
  struct BlockLit {
    void* isa;
    int flags;
    int reserved;
    void (*invoke)(void*, id, NSUInteger, BOOL*);
  };
  auto* b = static_cast<BlockLit*>(block);
  if (!b->invoke) return;
  NSUInteger cnt = [self count];
  for (NSUInteger i = 0; i < cnt; ++i) {
    BOOL stop = NO;
    b->invoke(b, [self objectAtIndex:i], i, &stop);
    if (stop) break;
  }
}
@end

@implementation NSDictionary (DarlingMoreAdditions)
+ (instancetype)dictionaryWithObject:(id)object forKey:(id)key {
  if (!object || !key) return [self dictionary];
  return [self dictionaryWithObjects:&object forKeys:&key count:1];
}
+ (instancetype)dictionaryWithObjectsAndKeys:(id)firstObject, ... {
  NSMutableDictionary* d = [NSMutableDictionary dictionary];
  if (!firstObject) return d;
  va_list ap;
  va_start(ap, firstObject);
  id obj = firstObject;
  while (obj) {
    id key = va_arg(ap, id);
    if (!key) break;
    [d setObject:obj forKey:key];
    obj = va_arg(ap, id);
  }
  va_end(ap);
  return d;
}
+ (instancetype)dictionaryWithDictionary:(NSDictionary*)dict {
  return dict ? [dict mutableCopy] : [self dictionary];
}
- (NSArray*)keysSortedByValueUsingSelector:(SEL)comparator {
  (void)comparator;
  return [self allKeys];
}
@end

@implementation NSMutableDictionary (DarlingMoreAdditions)
+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  (void)numItems;
  return [[self alloc] init];
}
- (instancetype)initWithCapacity:(NSUInteger)numItems {
  (void)numItems;
  return [self init];
}
- (void)addEntriesFromDictionary:(NSDictionary*)otherDictionary {
  if (!otherDictionary) return;
  for (id k in [otherDictionary allKeys]) {
    id v = [otherDictionary objectForKey:k];
    if (v) [self setObject:v forKey:k];
  }
}
- (void)removeAllObjects {
  auto* d = static_cast<DictStorage*>(_map);
  if (d) d->count = 0;
}
@end

@implementation NSUserDefaults (DarlingMoreAdditions)
- (NSArray*)arrayForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  return [obj isKindOfClass:[NSArray class]] ? obj : nil;
}
- (NSDictionary*)dictionaryForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}
- (NSData*)dataForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  return [obj isKindOfClass:[NSData class]] ? obj : nil;
}
- (double)doubleForKey:(NSString*)defaultName {
  id obj = [self objectForKey:defaultName];
  return [obj respondsToSelector:@selector(doubleValue)] ? [obj doubleValue] : 0.0;
}
- (void)setDouble:(double)value forKey:(NSString*)defaultName {
  [self setObject:[NSNumber numberWithDouble:value] forKey:defaultName];
}
- (void)setFloat:(float)value forKey:(NSString*)defaultName {
  [self setObject:[NSNumber numberWithDouble:value] forKey:defaultName];
}
- (NSDictionary*)dictionaryRepresentation {
  return _dict ? _dict : [NSDictionary dictionary];
}
- (id)valueForKey:(NSString*)key {
  return [self objectForKey:key];
}
@end

extern "C" {

extern const CFAllocatorRef kCFAllocatorDefault = nullptr;
extern const CFAllocatorRef kCFAllocatorSystemDefault = nullptr;
extern const CFAllocatorRef kCFAllocatorNull = nullptr;

// In Apple's Objective-C ABI, `@YES` / `@NO` literals compile to the
// addresses `&__kCFBooleanTrue` and `&__kCFBooleanFalse` directly (without
// dereferencing), whereas `kCFBooleanTrue` and `kCFBooleanFalse` are
// `const void*` pointers pointing to `&__kCFBooleanTrue` and
// `&__kCFBooleanFalse`. Therefore `__kCFBooleanTrue` and `__kCFBooleanFalse`
// must be full `NSNumber` instance structs whose first word is `isa`!
struct DarlingCFBooleanStorage {
  Class isa;
  double doubleVal;
  long long intVal;
  BOOL isFloat;
  uint8_t pad[7];
};

static NSNumber* g_cf_bool_true = nil;
static NSNumber* g_cf_bool_false = nil;
DarlingCFBooleanStorage __kCFBooleanTrue = {nullptr, 1.0, 1, NO, {0}};
DarlingCFBooleanStorage __kCFBooleanFalse = {nullptr, 0.0, 0, NO, {0}};
const void* kCFBooleanTrue = &__kCFBooleanTrue;
const void* kCFBooleanFalse = &__kCFBooleanFalse;

extern const CFStringRef kCFRunLoopCommonModes =
    reinterpret_cast<CFStringRef>(@"kCFRunLoopCommonModes");
extern const CFStringRef kCFRunLoopDefaultMode =
    reinterpret_cast<CFStringRef>(@"kCFRunLoopDefaultMode");
extern const CFStringRef kCFPreferencesCurrentApplication =
    reinterpret_cast<CFStringRef>(@"kCFPreferencesCurrentApplication");
extern const CFStringRef kCFPreferencesAnyApplication =
    reinterpret_cast<CFStringRef>(@"kCFPreferencesAnyApplication");
extern const CFStringRef kCFPreferencesCurrentUser =
    reinterpret_cast<CFStringRef>(@"kCFPreferencesCurrentUser");
extern const CFStringRef kCFPreferencesAnyUser =
    reinterpret_cast<CFStringRef>(@"kCFPreferencesAnyUser");
extern const CFStringRef kCFPreferencesCurrentHost =
    reinterpret_cast<CFStringRef>(@"kCFPreferencesCurrentHost");
extern const CFStringRef kCFPreferencesAnyHost =
    reinterpret_cast<CFStringRef>(@"kCFPreferencesAnyHost");

extern const CFStringRef kCFBundleNameKey =
    reinterpret_cast<CFStringRef>(@"CFBundleName");
extern const CFStringRef kCFBundleVersionKey =
    reinterpret_cast<CFStringRef>(@"CFBundleVersion");
extern const CFStringRef kCFBundleShortVersionStringKey =
    reinterpret_cast<CFStringRef>(@"CFBundleShortVersionString");
extern const CFStringRef kCFBundleSignatureKey =
    reinterpret_cast<CFStringRef>(@"CFBundleSignature");
extern const CFStringRef kCFBundleIdentifierKey =
    reinterpret_cast<CFStringRef>(@"CFBundleIdentifier");
extern const CFStringRef kCFBundleExecutableKey =
    reinterpret_cast<CFStringRef>(@"CFBundleExecutable");

extern const CFStringRef kCFStreamPropertyDataWritten =
    reinterpret_cast<CFStringRef>(@"kCFStreamPropertyDataWritten");
extern const CFStringRef kCFUserNotificationAlertHeaderKey =
    reinterpret_cast<CFStringRef>(@"AlertHeader");
extern const CFStringRef kCFUserNotificationAlertMessageKey =
    reinterpret_cast<CFStringRef>(@"AlertMessage");
extern const CFStringRef kCFUserNotificationDefaultButtonTitleKey =
    reinterpret_cast<CFStringRef>(@"DefaultButtonTitle");
extern const CFStringRef kCFUserNotificationAlternateButtonTitleKey =
    reinterpret_cast<CFStringRef>(@"AlternateButtonTitle");

const void* kCFTypeArrayCallBacks[8] = {nullptr};
const void* kCFTypeDictionaryKeyCallBacks[8] = {nullptr};
const void* kCFTypeDictionaryValueCallBacks[8] = {nullptr};

__attribute__((constructor)) static void InitCFBooleans() {
  BindCFConstantStringClass();
  Class numCls = [NSNumber class];
  __kCFBooleanTrue.isa = numCls;
  __kCFBooleanFalse.isa = numCls;
  g_cf_bool_true = reinterpret_cast<NSNumber*>(&__kCFBooleanTrue);
  g_cf_bool_false = reinterpret_cast<NSNumber*>(&__kCFBooleanFalse);
  kCFBooleanTrue = &__kCFBooleanTrue;
  kCFBooleanFalse = &__kCFBooleanFalse;
}

typedef unsigned char Boolean;

CFTypeRef CFAutorelease(CFTypeRef arg) { return arg; }

Boolean CFEqual(CFTypeRef cf1, CFTypeRef cf2) {
  if (cf1 == cf2) return 1;
  if (!cf1 || !cf2) return 0;
  return [reinterpret_cast<id>(const_cast<void*>(cf1))
             isEqual:reinterpret_cast<id>(const_cast<void*>(cf2))]
             ? 1
             : 0;
}

unsigned long CFGetTypeID(CFTypeRef cf) {
  if (!ValidCFPtr(cf)) return 0;
  id obj = reinterpret_cast<id>(const_cast<void*>(cf));
  if (obj == g_cf_bool_true || obj == g_cf_bool_false) return 2;
  if ([obj isKindOfClass:[NSString class]]) return 7;
  if ([obj isKindOfClass:[NSDictionary class]]) return 18;
  if ([obj isKindOfClass:[NSArray class]]) return 19;
  if ([obj isKindOfClass:[NSData class]]) return 20;
  if ([obj isKindOfClass:[NSNumber class]]) return 22;
  return 1;
}

unsigned long CFBooleanGetTypeID(void) { return 2; }
unsigned long CFStringGetTypeID(void) { return 7; }
unsigned long CFDictionaryGetTypeID(void) { return 18; }
unsigned long CFArrayGetTypeID(void) { return 19; }
unsigned long CFDataGetTypeID(void) { return 20; }
unsigned long CFNumberGetTypeID(void) { return 22; }
unsigned long CFDateGetTypeID(void) { return 42; }

Boolean CFBooleanGetValue(const void* boolean) {
  if (!boolean) return 0;
  if (boolean == kCFBooleanTrue) return 1;
  if (boolean == kCFBooleanFalse) return 0;
  id obj = reinterpret_cast<id>(const_cast<void*>(boolean));
  if ([obj respondsToSelector:@selector(boolValue)]) {
    return [obj boolValue] ? 1 : 0;
  }
  return 0;
}

CFStringRef CFCopyDescription(CFTypeRef cf) {
  if (!cf) return __CFStringMakeConstantString("(null)");
  return reinterpret_cast<CFStringRef>(
      [reinterpret_cast<id>(const_cast<void*>(cf)) description]);
}

CFIndex CFArrayGetCount(const void* theArray) {
  if (!theArray) return 0;
  return static_cast<CFIndex>(
      [reinterpret_cast<NSArray*>(const_cast<void*>(theArray)) count]);
}

const void* CFArrayGetValueAtIndex(const void* theArray, CFIndex idx) {
  if (!theArray || idx < 0) return nullptr;
  return [reinterpret_cast<NSArray*>(const_cast<void*>(theArray))
      objectAtIndex:static_cast<NSUInteger>(idx)];
}

const void* CFArrayCreate(CFAllocatorRef /*alloc*/, const void** values,
                          CFIndex numValues, const void* /*callBacks*/) {
  NSMutableArray* a = [[NSMutableArray alloc] init];
  for (CFIndex i = 0; values && i < numValues; ++i) {
    if (values[i]) [a addObject:reinterpret_cast<id>(const_cast<void*>(values[i]))];
  }
  return a;
}

void* CFArrayCreateMutable(CFAllocatorRef /*alloc*/, CFIndex /*capacity*/,
                           const void* /*callBacks*/) {
  return [[NSMutableArray alloc] init];
}

void CFArrayAppendValue(void* theArray, const void* value) {
  if (!theArray || !value) return;
  [reinterpret_cast<NSMutableArray*>(theArray)
      addObject:reinterpret_cast<id>(const_cast<void*>(value))];
}

const void* CFDictionaryCreate(CFAllocatorRef /*alloc*/, const void** keys,
                               const void** values, CFIndex numValues,
                               const void* /*keyCallBacks*/,
                               const void* /*valueCallBacks*/) {
  NSMutableDictionary* d = [[NSMutableDictionary alloc] init];
  for (CFIndex i = 0; keys && values && i < numValues; ++i) {
    if (keys[i] && values[i]) {
      [d setObject:reinterpret_cast<id>(const_cast<void*>(values[i]))
            forKey:reinterpret_cast<id>(const_cast<void*>(keys[i]))];
    }
  }
  return d;
}

void* CFDictionaryCreateMutable(CFAllocatorRef /*alloc*/, CFIndex /*capacity*/,
                                const void* /*keyCallBacks*/,
                                const void* /*valueCallBacks*/) {
  return [[NSMutableDictionary alloc] init];
}

void CFDictionarySetValue(void* theDict, const void* key, const void* value) {
  if (!theDict || !key || !value) return;
  [reinterpret_cast<NSMutableDictionary*>(theDict)
      setObject:reinterpret_cast<id>(const_cast<void*>(value))
         forKey:reinterpret_cast<id>(const_cast<void*>(key))];
}

void CFDictionaryRemoveValue(void* theDict, const void* key) {
  if (!theDict || !key) return;
  [reinterpret_cast<NSMutableDictionary*>(theDict)
      removeObjectForKey:reinterpret_cast<id>(const_cast<void*>(key))];
}

Boolean CFDictionaryGetValueIfPresent(CFDictionaryRef theDict, const void* key,
                                      const void** value) {
  const void* v = CFDictionaryGetValue(theDict, key);
  if (value) *value = v;
  return v != nullptr ? 1 : 0;
}

const void* CFNumberCreate(CFAllocatorRef /*alloc*/, CFIndex theType,
                           const void* valuePtr) {
  if (!valuePtr) return [NSNumber numberWithInt:0];
  switch (theType) {
    case 1:  // kCFNumberSInt8Type
    case 7:  // kCFNumberCharType
      return [NSNumber numberWithInt:*static_cast<const int8_t*>(valuePtr)];
    case 2:  // kCFNumberSInt16Type
    case 8:  // kCFNumberShortType
      return [NSNumber numberWithInt:*static_cast<const int16_t*>(valuePtr)];
    case 3:  // kCFNumberSInt32Type
    case 9:  // kCFNumberIntType
      return [NSNumber numberWithInt:*static_cast<const int32_t*>(valuePtr)];
    case 5:   // kCFNumberFloat32Type
    case 12:  // kCFNumberFloatType
      return [NSNumber numberWithDouble:*static_cast<const float*>(valuePtr)];
    case 6:   // kCFNumberFloat64Type
    case 13:  // kCFNumberDoubleType
    case 16:  // kCFNumberCGFloatType
      return [NSNumber numberWithDouble:*static_cast<const double*>(valuePtr)];
    default:
      return [NSNumber numberWithLongLong:*static_cast<const int64_t*>(valuePtr)];
  }
}

Boolean CFNumberGetValue(const void* number, CFIndex theType, void* valuePtr) {
  if (!number || !valuePtr) return 0;
  NSNumber* n = reinterpret_cast<NSNumber*>(const_cast<void*>(number));
  switch (theType) {
    case 1:
    case 7:
      *static_cast<int8_t*>(valuePtr) = static_cast<int8_t>([n intValue]);
      return 1;
    case 2:
    case 8:
      *static_cast<int16_t*>(valuePtr) = static_cast<int16_t>([n intValue]);
      return 1;
    case 3:
    case 9:
      *static_cast<int32_t*>(valuePtr) = [n intValue];
      return 1;
    case 5:
    case 12:
      *static_cast<float*>(valuePtr) = static_cast<float>([n doubleValue]);
      return 1;
    case 6:
    case 13:
    case 16:
      *static_cast<double*>(valuePtr) = [n doubleValue];
      return 1;
    default:
      *static_cast<int64_t*>(valuePtr) = [n longLongValue];
      return 1;
  }
}

const void* CFDataCreate(CFAllocatorRef /*alloc*/, const uint8_t* bytes,
                         CFIndex length) {
  return [NSData dataWithBytes:bytes
                        length:length > 0 ? static_cast<NSUInteger>(length) : 0];
}

const uint8_t* CFDataGetBytePtr(const void* theData) {
  if (!theData) return nullptr;
  return static_cast<const uint8_t*>(
      [reinterpret_cast<NSData*>(const_cast<void*>(theData)) bytes]);
}

CFIndex CFDataGetLength(const void* theData) {
  if (!theData) return 0;
  return static_cast<CFIndex>(
      [reinterpret_cast<NSData*>(const_cast<void*>(theData)) length]);
}

CFIndex CFStringCompare(CFStringRef theString1, CFStringRef theString2,
                        unsigned long /*compareOptions*/) {
  const char* s1 = theString1 ? CFStringGetCStringPtr(theString1, 0) : "";
  const char* s2 = theString2 ? CFStringGetCStringPtr(theString2, 0) : "";
  int c = strcmp(s1 ? s1 : "", s2 ? s2 : "");
  return c < 0 ? -1 : (c > 0 ? 1 : 0);
}

CFIndex CFStringCompareWithOptions(CFStringRef theString1,
                                   CFStringRef theString2, NSRange /*range*/,
                                   unsigned long compareOptions) {
  return CFStringCompare(theString1, theString2, compareOptions);
}

Boolean CFStringHasPrefix(CFStringRef theString, CFStringRef prefix) {
  if (!theString || !prefix) return 0;
  return [reinterpret_cast<NSString*>(const_cast<__CFString*>(theString))
             hasPrefix:reinterpret_cast<NSString*>(
                           const_cast<__CFString*>(prefix))]
             ? 1
             : 0;
}

Boolean CFStringHasSuffix(CFStringRef theString, CFStringRef suffix) {
  if (!theString || !suffix) return 0;
  return [reinterpret_cast<NSString*>(const_cast<__CFString*>(theString))
             hasSuffix:reinterpret_cast<NSString*>(
                           const_cast<__CFString*>(suffix))]
             ? 1
             : 0;
}

CFStringRef CFStringCreateCopy(CFAllocatorRef /*alloc*/, CFStringRef theString) {
  return theString ? CFStringCreateWithCString(
                         nullptr, CFStringGetCStringPtr(theString, 0), 0)
                   : __CFStringMakeConstantString("");
}

void* CFStringCreateMutableCopy(CFAllocatorRef /*alloc*/, CFIndex /*maxLength*/,
                                CFStringRef theString) {
  const char* s = theString ? CFStringGetCStringPtr(theString, 0) : "";
  return [[NSMutableString alloc] initWithUTF8String:s ? s : ""];
}

void CFStringAppend(void* theString, CFStringRef appendedString) {
  if (!theString || !appendedString) return;
  [reinterpret_cast<NSMutableString*>(theString)
      appendString:reinterpret_cast<NSString*>(
                       const_cast<__CFString*>(appendedString))];
}

int32_t CFStringGetIntValue(CFStringRef str) {
  const char* s = str ? CFStringGetCStringPtr(str, 0) : "0";
  return s ? atoi(s) : 0;
}

double CFStringGetDoubleValue(CFStringRef str) {
  const char* s = str ? CFStringGetCStringPtr(str, 0) : "0";
  return s ? atof(s) : 0.0;
}

CFIndex CFStringGetMaximumSizeForEncoding(CFIndex length,
                                          CFStringEncoding /*encoding*/) {
  return length * 4 + 1;
}

void* CFBundleGetMainBundle(void) { return [NSBundle mainBundle]; }

void* CFBundleGetBundleWithIdentifier(CFStringRef /*bundleID*/) {
  return [NSBundle mainBundle];
}

CFStringRef CFBundleGetIdentifier(void* bundle) {
  NSBundle* b = bundle ? reinterpret_cast<NSBundle*>(bundle)
                       : [NSBundle mainBundle];
  return reinterpret_cast<CFStringRef>([b bundleIdentifier]);
}

const void* CFBundleGetValueForInfoDictionaryKey(void* bundle,
                                                 CFStringRef key) {
  if (!key) return nullptr;
  NSBundle* b = bundle ? reinterpret_cast<NSBundle*>(bundle)
                       : [NSBundle mainBundle];
  return [b objectForInfoDictionaryKey:reinterpret_cast<NSString*>(
                                           const_cast<__CFString*>(key))];
}

const void* CFBundleCopyBundleURL(void* bundle) {
  NSBundle* b = bundle ? reinterpret_cast<NSBundle*>(bundle)
                       : [NSBundle mainBundle];
  return [b performSelector:@selector(bundleURL)];
}

const void* CFBundleCopyResourcesDirectoryURL(void* bundle) {
  NSBundle* b = bundle ? reinterpret_cast<NSBundle*>(bundle)
                       : [NSBundle mainBundle];
  return [b performSelector:@selector(bundleURL)];
}

const void* CFBundleCopyResourceURL(void* bundle, CFStringRef resourceName,
                                    CFStringRef resourceType,
                                    CFStringRef /*subDirName*/) {
  NSBundle* b = bundle ? reinterpret_cast<NSBundle*>(bundle)
                       : [NSBundle mainBundle];
  NSString* p = [b pathForResource:reinterpret_cast<NSString*>(
                                       const_cast<__CFString*>(resourceName))
                            ofType:reinterpret_cast<NSString*>(
                                       const_cast<__CFString*>(resourceType))];
  if (!p) return nullptr;
  Class urlCls = objc_getClass("NSURL");
  if (!urlCls) return p;
  typedef id (*UrlFn)(id, SEL, id);
  return reinterpret_cast<UrlFn>(objc_msgSend)(
      urlCls, sel_registerName("fileURLWithPath:"), p);
}

CFStringRef CFBundleCopyLocalizedString(void* bundle, CFStringRef key,
                                        CFStringRef value,
                                        CFStringRef tableName) {
  NSBundle* b = bundle ? reinterpret_cast<NSBundle*>(bundle)
                       : [NSBundle mainBundle];
  typedef id (*LocFn)(id, SEL, id, id, id);
  id res = reinterpret_cast<LocFn>(objc_msgSend)(
      b, sel_registerName("localizedStringForKey:value:table:"),
      reinterpret_cast<id>(const_cast<__CFString*>(key)),
      reinterpret_cast<id>(const_cast<__CFString*>(value)),
      reinterpret_cast<id>(const_cast<__CFString*>(tableName)));
  return reinterpret_cast<CFStringRef>(res);
}

const void* CFPreferencesCopyAppValue(CFStringRef key,
                                      CFStringRef /*applicationID*/) {
  if (!key) return nullptr;
  return [[NSUserDefaults standardUserDefaults]
      objectForKey:reinterpret_cast<NSString*>(const_cast<__CFString*>(key))];
}

const void* CFPreferencesCopyValue(CFStringRef key,
                                   CFStringRef /*applicationID*/,
                                   CFStringRef /*userName*/,
                                   CFStringRef /*hostName*/) {
  return CFPreferencesCopyAppValue(key, nullptr);
}

Boolean CFPreferencesGetAppBooleanValue(CFStringRef key,
                                        CFStringRef /*applicationID*/,
                                        Boolean* keyExistsAndHasValidFormat) {
  if (keyExistsAndHasValidFormat) *keyExistsAndHasValidFormat = 1;
  if (!key) return 0;
  return [[NSUserDefaults standardUserDefaults]
             boolForKey:reinterpret_cast<NSString*>(
                            const_cast<__CFString*>(key))]
             ? 1
             : 0;
}

CFIndex CFPreferencesGetAppIntegerValue(CFStringRef key,
                                        CFStringRef /*applicationID*/,
                                        Boolean* keyExistsAndHasValidFormat) {
  if (keyExistsAndHasValidFormat) *keyExistsAndHasValidFormat = 1;
  if (!key) return 0;
  return static_cast<CFIndex>([[NSUserDefaults standardUserDefaults]
      integerForKey:reinterpret_cast<NSString*>(const_cast<__CFString*>(key))]);
}

void CFPreferencesSetAppValue(CFStringRef key, const void* value,
                              CFStringRef /*applicationID*/) {
  if (!key) return;
  [[NSUserDefaults standardUserDefaults]
      setObject:reinterpret_cast<id>(const_cast<void*>(value))
         forKey:reinterpret_cast<NSString*>(const_cast<__CFString*>(key))];
}

void CFPreferencesSetValue(CFStringRef key, const void* value,
                           CFStringRef appID, CFStringRef /*userName*/,
                           CFStringRef /*hostName*/) {
  CFPreferencesSetAppValue(key, value, appID);
}

Boolean CFPreferencesAppSynchronize(CFStringRef /*applicationID*/) { return 1; }
Boolean CFPreferencesSynchronize(CFStringRef /*appID*/,
                                 CFStringRef /*userName*/,
                                 CFStringRef /*hostName*/) {
  return 1;
}

static int g_dummy_runloop = 1;
static int g_dummy_msgport = 2;
static int g_dummy_rlsource = 3;
static int g_dummy_notif_center = 4;

void* CFRunLoopGetCurrent(void) { return &g_dummy_runloop; }
void* CFRunLoopGetMain(void) { return &g_dummy_runloop; }
void CFRunLoopAddSource(void* /*rl*/, void* /*source*/, CFStringRef /*mode*/) {}
void CFRunLoopRemoveSource(void* /*rl*/, void* /*source*/,
                           CFStringRef /*mode*/) {}
void CFRunLoopAddTimer(void* /*rl*/, void* /*timer*/, CFStringRef /*mode*/) {}
int32_t CFRunLoopRunInMode(CFStringRef /*mode*/, double /*seconds*/,
                           Boolean /*returnAfterSourceHandled*/) {
  return 1;
}
void CFRunLoopRun(void) {}
void CFRunLoopStop(void* /*rl*/) {}
void CFRunLoopWakeUp(void* /*rl*/) {}

void* CFMessagePortCreateLocal(CFAllocatorRef /*alloc*/, CFStringRef /*name*/,
                               void* /*callout*/, void* /*context*/,
                               Boolean* shouldFreeInfo) {
  if (shouldFreeInfo) *shouldFreeInfo = 0;
  return &g_dummy_msgport;
}

void* CFMessagePortCreateRemote(CFAllocatorRef /*alloc*/, CFStringRef /*name*/) {
  return &g_dummy_msgport;
}

void* CFMessagePortCreateRunLoopSource(CFAllocatorRef /*alloc*/,
                                       void* /*local*/, CFIndex /*order*/) {
  return &g_dummy_rlsource;
}

void CFMessagePortInvalidate(void* /*ms*/) {}
int32_t CFMessagePortSendRequest(void* /*remote*/, int32_t /*msgid*/,
                                 const void* /*data*/, double /*sendTimeout*/,
                                 double /*rcvTimeout*/, CFStringRef /*replyMode*/,
                                 const void** returnData) {
  if (returnData) *returnData = nullptr;
  return 0;
}
void CFMessagePortSetInvalidationCallBack(void* /*ms*/, void* /*callout*/) {}

void* CFMachPortCreateRunLoopSource(CFAllocatorRef /*alloc*/, void* /*port*/,
                                    CFIndex /*order*/) {
  return &g_dummy_rlsource;
}
void CFMachPortInvalidate(void* /*port*/) {}

void* CFNotificationCenterGetLocalCenter(void) { return &g_dummy_notif_center; }
void* CFNotificationCenterGetDistributedCenter(void) {
  return &g_dummy_notif_center;
}
void* CFNotificationCenterGetDarwinNotifyCenter(void) {
  return &g_dummy_notif_center;
}
void CFNotificationCenterAddObserver(void* /*center*/, const void* /*observer*/,
                                     void* /*callBack*/, CFStringRef /*name*/,
                                     const void* /*object*/,
                                     CFIndex /*suspensionBehavior*/) {}
void CFNotificationCenterRemoveObserver(void* /*center*/,
                                        const void* /*observer*/,
                                        CFStringRef /*name*/,
                                        const void* /*object*/) {}
void CFNotificationCenterPostNotification(void* /*center*/, CFStringRef /*name*/,
                                          const void* /*object*/,
                                          CFDictionaryRef /*userInfo*/,
                                          Boolean /*deliverImmediately*/) {}

double CFAbsoluteTimeGetCurrent(void) {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  return static_cast<double>(tv.tv_sec) - 978307200.0 +
         static_cast<double>(tv.tv_usec) / 1000000.0;
}

const void* CFDateCreate(CFAllocatorRef /*alloc*/, double /*at*/) {
  return MakeNSString("2026-10-19T00:00:00Z");
}

const void* CFPropertyListCreateWithData(CFAllocatorRef /*alloc*/,
                                         const void* data,
                                         unsigned long /*options*/,
                                         CFIndex* /*format*/,
                                         void** error) {
  if (error) *error = nullptr;
  if (!data) return nullptr;
  NSData* d = reinterpret_cast<NSData*>(const_cast<void*>(data));
  return ParsePlistBytes(static_cast<const char*>([d bytes]), [d length]);
}

const void* CFUUIDCreate(CFAllocatorRef /*alloc*/) {
  return MakeNSString("00000000-0000-4000-8000-000000000001");
}

CFStringRef CFUUIDCreateString(CFAllocatorRef /*alloc*/, const void* /*uuid*/) {
  return __CFStringMakeConstantString("00000000-0000-4000-8000-000000000001");
}

void* CFBundleCreate(CFAllocatorRef /*alloc*/, const void* /*bundleURL*/) {
  return [NSBundle mainBundle];
}

const void* CFBundleGetInfoDictionary(void* bundle) {
  NSBundle* b = bundle ? reinterpret_cast<NSBundle*>(bundle)
                       : [NSBundle mainBundle];
  return [b infoDictionary];
}

const void* CFBundleCopyInfoDictionaryInDirectory(const void* bundleURL) {
  const void* bundle = CFBundleCreate(nullptr, bundleURL);
  return CFBundleGetInfoDictionary(const_cast<void*>(bundle));
}

int32_t CFUserNotificationDisplayAlert(
    double /*timeout*/, unsigned long /*flags*/, const void* /*iconURL*/,
    const void* /*soundURL*/, const void* /*localizationURL*/,
    CFStringRef alertHeader, CFStringRef alertMessage,
    CFStringRef /*defaultButtonTitle*/, CFStringRef /*alternateButtonTitle*/,
    CFStringRef /*otherButtonTitle*/, unsigned long* responseFlags) {
  fprintf(stderr, "[CFUserNotification] %s - %s\n",
          alertHeader ? CFStringGetCStringPtr(alertHeader, 0) : "",
          alertMessage ? CFStringGetCStringPtr(alertMessage, 0) : "");
  if (responseFlags) *responseFlags = 0;
  return 0;
}

}  // extern "C"

