// SPDX-License-Identifier: GPL-3.0-or-later
// Native ARM64 Mach-O Objective-C 2.0 Runtime (libobjc.A.dylib) for Darling Embedded.

#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct mach_header;
struct mach_header_64;

extern "C" {
typedef void (*dyld_bulk_image_callback)(unsigned count,
                                         const struct mach_header* headers[],
                                         const char* paths[]);
void _dyld_register_for_bulk_image_loads(dyld_bulk_image_callback callback);
unsigned char* getsectiondata(const struct mach_header_64* mhp,
                              const char* segname, const char* sectname,
                              unsigned long* size);
}

namespace {

struct method_t {
  const char* name;
  const char* types;
  IMP imp;
};

struct method_list_t {
  uint32_t entsizeAndFlags;
  uint32_t count;
  method_t first;
};

struct ivar_t {
  int32_t* offset;
  const char* name;
  const char* type;
  uint32_t alignment_raw;
  uint32_t size;
};

struct ivar_list_t {
  uint32_t entsize;
  uint32_t count;
  ivar_t first;
};

struct class_ro_t {
  uint32_t flags;
  uint32_t instanceStart;
  uint32_t instanceSize;
  uint32_t reserved;
  const uint8_t* ivarLayout;
  const char* name;
  const method_list_t* baseMethods;
  const void* baseProtocols;
  const ivar_list_t* ivars;
  const uint8_t* weakIvarLayout;
  const void* baseProperties;
};

struct category_t {
  const char* name;
  Class cls;
  const method_list_t* instanceMethods;
  const method_list_t* classMethods;
  const void* protocols;
  const void* instanceProperties;
};

}  // namespace

struct objc_class : objc_object {
  Class superclass;
  void* cache_buckets;
  uintptr_t cache_mask;
  uintptr_t data_bits;

  const class_ro_t* ro() const {
    return reinterpret_cast<const class_ro_t*>(data_bits & ~7ULL);
  }
};

