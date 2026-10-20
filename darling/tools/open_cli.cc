// SPDX-License-Identifier: GPL-3.0-or-later
// Mac OS X `open` utility (/usr/bin/open) for Darling Embedded on XNU/Darwin.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

extern "C" int main(int argc, char** argv) {
  if (argc < 2) {
    printf("Usage: open [-a AppName] [-W] <PathTo.app> [--args ...]\n");
    return 0;
  }

  bool wait_for_exit = false;
  const char* app_target = nullptr;
  int extra_start = argc;

  for (int i = 1; i < argc; ++i) {
    if (strcmp(argv[i], "-W") == 0 || strcmp(argv[i], "--wait-apps") == 0) {
      wait_for_exit = true;
    } else if (strcmp(argv[i], "-a") == 0 && i + 1 < argc) {
      app_target = argv[++i];
    } else if (strcmp(argv[i], "--args") == 0) {
      extra_start = i + 1;
      break;
    } else if (!app_target) {
      app_target = argv[i];
    }
  }

  if (!app_target) {
    fprintf(stderr, "open: no application specified\n");
    return 1;
  }
  // There is no LaunchServices URL-handler database in this environment, so
  // URLs are not mapped to an application. Use: open -a <App> --args <URL>.
  if (strstr(app_target, "://") != nullptr) {
    fprintf(stderr,
            "open: no URL handler registry; use 'open -a <App.app> --args %s'\n",
            app_target);
    return 1;
  }

  const char* fg_env = getenv("DARLING_OPEN_FOREGROUND");
  if (fg_env && strcmp(fg_env, "1") == 0) {
    wait_for_exit = true;
  }

  char* exec_argv[64];
  size_t idx = 0;
  exec_argv[idx++] = const_cast<char*>("/usr/bin/darling");
  exec_argv[idx++] = const_cast<char*>("open");
  exec_argv[idx++] = const_cast<char*>(app_target);
  for (int i = extra_start; i < argc && idx + 1 < 64; ++i) {
    exec_argv[idx++] = argv[i];
  }
  exec_argv[idx] = nullptr;

  if (wait_for_exit) {
    execve("/usr/bin/darling", exec_argv, environ);
    perror("open: execve /usr/bin/darling");
    return 127;
  }

  pid_t child = fork();
  if (child < 0) {
    perror("open: fork");
    return 1;
  }
  if (child == 0) {
    execve("/usr/bin/darling", exec_argv, environ);
    _exit(127);
  }
  return 0;
}
