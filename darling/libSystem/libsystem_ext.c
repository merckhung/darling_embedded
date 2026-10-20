// SPDX-License-Identifier: GPL-3.0-or-later
// Supplemental libSystem symbols (Stack Protector, Libdispatch / GCD)
// for Darling Embedded Mach-O userland on ARM64 XNU/Darwin.

#include <stdint.h>

extern void _exit(int);

uintptr_t __stack_chk_guard = 0x595e9fbd94fda766ULL;

void __stack_chk_fail(void) {
  while (1) {
    _exit(127);
  }
}

struct dispatch_queue_s {
  int dummy;
};
static struct dispatch_queue_s g_main_queue = {1};
struct dispatch_queue_s* const _dispatch_main_q = &g_main_queue;

typedef void (^dispatch_block_t)(void);

void dispatch_async(void* queue, dispatch_block_t block) {
  (void)queue;
  if (block) {
    struct Block_literal {
      void* isa;
      int flags;
      int reserved;
      void (*invoke)(void*);
    };
    struct Block_literal* b = (struct Block_literal*)block;
    if (b && b->invoke) {
      b->invoke(block);
    }
  }
}

void* dispatch_get_global_queue(long identifier, unsigned long flags) {
  (void)identifier;
  (void)flags;
  return &g_main_queue;
}

void dispatch_once(long* predicate, dispatch_block_t block) {
  if (!predicate) return;
  if (*predicate == 0) {
    *predicate = 1;
    if (block) {
      struct Block_literal {
        void* isa;
        int flags;
        int reserved;
        void (*invoke)(void*);
      };
      struct Block_literal* b = (struct Block_literal*)block;
      if (b && b->invoke) {
        b->invoke(block);
      }
    }
    *predicate = 2;
  }
}

// ---------------------------------------------------------------------------
// Symbols required by binaries built with current Xcode that the native
// libSystem does not export.
// ---------------------------------------------------------------------------

#include <stddef.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

extern int posix_memalign(void** memptr, size_t alignment, size_t size);
extern void* malloc(size_t size);
extern void* calloc(size_t count, size_t size);
extern void* realloc(void* ptr, size_t size);
extern void free(void* ptr);

// C11 aligned_alloc on top of posix_memalign.
void* aligned_alloc(size_t alignment, size_t size) {
  void* p = 0;
  if (alignment < sizeof(void*)) alignment = sizeof(void*);
  return posix_memalign(&p, alignment, size) == 0 ? p : 0;
}

// _NSGetExecutablePath (normally in libdyld): the executable path is the
// first string of this process's KERN_PROCARGS2 block.
int _NSGetExecutablePath(char* buf, uint32_t* bufsize) {
  if (!bufsize) return -1;
  int mib[3] = {CTL_KERN, KERN_PROCARGS2, getpid()};
  static char args[16384];
  size_t len = sizeof(args);
  if (sysctl(mib, 3, args, &len, 0, 0) != 0 || len <= sizeof(int)) return -1;
  const char* path = args + sizeof(int);
  size_t n = strnlen(path, len - sizeof(int));
  if (!buf || *bufsize < n + 1) {
    *bufsize = (uint32_t)(n + 1);
    return -1;
  }
  memcpy(buf, path, n);
  buf[n] = '\0';
  return 0;
}

// Minimal malloc zone registry with libmalloc's malloc_zone_t layout. The
// default zone forwards to the process allocator.
typedef struct _malloc_zone_t {
  void* reserved1;
  void* reserved2;
  size_t (*size)(struct _malloc_zone_t*, const void*);
  void* (*malloc)(struct _malloc_zone_t*, size_t);
  void* (*calloc)(struct _malloc_zone_t*, size_t, size_t);
  void* (*valloc)(struct _malloc_zone_t*, size_t);
  void (*free)(struct _malloc_zone_t*, void*);
  void* (*realloc)(struct _malloc_zone_t*, void*, size_t);
  void (*destroy)(struct _malloc_zone_t*);
  const char* zone_name;
  unsigned (*batch_malloc)(struct _malloc_zone_t*, size_t, void**, unsigned);
  void (*batch_free)(struct _malloc_zone_t*, void**, unsigned);
  void* introspect;
  unsigned version;
  void* (*memalign)(struct _malloc_zone_t*, size_t, size_t);
  void (*free_definite_size)(struct _malloc_zone_t*, void*, size_t);
  size_t (*pressure_relief)(struct _malloc_zone_t*, size_t);
} malloc_zone_t;

static size_t zone_size(malloc_zone_t* z, const void* p) { (void)z; (void)p; return 0; }
static void* zone_malloc(malloc_zone_t* z, size_t n) { (void)z; return malloc(n); }
static void* zone_calloc(malloc_zone_t* z, size_t c, size_t n) { (void)z; return calloc(c, n); }
static void* zone_valloc(malloc_zone_t* z, size_t n) {
  (void)z;
  void* p = 0;
  return posix_memalign(&p, 16384, n) == 0 ? p : 0;
}
static void zone_free(malloc_zone_t* z, void* p) { (void)z; free(p); }
static void* zone_realloc(malloc_zone_t* z, void* p, size_t n) { (void)z; return realloc(p, n); }
static void* zone_memalign(malloc_zone_t* z, size_t a, size_t n) {
  (void)z;
  void* p = 0;
  return posix_memalign(&p, a, n) == 0 ? p : 0;
}
static void zone_free_definite(malloc_zone_t* z, void* p, size_t n) { (void)z; (void)n; free(p); }