namespace {

constexpr size_t kMaxClasses = 1024;
constexpr size_t kMaxCategoryMethods = 2048;

struct ExtraMethod {
  Class cls;
  const char* name;
  IMP imp;
};

struct MethodRef {
  const char* name;
  IMP imp;
};

inline MethodRef GetMethodAt(const method_list_t* list, uint32_t index) {
  if (!list || index >= list->count) {
    return {nullptr, nullptr};
  }
  uint32_t flags = list->entsizeAndFlags;
  bool is_relative = (flags & 0x80000000U) != 0;
  if (is_relative) {
    uint32_t stride = flags & 0x7fffffffU & ~3U;
    if (stride < 12) stride = 12;
    const uint8_t* entry =
        reinterpret_cast<const uint8_t*>(&list->first) + index * stride;
    const auto* name_off = reinterpret_cast<const int32_t*>(entry);
    const auto* imp_off = reinterpret_cast<const int32_t*>(entry + 8);

    const char* name = nullptr;
    if (*name_off != 0) {
      int64_t noff = *name_off;
      uintptr_t name_addr =
          static_cast<uintptr_t>(reinterpret_cast<intptr_t>(name_off) + noff);
      if (flags & 0x40000000U) {
        // Direct selector name string
        name = reinterpret_cast<const char*>(name_addr);
      } else {
        // Indirect: pointer to selector string (selref)
        uintptr_t target_val = *reinterpret_cast<const uintptr_t*>(name_addr);
        if (target_val >= 0x100000000ULL) {
          name = reinterpret_cast<const char*>(target_val);
        } else {
          name = reinterpret_cast<const char*>(name_addr);
        }
      }
    }

    IMP imp = nullptr;
    if (*imp_off != 0) {
      int64_t ioff = *imp_off;
      uintptr_t imp_addr =
          static_cast<uintptr_t>(reinterpret_cast<intptr_t>(imp_off) + ioff);
      imp = reinterpret_cast<IMP>(imp_addr);
    }
    return {name, imp};
  } else {
    uint32_t stride = flags & ~3U;
    if (stride < sizeof(method_t)) stride = sizeof(method_t);
    const uint8_t* entry =
        reinterpret_cast<const uint8_t*>(&list->first) + index * stride;
    const auto* m = reinterpret_cast<const method_t*>(entry);
    return {m->name, m->imp};
  }
}

pthread_mutex_t g_objc_lock = PTHREAD_MUTEX_INITIALIZER;
Class g_classes[kMaxClasses];
size_t g_class_count = 0;
// Per-class realization state (parallel to g_classes): whether ivar offsets
// have been slid for the superclass's actual size, and the resulting size.
bool g_realized[kMaxClasses];
uint32_t g_instance_size[kMaxClasses];
ExtraMethod g_extra_methods[kMaxCategoryMethods];
size_t g_extra_method_count = 0;

bool SelectorMatches(const char* a, const char* b) {
  if (a == b) return true;
  if (!a || !b) return false;
  return strcmp(a, b) == 0;
}

inline bool ValidObjCPtr(const void* p) {
  uintptr_t u = reinterpret_cast<uintptr_t>(p);
  return u >= 0x1000ULL && (u >> 48) == 0;
}

void RegisterClassLocked(Class cls) {
  if (!cls) return;
  const class_ro_t* ro = cls->ro();
  if (!ro || !ro->name) return;
  for (size_t i = 0; i < g_class_count; ++i) {
    if (g_classes[i] == cls) return;
    const class_ro_t* existing_ro = g_classes[i]->ro();
    if (existing_ro && existing_ro->name &&
        strcmp(existing_ro->name, ro->name) == 0) {
      return;
    }
  }
  if (g_class_count < kMaxClasses) {
    g_classes[g_class_count++] = cls;
  }
}


const ivar_t* IvarAt(const ivar_list_t* list, uint32_t i) {
  uint32_t stride = list->entsize ? list->entsize : sizeof(ivar_t);
  return reinterpret_cast<const ivar_t*>(
      reinterpret_cast<const uint8_t*>(&list->first) + i * stride);
}

ssize_t ClassIndexLocked(Class cls) {
  for (size_t i = 0; i < g_class_count; ++i) {
    if (g_classes[i] == cls) return static_cast<ssize_t>(i);
  }
  return -1;
}

// Non-fragile ivar layout: a subclass compiled against an SDK in which its
// superclass was smaller must have its ivar offsets moved past the
// superclass's actual instance size (as libobjc's realizeClass does).
uint32_t RealizeClassLocked(Class cls, int depth = 0) {
  if (!cls) return sizeof(objc_object);
  const class_ro_t* ro = cls->ro();
  ssize_t idx = ClassIndexLocked(cls);
  if (idx >= 0 && g_realized[idx]) return g_instance_size[idx];
  uint32_t size = ro ? ro->instanceSize : sizeof(objc_object);
  if (ro && cls->superclass && depth < 64) {
    uint32_t super_size = RealizeClassLocked(cls->superclass, depth + 1);
    if (super_size > ro->instanceStart) {
      uint32_t diff = super_size - ro->instanceStart;
      // Keep ivar alignment: round the shift up to 8 bytes.
      diff = (diff + 7U) & ~7U;
      if (ro->ivars) {
        for (uint32_t i = 0; i < ro->ivars->count; ++i) {
          const ivar_t* iv = IvarAt(ro->ivars, i);
          if (iv->offset) *iv->offset += static_cast<int32_t>(diff);
        }
      }
      size = ro->instanceSize + diff;
    }
    if (size < super_size) size = super_size;
  }
  if (idx >= 0) {
    g_realized[idx] = true;
    g_instance_size[idx] = size;
  }
  return size;
}

void AttachMethodListLocked(Class cls, const method_list_t* list) {
  if (!cls || !list) return;
  for (uint32_t i = 0; i < list->count; ++i) {
    MethodRef m = GetMethodAt(list, i);
    if (m.name && m.imp && g_extra_method_count < kMaxCategoryMethods) {
      g_extra_methods[g_extra_method_count++] = {cls, m.name, m.imp};
    }
  }
}

IMP LookupMethodInClass(Class cls, SEL sel) {
  if (!ValidObjCPtr(cls) || !ValidObjCPtr(sel)) return nullptr;
  size_t depth = 0;
  for (Class cur = cls; ValidObjCPtr(cur) && depth < 32;
       cur = cur->superclass, ++depth) {
    const class_ro_t* ro = cur->ro();
    if (ValidObjCPtr(ro) && ValidObjCPtr(ro->baseMethods)) {
      const method_list_t* mlist = ro->baseMethods;
      for (uint32_t i = 0; i < mlist->count; ++i) {
        MethodRef m = GetMethodAt(mlist, i);
        if (SelectorMatches(m.name, sel)) {
          return m.imp;
        }
      }
    }
    for (size_t i = g_extra_method_count; i > 0; --i) {
      const ExtraMethod& em = g_extra_methods[i - 1];
      if (em.cls == cur && SelectorMatches(em.name, sel)) {
        return em.imp;
      }
    }
  }
  return nullptr;
}

void ScanObjCSections(unsigned count, const struct mach_header* headers[],
                      const char* /*paths*/[]) {
  pthread_mutex_lock(&g_objc_lock);
  const char* segments[] = {"__DATA", "__DATA_CONST"};
  for (unsigned i = 0; i < count; ++i) {
    const auto* mh = reinterpret_cast<const struct mach_header_64*>(headers[i]);
    if (!mh) continue;
    for (const char* seg : segments) {
      unsigned long size = 0;
      auto* classlist = reinterpret_cast<Class*>(
          getsectiondata(mh, seg, "__objc_classlist", &size));
      if (classlist && size >= sizeof(Class)) {
        size_t n = size / sizeof(Class);
        for (size_t j = 0; j < n; ++j) {
          RegisterClassLocked(classlist[j]);
        }
      }
      unsigned long cat_size = 0;
      auto* catlist = reinterpret_cast<category_t**>(
          getsectiondata(mh, seg, "__objc_catlist", &cat_size));
      if (catlist && cat_size >= sizeof(category_t*)) {
        size_t n = cat_size / sizeof(category_t*);
        for (size_t j = 0; j < n; ++j) {
          category_t* cat = catlist[j];
          if (!cat || !cat->cls) continue;
          AttachMethodListLocked(cat->cls, cat->instanceMethods);
          AttachMethodListLocked(cat->cls->isa, cat->classMethods);
        }
      }
    }
  }
  pthread_mutex_unlock(&g_objc_lock);
}

__attribute__((constructor)) void InitializeDarlingObjCRuntime() {
  _dyld_register_for_bulk_image_loads(ScanObjCSections);
}

}  // namespace

