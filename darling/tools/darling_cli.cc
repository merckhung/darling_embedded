// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded CLI Launcher (/usr/bin/darling) for XNU/Darwin ARM64.
// Inspired by darlinghq/darling src/startup/darling.c, adapted for native
// XNU/Darwin execution without Linux LKM/namespace translation.

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <unistd.h>

extern char** environ;

namespace {

bool FileExists(const char* path) {
  struct stat st;
  return path && stat(path, &st) == 0;
}

bool ExtractPlistString(const char* plist_path, const char* key, char* out,
                        size_t out_size) {
  if (!plist_path || !key || !out || out_size == 0) return false;
  out[0] = '\0';
  FILE* fp = fopen(plist_path, "rb");
  if (!fp) return false;
  fseek(fp, 0, SEEK_END);
  long fsz = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (fsz <= 0 || fsz > 1024 * 1024) {
    fclose(fp);
    return false;
  }
  char* buf = static_cast<char*>(malloc(static_cast<size_t>(fsz) + 1));
  if (!buf) {
    fclose(fp);
    return false;
  }
  size_t n = fread(buf, 1, static_cast<size_t>(fsz), fp);
  fclose(fp);
  buf[n] = '\0';

  char key_tag[128];
  snprintf(key_tag, sizeof(key_tag), "<key>%s</key>", key);
  const char* kpos = strstr(buf, key_tag);
  if (!kpos) {
    free(buf);
    return false;
  }
  const char* spos = strstr(kpos + strlen(key_tag), "<string>");
  if (!spos) {
    free(buf);
    return false;
  }
  spos += 8;
  const char* epos = strstr(spos, "</string>");
  if (!epos) {
    free(buf);
    return false;
  }
  size_t len = static_cast<size_t>(epos - spos);
  if (len >= out_size) len = out_size - 1;
  memcpy(out, spos, len);
  out[len] = '\0';
  free(buf);
  return true;
}

bool ResolveAppBundle(const char* input, char* bundle_dir, size_t bundle_size,
                      char* exec_path, size_t exec_size) {
  if (!input || !input[0]) return false;
  char candidate[512];
  if (strstr(input, ".app")) {
    if (input[0] == '/') {
      snprintf(candidate, sizeof(candidate), "%s", input);
    } else {
      snprintf(candidate, sizeof(candidate), "/Applications/%s", input);
      if (!FileExists(candidate)) {
        snprintf(candidate, sizeof(candidate), "%s", input);
      }
    }
  } else if (input[0] != '/') {
    snprintf(candidate, sizeof(candidate), "/Applications/%s.app", input);
  } else {
    return false;
  }

  char plist_path[640];
  snprintf(plist_path, sizeof(plist_path), "%s/Contents/Info.plist", candidate);
  if (!FileExists(plist_path)) return false;

  char exec_name[128] = {0};
  if (!ExtractPlistString(plist_path, "CFBundleExecutable", exec_name,
                          sizeof(exec_name))) {
    const char* slash = strrchr(candidate, '/');
    const char* base = slash ? slash + 1 : candidate;
    snprintf(exec_name, sizeof(exec_name), "%s", base);
    char* dot = strstr(exec_name, ".app");
    if (dot) *dot = '\0';
  }

  snprintf(bundle_dir, bundle_size, "%s", candidate);
  snprintf(exec_path, exec_size, "%s/Contents/MacOS/%s", candidate, exec_name);
  return FileExists(exec_path);
}

void SetupDarlingEnvironment(const char* bundle_dir) {
  setenv("DARLING_PREFIX", "/", 1);
  setenv("DARLING_NATIVE_XNU", "1", 1);
  if (!getenv("DISPLAY")) {
    setenv("DISPLAY", ":0", 1);
  }
  if (!getenv("PATH")) {
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1);
  }
  if (!getenv("HOME")) {
    setenv("HOME", "/var/root", 1);
  }
  if (bundle_dir && bundle_dir[0]) {
    setenv("DARLING_APP_BUNDLE", bundle_dir, 1);
  }
}

void PrintVersion() {
  struct utsname u;
  memset(&u, 0, sizeof(u));
  uname(&u);
  printf(
      "Darling Embedded 0.1.0 (darlinghq/darling Mach-O userland on native %s "
      "%s %s)\n",
      u.sysname[0] ? u.sysname : "Darwin", u.release[0] ? u.release : "25.5.0",
      u.machine[0] ? u.machine : "arm64");
}

