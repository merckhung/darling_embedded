// SPDX-License-Identifier: GPL-3.0-or-later
// Parser for Apple compiled-nib "NIBArchive" files (the format produced by
// ibtool for macOS nibs). Dependency-free C++ (no libc++) so it can be used
// both inside the guest AppKit (built with -nostdinc++) and in host tools.
//
// File layout (all integers little-endian):
//   char     magic[10] = "NIBArchive"
//   int32    formatVersion (1), coderVersion (9 or 10)
//   uint32   objectCount, objectsOffset
//   uint32   keyCount,    keysOffset
//   uint32   valueCount,  valuesOffset
//   uint32   classCount,  classesOffset
// Object:  varint classIndex, varint firstValueIndex, varint valueCount
// Key:     varint length, bytes[length]
// Value:   varint keyIndex, uint8 type, payload (see NibValueType)
// Class:   varint length, varint extraCount, int32 extra[extraCount],
//          bytes[length] (NUL-terminated name)
// Varints store 7 bits per byte, least-significant group first; the high
// bit is set on the *final* byte.

#ifndef DARLING_FRAMEWORKS_NIBARCHIVE_H_
#define DARLING_FRAMEWORKS_NIBARCHIVE_H_

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

namespace darling_nib {

enum NibValueType : uint8_t {
  kInt8 = 0,
  kInt16 = 1,
  kInt32 = 2,
  kInt64 = 3,
  kTrue = 4,
  kFalse = 5,
  kFloat = 6,
  kDouble = 7,
  kData = 8,
  kNil = 9,
  kObjectRef = 10,
};

struct NibObject {
  uint32_t class_index;
  uint32_t first_value;
  uint32_t value_count;
};

struct NibValue {
  uint32_t key_index;
  uint8_t type;
  int64_t int_value;       // kInt*, kTrue(1)/kFalse(0)
  double double_value;     // kFloat/kDouble
  const uint8_t* data;     // kData
  uint32_t data_len;       // kData
  uint32_t object_ref;     // kObjectRef
};

struct NibString {
  const char* ptr;
  uint32_t len;
};

struct NibArchive {
  uint32_t object_count = 0;
  uint32_t key_count = 0;
  uint32_t value_count = 0;
  uint32_t class_count = 0;
  NibObject* objects = nullptr;
  NibString* keys = nullptr;
  NibValue* values = nullptr;
  NibString* classes = nullptr;

  ~NibArchive() {
    free(objects);
    free(keys);
    free(values);
    free(classes);
  }

  const char* ClassNameOf(uint32_t obj) const {
    if (obj >= object_count) return nullptr;
    uint32_t ci = objects[obj].class_index;
    return ci < class_count ? classes[ci].ptr : nullptr;
  }

  bool KeyEquals(uint32_t key_index, const char* name) const {
    if (key_index >= key_count) return false;
    size_t n = strlen(name);
    return keys[key_index].len == n && memcmp(keys[key_index].ptr, name, n) == 0;
  }