extern "C" {

void* _objc_empty_cache[2] = {nullptr, nullptr};

IMP _objc_lookup_imp(id receiver, SEL sel) {
  if (!ValidObjCPtr(receiver) || !ValidObjCPtr(sel) ||
      !ValidObjCPtr(receiver->isa)) {
    return nullptr;
  }
  IMP imp = LookupMethodInClass(receiver->isa, sel);
  if (!imp) {
    fprintf(stderr, "[ObjC] Method not found: [%s %s]\n",
            class_getName(receiver->isa), sel ? sel : "<null>");
  }
  return imp;
}

IMP _objc_lookup_super2_imp(struct objc_super2* super_ref, SEL sel) {
  if (!ValidObjCPtr(super_ref) || !ValidObjCPtr(super_ref->receiver) ||
      !ValidObjCPtr(super_ref->current_class) || !ValidObjCPtr(sel)) {
    return nullptr;
  }
  Class target_cls = super_ref->current_class->superclass;
  if (!ValidObjCPtr(target_cls)) return nullptr;
  return LookupMethodInClass(target_cls, sel);
}

SEL sel_registerName(const char* name) { return name; }

const char* sel_getName(SEL sel) { return sel ? sel : "<null selector>"; }

bool sel_isEqual(SEL lhs, SEL rhs) { return SelectorMatches(lhs, rhs); }

Class objc_lookUpClass(const char* name) {
  if (!name) return nullptr;
  pthread_mutex_lock(&g_objc_lock);
  Class found = nullptr;
  for (size_t i = 0; i < g_class_count; ++i) {
    const class_ro_t* ro = g_classes[i]->ro();
    if (ro && ro->name && strcmp(ro->name, name) == 0) {
      found = g_classes[i];
      break;
    }
  }
  pthread_mutex_unlock(&g_objc_lock);
  return found;
}

Class objc_getClass(const char* name) { return objc_lookUpClass(name); }

Class objc_getMetaClass(const char* name) {
  Class cls = objc_lookUpClass(name);
  return cls ? cls->isa : nullptr;
}

const char* class_getName(Class cls) {
  if (!cls) return "nil";
  const class_ro_t* ro = cls->ro();
  return (ro && ro->name) ? ro->name : "unknown";
}

Class class_getSuperclass(Class cls) { return cls ? cls->superclass : nullptr; }

size_t class_getInstanceSize(Class cls) {
  if (!cls) return sizeof(objc_object);
  pthread_mutex_lock(&g_objc_lock);
  size_t size = RealizeClassLocked(cls);
  pthread_mutex_unlock(&g_objc_lock);
  if (size < sizeof(objc_object)) size = sizeof(objc_object);
  return (size + 7U) & ~7U;
}

Ivar class_getInstanceVariable(Class cls, const char* name) {
  if (!cls || !name) return nullptr;
  pthread_mutex_lock(&g_objc_lock);
  RealizeClassLocked(cls);
  pthread_mutex_unlock(&g_objc_lock);
  for (Class cur = cls; cur != nullptr; cur = cur->superclass) {
    const class_ro_t* ro = cur->ro();
    if (!ro || !ro->ivars) continue;
    for (uint32_t i = 0; i < ro->ivars->count; ++i) {
      const ivar_t* iv = IvarAt(ro->ivars, i);
      if (iv->name && strcmp(iv->name, name) == 0) {
        return reinterpret_cast<Ivar>(const_cast<ivar_t*>(iv));
      }
    }
  }
  return nullptr;
}

ptrdiff_t ivar_getOffset(Ivar ivar) {
  const auto* iv = reinterpret_cast<const ivar_t*>(ivar);
  return (iv && iv->offset) ? *iv->offset : 0;
}

const char* ivar_getName(Ivar ivar) {
  const auto* iv = reinterpret_cast<const ivar_t*>(ivar);
  return iv ? iv->name : nullptr;
}

const char* ivar_getTypeEncoding(Ivar ivar) {
  const auto* iv = reinterpret_cast<const ivar_t*>(ivar);
  return iv ? iv->type : nullptr;
}

id object_getIvar(id obj, Ivar ivar) {
  if (!obj || !ivar) return nullptr;
  return *reinterpret_cast<id*>(reinterpret_cast<uint8_t*>(obj) +
                                ivar_getOffset(ivar));
}

void object_setIvar(id obj, Ivar ivar, id value) {
  if (!obj || !ivar) return;
  *reinterpret_cast<id*>(reinterpret_cast<uint8_t*>(obj) +
                         ivar_getOffset(ivar)) = value;
}

bool class_respondsToSelector(Class cls, SEL sel) {
  if (!cls || !sel) return false;
  return LookupMethodInClass(cls, sel) != nullptr;
}

IMP class_getMethodImplementation(Class cls, SEL sel) {
  return LookupMethodInClass(cls, sel);
}

Class object_getClass(id obj) {
  return obj ? obj->isa : nullptr;
}

Class object_setClass(id obj, Class cls) {
  if (!obj) return nullptr;
  Class old = obj->isa;
  obj->isa = cls;
  return old;
}

id objc_alloc(Class cls) {
  if (!cls) return nullptr;
  size_t size = class_getInstanceSize(cls);
  if (size < 16) size = 16;
  auto* obj = static_cast<objc_object*>(calloc(1, size));
  if (!obj) return nullptr;
  obj->isa = cls;
  return obj;
}

id objc_alloc_init(Class cls) {
  id obj = objc_alloc(cls);
  if (!obj) return nullptr;
  typedef id (*InitFn)(id, SEL);
  return reinterpret_cast<InitFn>(objc_msgSend)(obj, "init");
}

id objc_opt_new(Class cls) {
  return objc_alloc_init(cls);
}

id objc_retain(id obj) { return obj; }

id objc_retainAutorelease(id obj) { return obj; }

id objc_retainBlock(id obj) { return obj; }

id objc_loadWeakRetained(id* location) { return location ? *location : nullptr; }

id objc_loadWeak(id* location) { return location ? *location : nullptr; }

id objc_storeWeak(id* location, id obj) {
  if (location) *location = obj;
  return obj;
}

id objc_initWeak(id* location, id obj) { return objc_storeWeak(location, obj); }

void objc_destroyWeak(id* location) {
  if (location) *location = nullptr;
}

void objc_copyWeak(id* to, id* from) {
  if (to) *to = from ? *from : nullptr;
}

void objc_moveWeak(id* to, id* from) {
  objc_copyWeak(to, from);
  if (from) *from = nullptr;
}

// Synthesized property accessors (objc4 objc-accessors.mm semantics; this
// runtime has no-op reference counting, so "copy" sends -copy and atomic
// accessors need no spinlock for single-threaded AppKit code).
id objc_getProperty(id self, SEL /*_cmd*/, ptrdiff_t offset, bool /*atomic*/) {
  if (!self) return nullptr;
  return *reinterpret_cast<id*>(reinterpret_cast<uint8_t*>(self) + offset);
}

static void SetPropertyImpl(id self, ptrdiff_t offset, id value, bool copy) {
  if (!self) return;
  if (copy && value) {
    typedef id (*CopyFn)(id, SEL);
    value = reinterpret_cast<CopyFn>(objc_msgSend)(value, "copy");
  }
  *reinterpret_cast<id*>(reinterpret_cast<uint8_t*>(self) + offset) = value;
}

void objc_setProperty(id self, SEL /*_cmd*/, ptrdiff_t offset, id value, bool /*atomic*/,
                      signed char shouldCopy) {
  SetPropertyImpl(self, offset, value, shouldCopy != 0);
}
void objc_setProperty_atomic(id self, SEL, id value, ptrdiff_t offset) {
  SetPropertyImpl(self, offset, value, false);
}
void objc_setProperty_nonatomic(id self, SEL, id value, ptrdiff_t offset) {
  SetPropertyImpl(self, offset, value, false);
}
void objc_setProperty_atomic_copy(id self, SEL, id value, ptrdiff_t offset) {
  SetPropertyImpl(self, offset, value, true);
}
void objc_setProperty_nonatomic_copy(id self, SEL, id value, ptrdiff_t offset) {
  SetPropertyImpl(self, offset, value, true);
}

void objc_copyStruct(void* dest, const void* src, ptrdiff_t size, bool /*atomic*/,
                     bool /*hasStrong*/) {
  memcpy(dest, src, static_cast<size_t>(size));
}

void objc_release(id /*obj*/) {}

id objc_autorelease(id obj) { return obj; }

id objc_autoreleaseReturnValue(id obj) { return obj; }

id objc_retainAutoreleasedReturnValue(id obj) { return obj; }

id objc_retainAutoreleaseReturnValue(id obj) { return obj; }

id objc_unsafeClaimAutoreleasedReturnValue(id obj) { return obj; }

id objc_claimAutoreleasedReturnValue(id obj) { return obj; }

id objc_allocWithZone(Class cls) { return objc_alloc(cls); }

id objc_opt_self(id obj) { return obj; }

int __objc_personality_v0(int /*version*/, int /*actions*/,
                          uint64_t /*exceptionClass*/,
                          void* /*exceptionObject*/, void* /*context*/) {
  return 8;  // _URC_CONTINUE_UNWIND
}

id objc_begin_catch(void* exc_buf) {
  return reinterpret_cast<id>(exc_buf);
}

void objc_end_catch(void) {}

void objc_exception_rethrow(void) {}

void objc_terminate(void) {
  exit(0);
}

int objc_sync_enter(id /*obj*/) { return 0; }

int objc_sync_exit(id /*obj*/) { return 0; }

void* _OBJC_EHTYPE_$_NSException[4] = {nullptr, nullptr, nullptr, nullptr};

struct objc_method_description_ret {
  SEL name;
  const char* types;
};

objc_method_description_ret protocol_getMethodDescription(
    void* /*proto*/, SEL aSel, bool /*isRequiredMethod*/,
    bool /*isInstanceMethod*/) {
  return {aSel, "@@:"};
}

void objc_enumerationMutation(id /*obj*/) {}

void* objc_autoreleasePoolPush(void) {
  static int token = 1;
  return &token;
}

void objc_autoreleasePoolPop(void* /*pool*/) {}

void objc_storeStrong(id* location, id obj) {
  if (location) *location = obj;
}

Class objc_opt_class(id obj) {
  return ValidObjCPtr(obj) ? obj->isa : nullptr;
}

bool objc_opt_isKindOfClass(id obj, Class other) {
  if (!ValidObjCPtr(obj) || !ValidObjCPtr(other)) return false;
  for (Class cur = obj->isa; ValidObjCPtr(cur); cur = cur->superclass) {
    if (cur == other) return true;
  }
  return false;
}

bool objc_opt_respondsToSelector(id obj, SEL sel) {
  if (!ValidObjCPtr(obj) || !ValidObjCPtr(sel)) return false;
  return class_respondsToSelector(obj->isa, sel);
}

int __cxa_guard_acquire(uint64_t* guard) {
  return *reinterpret_cast<volatile uint8_t*>(guard) == 0;
}

void __cxa_guard_release(uint64_t* guard) {
  *reinterpret_cast<volatile uint8_t*>(guard) = 1;
}

void __cxa_guard_abort(uint64_t* guard) {
  (void)guard;
}

void __cxa_pure_virtual() {
  while (1) {}
}

}  // extern "C"