static malloc_zone_t g_default_zone = {
    0, 0, zone_size, zone_malloc, zone_calloc, zone_valloc, zone_free,
    zone_realloc, 0, "DefaultMallocZone", 0, 0, 0, 9, zone_memalign,
    zone_free_definite, 0};

#define MAX_MALLOC_ZONES 32
static malloc_zone_t* g_zones[MAX_MALLOC_ZONES] = {&g_default_zone};
static unsigned g_zone_count = 1;

malloc_zone_t* malloc_default_zone(void) { return &g_default_zone; }
malloc_zone_t* malloc_default_purgeable_zone(void) { return &g_default_zone; }

void malloc_zone_register(malloc_zone_t* zone) {
  if (!zone || g_zone_count >= MAX_MALLOC_ZONES) return;
  for (unsigned i = 0; i < g_zone_count; ++i) {
    if (g_zones[i] == zone) return;
  }
  g_zones[g_zone_count++] = zone;
}

void malloc_zone_unregister(malloc_zone_t* zone) {
  for (unsigned i = 0; i < g_zone_count; ++i) {
    if (g_zones[i] == zone) {
      g_zones[i] = g_zones[--g_zone_count];
      return;
    }
  }
}

// kern_return_t malloc_get_all_zones(task_t, memory_reader_t,
//                                    vm_address_t** addresses, unsigned* count)
int malloc_get_all_zones(unsigned task, void* reader, uintptr_t** addresses,
                         unsigned* count) {
  (void)task;
  (void)reader;
  if (addresses) *addresses = (uintptr_t*)g_zones;
  if (count) *count = g_zone_count;
  return 0;
}

// Apple's arm64 SDK binds plain fopen/realpath; this libc exports only the
// $DARWIN_EXTSN variants (identical behaviour on 64-bit).
typedef struct __sFILE FILE;
extern FILE* fopen_extsn(const char* path, const char* mode) __asm("_fopen$DARWIN_EXTSN");
FILE* fopen(const char* path, const char* mode) { return fopen_extsn(path, mode); }

extern char* realpath_extsn(const char* path, char* resolved) __asm("_realpath$DARWIN_EXTSN");
char* realpath(const char* path, char* resolved) { return realpath_extsn(path, resolved); }

// dispatch_once with a function pointer (libdispatch's dispatch_once_f).
void dispatch_once_f(long* predicate, void* context, void (*function)(void*)) {
  if (!predicate || *predicate != 0) return;
  *predicate = 1;
  if (function) function(context);
  *predicate = ~0L;
}

// Backs @available(...) checks. Every requested macOS version is reported
// as available: this userland implements a subset of the current SDK's API
// rather than an older OS, and missing methods fail softly (nil messaging).
typedef struct {
  uint32_t platform;
  uint32_t version;
} dyld_build_version_t;
int _availability_version_check(uint32_t count, dyld_build_version_t versions[]) {
  (void)count;
  (void)versions;
  return 1;
}

// C99 fmax family (missing from the native libm). NaN arguments are ignored
// as required by C99 7.12.12.2.
double fmax(double x, double y) {
  if (x != x) return y;
  if (y != y) return x;
  return x > y ? x : y;
}
float fmaxf(float x, float y) {
  if (x != x) return y;
  if (y != y) return x;
  return x > y ? x : y;
}
float fminf(float x, float y) {
  if (x != x) return y;
  if (y != y) return x;
  return x < y ? x : y;
}

// ---------------------------------------------------------------------------
// Additional GCD (libdispatch), os_log, libmalloc, and Darwin BSD symbols
// required by unmodified macOS ARM64/arm64e applications.
// ---------------------------------------------------------------------------

int _dispatch_queue_attr_concurrent = 0;
int _dispatch_source_type_timer = 1;
int _dispatch_source_type_signal = 2;

struct dispatch_source_s {
  void* type;
  dispatch_block_t handler;
  int resumed;
};

void* dispatch_queue_create(const char* label, void* attr) {
  (void)label;
  (void)attr;
  return &g_main_queue;
}

void dispatch_sync(void* queue, dispatch_block_t block) {
  dispatch_async(queue, block);
}

uint64_t dispatch_time(uint64_t when, int64_t delta) {
  return when + (uint64_t)(delta > 0 ? delta : 0);
}

void dispatch_after(uint64_t when, void* queue, dispatch_block_t block) {
  (void)when;
  dispatch_async(queue, block);
}

void* dispatch_source_create(void* type, uintptr_t handle, unsigned long mask,
                             void* queue) {
  (void)handle;
  (void)mask;
  (void)queue;
  struct dispatch_source_s* src =
      (struct dispatch_source_s*)calloc(1, sizeof(struct dispatch_source_s));
  if (src) src->type = type;
  return src;
}