  // Returns the value of `key` on object `obj`, or nullptr.
  const NibValue* Find(uint32_t obj, const char* key) const {
    if (obj >= object_count) return nullptr;
    const NibObject& o = objects[obj];
    for (uint32_t i = 0; i < o.value_count; ++i) {
      uint32_t vi = o.first_value + i;
      if (vi < value_count && KeyEquals(values[vi].key_index, key)) {
        return &values[vi];
      }
    }
    return nullptr;
  }
};

namespace internal {

inline bool ReadVarint(const uint8_t* buf, size_t len, size_t* pos,
                       uint32_t* out) {
  uint32_t result = 0;
  int shift = 0;
  while (*pos < len && shift < 35) {
    uint8_t b = buf[(*pos)++];
    result |= static_cast<uint32_t>(b & 0x7F) << shift;
    if (b & 0x80) {
      *out = result;
      return true;
    }
    shift += 7;
  }
  return false;
}

inline uint32_t ReadU32(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

inline uint64_t ReadU64(const uint8_t* p) {
  return static_cast<uint64_t>(ReadU32(p)) |
         (static_cast<uint64_t>(ReadU32(p + 4)) << 32);
}

}  // namespace internal

// Parses `buf` (which must outlive `out`, since strings/data point into it).
inline bool ParseNibArchive(const uint8_t* buf, size_t len, NibArchive* out) {
  using internal::ReadU32;
  using internal::ReadVarint;
  if (len < 50 || memcmp(buf, "NIBArchive", 10) != 0) return false;
  out->object_count = ReadU32(buf + 18);
  uint32_t objects_off = ReadU32(buf + 22);
  out->key_count = ReadU32(buf + 26);
  uint32_t keys_off = ReadU32(buf + 30);
  out->value_count = ReadU32(buf + 34);
  uint32_t values_off = ReadU32(buf + 38);
  out->class_count = ReadU32(buf + 42);
  uint32_t classes_off = ReadU32(buf + 46);
  if (out->object_count > 1000000 || out->key_count > 1000000 ||
      out->value_count > 1000000 || out->class_count > 100000) {
    return false;
  }
  out->objects = static_cast<NibObject*>(
      calloc(out->object_count + 1, sizeof(NibObject)));
  out->keys = static_cast<NibString*>(calloc(out->key_count + 1, sizeof(NibString)));
  out->values =
      static_cast<NibValue*>(calloc(out->value_count + 1, sizeof(NibValue)));
  out->classes =
      static_cast<NibString*>(calloc(out->class_count + 1, sizeof(NibString)));
  if (!out->objects || !out->keys || !out->values || !out->classes) return false;

  size_t pos = objects_off;
  for (uint32_t i = 0; i < out->object_count; ++i) {
    NibObject& o = out->objects[i];
    if (!ReadVarint(buf, len, &pos, &o.class_index) ||
        !ReadVarint(buf, len, &pos, &o.first_value) ||
        !ReadVarint(buf, len, &pos, &o.value_count)) {
      return false;
    }
  }
  pos = keys_off;
  for (uint32_t i = 0; i < out->key_count; ++i) {
    uint32_t klen = 0;
    if (!ReadVarint(buf, len, &pos, &klen) || pos + klen > len) return false;
    out->keys[i] = {reinterpret_cast<const char*>(buf + pos), klen};
    pos += klen;
  }
  pos = values_off;
  for (uint32_t i = 0; i < out->value_count; ++i) {
    NibValue& v = out->values[i];
    if (!ReadVarint(buf, len, &pos, &v.key_index) || pos >= len) return false;
    v.type = buf[pos++];
    switch (v.type) {
      case kInt8:
        if (pos + 1 > len) return false;
        v.int_value = static_cast<int8_t>(buf[pos]);
        pos += 1;
        break;
      case kInt16:
        if (pos + 2 > len) return false;
        v.int_value = static_cast<int16_t>(buf[pos] | (buf[pos + 1] << 8));
        pos += 2;
        break;
      case kInt32:
        if (pos + 4 > len) return false;
        v.int_value = static_cast<int32_t>(ReadU32(buf + pos));
        pos += 4;
        break;
      case kInt64:
        if (pos + 8 > len) return false;
        v.int_value = static_cast<int64_t>(internal::ReadU64(buf + pos));
        pos += 8;
        break;
      case kTrue:
        v.int_value = 1;
        break;
      case kFalse:
        v.int_value = 0;
        break;
      case kFloat: {
        if (pos + 4 > len) return false;
        uint32_t bits = ReadU32(buf + pos);
        float f;
        memcpy(&f, &bits, 4);
        v.double_value = f;
        pos += 4;
        break;
      }
      case kDouble: {
        if (pos + 8 > len) return false;
        uint64_t bits = internal::ReadU64(buf + pos);
        memcpy(&v.double_value, &bits, 8);
        pos += 8;
        break;
      }
      case kData: {
        uint32_t dlen = 0;
        if (!ReadVarint(buf, len, &pos, &dlen) || pos + dlen > len) return false;
        v.data = buf + pos;
        v.data_len = dlen;
        pos += dlen;
        break;
      }
      case kNil:
        break;
      case kObjectRef:
        if (pos + 4 > len) return false;
        v.object_ref = ReadU32(buf + pos);
        pos += 4;
        break;
      default:
        return false;
    }
  }
  pos = classes_off;
  for (uint32_t i = 0; i < out->class_count; ++i) {
    uint32_t clen = 0, extra = 0;
    if (!ReadVarint(buf, len, &pos, &clen) || !ReadVarint(buf, len, &pos, &extra)) {
      return false;
    }
    pos += static_cast<size_t>(extra) * 4;
    if (pos + clen > len) return false;
    out->classes[i] = {reinterpret_cast<const char*>(buf + pos), clen};
    pos += clen;
  }
  return true;
}

}  // namespace darling_nib

#endif  // DARLING_FRAMEWORKS_NIBARCHIVE_H_