void PrintStatus() {
  PrintVersion();
  int ncpu = 4;
  size_t len = sizeof(ncpu);
  sysctlbyname("hw.ncpu", &ncpu, &len, nullptr, 0);
  uint64_t mem = 0;
  len = sizeof(mem);
  sysctlbyname("hw.memsize", &mem, &len, nullptr, 0);
  printf("  Kernel:      XNU/Darwin 25.5.0 (ARM64 Cortex-A72)\n");
  printf("  Userland:    Darling Mach-O + Cocoa (Foundation / AppKit / X11)\n");
  printf("  CPUs:        %d\n", ncpu);
  printf("  Memory:      %llu MiB\n",
         static_cast<unsigned long long>(mem / (1024ULL * 1024ULL)));
  printf("  Prefix:      / (Native HFS+ Root)\n");
}

void PrintUsage() {
  printf(
      "Usage:\n"
      "  darling --version                  Show Darling Embedded version\n"
      "  darling status                     Show XNU + Darling runtime status\n"
      "  darling shell [command [args...]]  Run shell or command in Darling\n"
      "  darling open <App.app|AppName>     Launch a Mac OS X .app bundle\n"
      "  darling [run] <binary|App.app>     Execute a Mach-O binary or .app\n");
}

}  // namespace

extern "C" int main(int argc, char** argv) {
  if (argc < 2) {
    PrintUsage();
    return 0;
  }

  const char* cmd = argv[1];
  if (strcmp(cmd, "--version") == 0 || strcmp(cmd, "-v") == 0 ||
      strcmp(cmd, "version") == 0) {
    PrintVersion();
    return 0;
  }
  if (strcmp(cmd, "--help") == 0 || strcmp(cmd, "-h") == 0 ||
      strcmp(cmd, "help") == 0) {
    PrintUsage();
    return 0;
  }
  if (strcmp(cmd, "status") == 0 || strcmp(cmd, "info") == 0) {
    PrintStatus();
    return 0;
  }

  if (strcmp(cmd, "shell") == 0) {
    SetupDarlingEnvironment(nullptr);
    if (argc == 2) {
      char* sh_argv[] = {const_cast<char*>("/bin/sh"),
                         const_cast<char*>("-i"), nullptr};
      execve("/bin/sh", sh_argv, environ);
      perror("darling shell");
      return 127;
    }
    return main(argc - 1, argv + 1);
  }

  int arg_start = 1;
  if (strcmp(cmd, "run") == 0 || strcmp(cmd, "open") == 0) {
    if (argc < 3) {
      fprintf(stderr, "darling %s: missing target application or binary\n",
              cmd);
      return 1;
    }
    arg_start = 2;
  }

  const char* target = argv[arg_start];
  char bundle_dir[512] = {0};
  char exec_path[640] = {0};

  if (ResolveAppBundle(target, bundle_dir, sizeof(bundle_dir), exec_path,
                       sizeof(exec_path))) {
    SetupDarlingEnvironment(bundle_dir);
    printf("DARLING_LAUNCH_BUNDLE:%s:%s\n", bundle_dir, exec_path);
    fflush(stdout);
    char* new_argv[64];
    size_t idx = 0;
    new_argv[idx++] = exec_path;
    for (int i = arg_start + 1; i < argc && idx + 1 < 64; ++i) {
      if (strcmp(argv[i], "--args") == 0) continue;
      new_argv[idx++] = argv[i];
    }
    new_argv[idx] = nullptr;
    execve(exec_path, new_argv, environ);
    perror("darling execve .app");
    return 127;
  }

  SetupDarlingEnvironment(nullptr);
  if (target[0] == '/' && FileExists(target)) {
    snprintf(exec_path, sizeof(exec_path), "%s", target);
  } else {
    const char* search_dirs[] = {"/usr/bin", "/bin", "/sbin", "/usr/sbin"};
    bool found = false;
    for (const char* dir : search_dirs) {
      snprintf(exec_path, sizeof(exec_path), "%s/%s", dir, target);
      if (FileExists(exec_path)) {
        found = true;
        break;
      }
    }
    if (!found) {
      snprintf(exec_path, sizeof(exec_path), "%s", target);
    }
  }

  char* new_argv[64];
  size_t idx = 0;
  new_argv[idx++] = exec_path;
  for (int i = arg_start + 1; i < argc && idx + 1 < 64; ++i) {
    new_argv[idx++] = argv[i];
  }
  new_argv[idx] = nullptr;
  execve(exec_path, new_argv, environ);
  fprintf(stderr, "darling: failed to execute '%s': %s\n", exec_path,
          strerror(errno));
  return 127;
}