void dispatch_source_set_timer(void* source, uint64_t start, uint64_t interval,
                               uint64_t leeway) {
  (void)source;
  (void)start;
  (void)interval;
  (void)leeway;
}

void dispatch_source_set_event_handler(void* source, dispatch_block_t handler) {
  struct dispatch_source_s* src = (struct dispatch_source_s*)source;
  if (src) src->handler = handler;
}

void dispatch_source_cancel(void* source) {
  struct dispatch_source_s* src = (struct dispatch_source_s*)source;
  if (src) src->handler = 0;
}

void dispatch_resume(void* object) {
  struct dispatch_source_s* src = (struct dispatch_source_s*)object;
  if (src && src->type == &_dispatch_source_type_timer && src->handler &&
      !src->resumed) {
    src->resumed = 1;
    dispatch_async(&g_main_queue, src->handler);
  }
}

void dispatch_suspend(void* object) {
  (void)object;
}

void dispatch_assert_queue_v2(void* queue) __asm("_dispatch_assert_queue$V2");
void dispatch_assert_queue_v2(void* queue) {
  (void)queue;
}

int _os_log_default = 0;

void* os_log_create(const char* subsystem, const char* category) {
  (void)subsystem;
  (void)category;
  return &_os_log_default;
}

int os_log_type_enabled(void* oslog, uint8_t type) {
  (void)oslog;
  (void)type;
  return 0;
}

void _os_log_impl(void* dso, void* log, uint8_t type, const char* format,
                  uint8_t* buf, uint32_t size) {
  (void)dso;
  (void)log;
  (void)type;
  (void)format;
  (void)buf;
  (void)size;
}

void _os_log_error_impl(void* dso, void* log, uint8_t type, const char* format,
                        uint8_t* buf, uint32_t size) {
  (void)dso;
  (void)log;
  (void)type;
  (void)format;
  (void)buf;
  (void)size;
}

void _os_log_debug_impl(void* dso, void* log, uint8_t type, const char* format,
                        uint8_t* buf, uint32_t size) {
  (void)dso;
  (void)log;
  (void)type;
  (void)format;
  (void)buf;
  (void)size;
}

void* _os_log_send_and_compose_impl(unsigned long flags, void* reg, void* log,
                                    uint8_t type, const char* fmt, ...) {
  (void)flags;
  (void)reg;
  (void)log;
  (void)type;
  (void)fmt;
  return 0;
}

void* malloc_type_calloc(size_t count, size_t size, uint64_t type_id) {
  (void)type_id;
  return calloc(count, size);
}

uint32_t notify_register_dispatch(const char* name, int* out_token, void* queue,
                                  void* handler) {
  (void)name;
  (void)queue;
  (void)handler;
  if (out_token) *out_token = 0;
  return 0;
}

long fsgetpath(char* buf, size_t buflen, void* fsid, uint64_t objid) {
  (void)fsid;
  (void)objid;
  if (buf && buflen > 0) {
    buf[0] = '/';
    if (buflen > 1) buf[1] = '\0';
    return 1;
  }
  return -1;
}

int responsibility_set_caller_responsible_for_self(void) { return 0; }

int responsibility_set_audittoken_responsible_for_caller(void* token) {
  (void)token;
  return 0;
}

size_t __strlcpy_chk(char* dst, const char* src, size_t dstsize,
                     size_t objsize) {
  (void)objsize;
  size_t srclen = src ? strlen(src) : 0;
  if (dst && dstsize > 0) {
    size_t n = srclen < dstsize - 1 ? srclen : dstsize - 1;
    if (src) memcpy(dst, src, n);
    dst[n] = '\0';
  }
  return srclen;
}

void* xar_open(const char* file, int32_t flags) {
  (void)file;
  (void)flags;
  return NULL;
}

int xar_close(void* x) {
  (void)x;
  return 0;
}

void* xar_signature_first(void* x) {
  (void)x;
  return NULL;
}

void* xar_signature_next(void* s) {
  (void)s;
  return NULL;
}

const char* xar_signature_type(void* s) {
  (void)s;
  return "RSA";
}

int32_t xar_signature_get_x509certificate_count(void* s) {
  (void)s;
  return 0;
}

int32_t xar_signature_get_x509certificate_data(void* s, int32_t idx,
                                               const uint8_t** cert_data,
                                               uint32_t* cert_len) {
  (void)s;
  (void)idx;
  if (cert_data) *cert_data = NULL;
  if (cert_len) *cert_len = 0;
  return -1;
}

int32_t xar_signature_copy_signed_data(void* s, uint8_t** data, uint32_t* len,
                                       uint8_t** signed_data,
                                       uint32_t* signed_len, uint64_t* offset) {
  (void)s;
  if (data) *data = NULL;
  if (len) *len = 0;
  if (signed_data) *signed_data = NULL;
  if (signed_len) *signed_len = 0;
  if (offset) *offset = 0;
  return -1;
}


