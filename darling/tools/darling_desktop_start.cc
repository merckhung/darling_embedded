// SPDX-License-Identifier: GPL-3.0-or-later
// Darling Embedded Graphical Desktop & Mac OS X App Session Supervisor
// Starts Xorg (:0) and the Darling desktop shell
// (menu bar, Dock, Finder), and then waits; applications are started on
// demand via /usr/bin/open or the Dock.

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;


extern "C" int main(int argc, char** argv) {
  if (argc == 2 && strcmp(argv[1], "--session") == 0) {
    const char* address = getenv("DBUS_SESSION_BUS_ADDRESS");
    if (address && *address) {
      umask(022);
      FILE* fp = fopen("/var/run/xfce-session.bus", "w");
      if (fp) {
        fprintf(fp, "%s\n", address);
        fclose(fp);
      }
    }
    pid_t panel_pid = fork();
    if (panel_pid == 0) {
      execl("/System/Library/CoreServices/darling-shell", "darling-shell",
            static_cast<char*>(nullptr));
      _exit(127);
    }
    while (true) {
      int st = 0;
      pid_t p = waitpid(-1, &st, 0);
      if (p < 0 && errno != EINTR) break;
    }
    return 0;
  }

  setenv("DISPLAY", ":0", 1);
  setenv("XDG_CURRENT_DESKTOP", "XFCE", 1);
  setenv("XDG_SESSION_TYPE", "x11", 1);
  setenv("DESKTOP_SESSION", "xfce", 1);
  setenv("DARLING_PREFIX", "/", 1);
  setenv("HOME", "/var/root", 1);
  setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1);

  if (access("/sbin/netcfg", X_OK) == 0) {
    pid_t net_pid = fork();
    if (net_pid == 0) {
      execl("/sbin/netcfg", "netcfg", "up", "en0", "10.0.2.15/24", "10.0.2.2",
            "15", static_cast<char*>(nullptr));
      _exit(127);
    } else if (net_pid > 0) {
      int st = 0;
      waitpid(net_pid, &st, 0);
    }
  }

  pid_t xorg_pid = fork();
  if (xorg_pid < 0) {
    perror("darling-desktop-start: fork Xorg");
    return 1;
  }
  if (xorg_pid == 0) {
    execl("/usr/bin/Xorg", "Xorg", ":0", "-nolisten", "tcp", "-noreset",
          static_cast<char*>(nullptr));
    _exit(127);
  }

  Display* display = nullptr;
  for (int retry = 0; retry < 1200 && !display; ++retry) {
    int status = 0;
    if (waitpid(xorg_pid, &status, WNOHANG) == xorg_pid) {
      fprintf(stderr, "darling-desktop-start: Xorg exited early\n");
      return 1;
    }
    display = XOpenDisplay(":0");
    if (!display) usleep(50000);
  }
  if (!display) {
    fprintf(stderr, "darling-desktop-start: timed out waiting for Xorg :0\n");
    return 1;
  }

  // Set 1:1 unaccelerated pointer control for deterministic hardware input
  XChangePointerControl(display, True, True, 1, 1, 0);

  // Paint desktop background with standard Mac OS X Aqua blue (0x24588e)
  XSetWindowBackground(display, DefaultRootWindow(display), 0x24588e);
  XClearWindow(display, DefaultRootWindow(display));
  XFlush(display);

  // The Mac OS X desktop shell: wallpaper, global menu bar, Dock, Finder.
  // There is no separate window manager: AppKit windows draw their own
  // title bars and the shell keeps the menu bar and Dock on top.
  pid_t shell_pid = fork();
  if (shell_pid == 0) {
    execl("/System/Library/CoreServices/darling-shell", "darling-shell",
          static_cast<char*>(nullptr));
    _exit(127);
  }

  printf("DARLING_XFCE_DESKTOP_UP:xorg=%ld:shell=%ld\n",
         static_cast<long>(xorg_pid), static_cast<long>(shell_pid));
  fflush(stdout);

  // Applications are launched on demand (e.g. via /usr/bin/open); none are
  // auto-started by the session supervisor.
  int screen = DefaultScreen(display);
  Window root_ret = None, child_ret = None;
  int rx = 0, ry = 0, wx = 0, wy = 0;
  unsigned int mask = 0;
  XQueryPointer(display, RootWindow(display, screen), &root_ret, &child_ret,
                &rx, &ry, &wx, &wy, &mask);

  printf("DARLING_DESKTOP_SESSION_READY:ptr=%d:%d\n", rx, ry);
  fflush(stdout);

  XCloseDisplay(display);

  while (true) {
    int status = 0;
    pid_t exited = waitpid(-1, &status, 0);
    if (exited < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (exited == xorg_pid) break;
  }
  return 0;
}
