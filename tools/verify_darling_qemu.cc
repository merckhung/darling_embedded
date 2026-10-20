// SPDX-License-Identifier: GPL-3.0-or-later
// C++20 Automated QEMU ARM64 Boot, CLI, and GUI Verification Harness for
// Darling Embedded (XNU/Darwin 25.5.0 + Darling Mach-O Userland + Mac OS X Apps).

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <regex>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

volatile sig_atomic_t g_shutdown_requested = 0;
void SigHandler(int) {
  g_shutdown_requested = 1;
}

uint64_t ParseJsonUint64(const std::string& json, const std::string& key) {
  std::regex re("\"" + key + "\"\\s*:\\s*([0-9]+)");
  std::smatch m;
  if (std::regex_search(json, m, re)) {
    return std::stoull(m[1].str());
  }
  return 0;
}

class QmpClient {
 public:
  QmpClient() : fd_(-1) {}
  ~QmpClient() { Close(); }

  bool Connect(const fs::path& sock_path, int timeout_ms = 30000) {
    auto start = std::chrono::steady_clock::now();
    while (true) {
      fd_ = socket(AF_UNIX, SOCK_STREAM, 0);
      if (fd_ < 0) return false;
      struct sockaddr_un addr;
      std::memset(&addr, 0, sizeof(addr));
      addr.sun_family = AF_UNIX;
      std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s",
                    sock_path.c_str());
      if (connect(fd_, reinterpret_cast<struct sockaddr*>(&addr),
                  sizeof(addr)) == 0) {
        break;
      }
      close(fd_);
      fd_ = -1;
      auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                         std::chrono::steady_clock::now() - start)
                         .count();
      if (elapsed >= timeout_ms) return false;
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    std::string greeting = ReadLine();
    if (greeting.find("QMP") == std::string::npos) return false;
    return Execute("{\"execute\":\"qmp_capabilities\"}");
  }

  bool Execute(const std::string& json_cmd) {
    if (fd_ < 0) return false;
    std::string payload = json_cmd + "\n";
    ssize_t w = write(fd_, payload.data(), payload.size());
    if (w != static_cast<ssize_t>(payload.size())) return false;
    while (true) {
      std::string line = ReadLine();
      if (line.empty()) return false;
      if (line.find("\"return\"") != std::string::npos) return true;
      if (line.find("\"error\"") != std::string::npos) return false;
    }
  }

  bool Screendump(const fs::path& ppm_path) {
    std::ostringstream oss;
    oss << "{\"execute\":\"screendump\",\"arguments\":{\"filename\":\""
        << ppm_path.string() << "\"}}";
    return Execute(oss.str());
  }

  bool MoveMouseRelative(int dx, int dy) {
    while (dx != 0 || dy != 0) {
      int step_x = std::max(-40, std::min(40, dx));
      int step_y = std::max(-40, std::min(40, dy));
      std::ostringstream oss;
      oss << "{\"execute\":\"input-send-event\",\"arguments\":{\"events\":["
          << "{\"type\":\"rel\",\"data\":{\"axis\":\"x\",\"value\":" << step_x
          << "}},"
          << "{\"type\":\"rel\",\"data\":{\"axis\":\"y\",\"value\":" << step_y
          << "}}"
          << "]}}";
      if (!Execute(oss.str())) return false;
      dx -= step_x;
      dy -= step_y;
      std::this_thread::sleep_for(std::chrono::milliseconds(25));
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(80));
    return true;
  }

  bool ClickLeftButton() {
    if (!Execute(
            "{\"execute\":\"input-send-event\",\"arguments\":{\"events\":["
            "{\"type\":\"btn\",\"data\":{\"down\":true,\"button\":\"left\"}}"
            "]}}")) {
      return false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(60));
    if (!Execute(
            "{\"execute\":\"input-send-event\",\"arguments\":{\"events\":["
            "{\"type\":\"btn\",\"data\":{\"down\":false,\"button\":\"left\"}}"
            "]}}")) {
      return false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    return true;
  }

  // Presses and releases a key chord given as QEMU qcodes, e.g. {"meta_l", "q"}.
  bool SendKeyChord(const std::vector<std::string>& qcodes) {
    for (int down = 1; down >= 0; --down) {
      for (size_t k = 0; k < qcodes.size(); ++k) {
        const std::string& q = down ? qcodes[k] : qcodes[qcodes.size() - 1 - k];
        std::ostringstream oss;
        oss << "{\"execute\":\"input-send-event\",\"arguments\":{\"events\":["
            << "{\"type\":\"key\",\"data\":{\"down\":" << (down ? "true" : "false")
            << ",\"key\":{\"type\":\"qcode\",\"data\":\"" << q << "\"}}}]}}";
        if (!Execute(oss.str())) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(60));
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    return true;
  }

  void Close() {
    if (fd_ >= 0) {
      close(fd_);
      fd_ = -1;
    }
  }

 private:
  std::string ReadLine() {
    std::string line;
    char c = 0;
    while (read(fd_, &c, 1) == 1) {
      if (c == '\n') break;
      line.push_back(c);
    }
    return line;
  }

  int fd_;
};

bool ConvertPpmToPng(const fs::path& ppm_path, const fs::path& png_path) {
  fs::create_directories(png_path.parent_path());
  std::ostringstream cmd;
  cmd << "pnmtopng '" << ppm_path.string() << "' > '" << png_path.string()
      << "' 2>/dev/null || convert '" << ppm_path.string() << "' '"
      << png_path.string() << "' 2>/dev/null";
  int ret = std::system(cmd.str().c_str());
  if (ret != 0 || !fs::exists(png_path)) {
    std::cerr << "ConvertPpmToPng failed for " << ppm_path << " -> " << png_path
              << " (cmd status " << ret << ")\n";
    return false;
  }
  return true;
}

bool ValidatePpmScanout(const fs::path& ppm_path, int expected_w,
                        int expected_h) {
  std::ifstream in(ppm_path, std::ios::binary);
  if (!in) {
    return false;
  }
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(in)),
                            std::istreambuf_iterator<char>());
  if (data.size() < 16) return false;

  size_t idx = 0;
  if (data[0] != 'P' || data[1] != '6') return false;
  idx = 2;

  auto skip_ws_comments = [&]() {
    while (idx < data.size()) {
      if (data[idx] == '#') {
        while (idx < data.size() && data[idx] != '\n') idx++;
        if (idx < data.size() && data[idx] == '\n') idx++;
      } else if (data[idx] == ' ' || data[idx] == '\t' || data[idx] == '\r' ||
                 data[idx] == '\n') {
        idx++;
      } else {
        break;
      }
    }
  };

  auto read_num = [&]() -> int {
    skip_ws_comments();
    if (idx >= data.size() || data[idx] < '0' || data[idx] > '9') return -1;
    int val = 0;
    while (idx < data.size() && data[idx] >= '0' && data[idx] <= '9') {
      val = val * 10 + (data[idx] - '0');
      idx++;
    }
    return val;
  };

  int w = read_num();
  int h = read_num();
  int maxval = read_num();
  if (w != expected_w || h != expected_h || maxval != 255) {
    return false;
  }

  if (idx < data.size() &&
      (data[idx] == ' ' || data[idx] == '\t' || data[idx] == '\r' ||
       data[idx] == '\n')) {
    idx++;
  } else {
    return false;
  }

  size_t pixel_bytes = data.size() - idx;
  size_t expected_bytes = static_cast<size_t>(w * h * 3);
  if (pixel_bytes < expected_bytes) {
    return false;
  }

  const uint8_t* pixels = data.data() + idx;
  size_t non_black = 0;
  for (size_t i = 0; i < expected_bytes; i += 3) {
    uint8_t r = pixels[i];
    uint8_t g = pixels[i + 1];
    uint8_t b = pixels[i + 2];
    if (r > 20 || g > 20 || b > 20) {
      non_black++;
    }
  }

  return non_black > static_cast<size_t>(w * h / 4);
}

}  // namespace

int main(int argc, char** argv) {
  fs::path loader_bin;
  fs::path kernel_bin;
  fs::path layout_json;
  fs::path root_img;
  fs::path screenshots_dir;
  std::string display_mode = "none";
  bool interactive = false;
  bool quick_desktop = false;
  bool baseline_only = false;

  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    auto next_val = [&]() -> std::string {
      return (i + 1 < argc) ? argv[++i] : "";
    };
    if (arg == "--loader") {
      loader_bin = next_val();
    } else if (arg == "--kernel") {
      kernel_bin = next_val();
    } else if (arg == "--layout") {
      layout_json = next_val();
    } else if (arg == "--root") {
      root_img = next_val();
    } else if (arg == "--screenshots-dir") {
      screenshots_dir = next_val();
    } else if (arg == "--display") {
      display_mode = next_val();
    } else if (arg == "--baseline-only") {
      baseline_only = true;
    } else if (arg == "--quick-desktop") {
      quick_desktop = true;
    } else if (arg == "--interactive" || arg == "--gui") {
      interactive = true;
      if (display_mode == "none") {
        display_mode = "gtk";
      }
    }
  }

  signal(SIGINT, SigHandler);
  signal(SIGTERM, SigHandler);

  if (screenshots_dir.empty()) {
    const char* ws = std::getenv("BUILD_WORKSPACE_DIRECTORY");
    if (ws && ws[0]) {
      screenshots_dir = fs::path(ws) / "docs/screenshots";
    } else {
      screenshots_dir = fs::current_path() / "docs/screenshots";
    }
  }
  fs::create_directories(screenshots_dir);

  std::ifstream layout_in(layout_json);
  std::string layout_str((std::istreambuf_iterator<char>(layout_in)),
                         std::istreambuf_iterator<char>());
  uint64_t phys_base = ParseJsonUint64(layout_str, "physical_base");
  if (phys_base == 0) {
    std::cerr << "Failed to parse physical_base from " << layout_json << "\n";
    return 1;
  }

  char tmp_template[] = "/tmp/darling-qemu-XXXXXX";
  char* tmp_dir_cstr = mkdtemp(tmp_template);
  if (!tmp_dir_cstr) return 1;
  fs::path work_dir(tmp_dir_cstr);
  fs::path seed_file = work_dir / "entropy.bin";
  fs::path hosttime_file = work_dir / "hosttime.bin";
  fs::path qmp_sock = work_dir / "qmp.sock";

  {
    std::ofstream seed_out(seed_file, std::ios::binary);
    uint8_t seed_bytes[256];
    for (int i = 0; i < 256; ++i) seed_bytes[i] = static_cast<uint8_t>(i * 37);
    seed_out.write(reinterpret_cast<const char*>(seed_bytes), 256);
  }
  {
    std::ofstream ht_out(hosttime_file, std::ios::binary);
    const char magic[8] = {'H', 'O', 'S', 'T', 'T', 'I', 'M', 'E'};
    uint64_t now_sec = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now().time_since_epoch())
            .count());
    ht_out.write(magic, 8);
    ht_out.write(reinterpret_cast<const char*>(&now_sec), sizeof(now_sec));
  }

  char phys_hex[32];
  std::snprintf(phys_hex, sizeof(phys_hex), "0x%llx",
                static_cast<unsigned long long>(phys_base));

  int stdin_pipe[2];
  int stdout_pipe[2];
  if (pipe(stdin_pipe) != 0 || pipe(stdout_pipe) != 0) {
    return 1;
  }

  pid_t qemu_pid = fork();
  if (qemu_pid < 0) return 1;
  if (qemu_pid == 0) {
    dup2(stdin_pipe[0], STDIN_FILENO);
    dup2(stdout_pipe[1], STDOUT_FILENO);
    dup2(stdout_pipe[1], STDERR_FILENO);
    close(stdin_pipe[0]);
    close(stdin_pipe[1]);
    close(stdout_pipe[0]);
    close(stdout_pipe[1]);

    std::string loader0 =
        "loader,file=" + loader_bin.string() + ",addr=0x40080000,cpu-num=0";
    std::string loader_kern =
        "loader,file=" + kernel_bin.string() + ",addr=" + phys_hex;
    std::string loader_seed =
        "loader,file=" + seed_file.string() + ",addr=0x07f00000";
    std::string loader_hosttime =
        "loader,file=" + hosttime_file.string() + ",addr=0x07f00800";
    std::string loader_root =
        "loader,file=" + root_img.string() + ",addr=0x0a000000";
    std::string qmp_arg =
        "unix:" + qmp_sock.string() + ",server=on,wait=off";

    std::vector<const char*> args = {
        "qemu-system-aarch64",
        "-M",
        "raspi4b",
        "-cpu",
        "cortex-a72",
        "-m",
        "2G",
        "-device",
        loader0.c_str(),
        "-global",
        "bcm2835-fb.xres=1024",
        "-global",
        "bcm2835-fb.yres=768",
        "-global",
        "bcm2835-fb.bpp=32",
        "-global",
        "bcm2835-fb.pixo=0",
        "-device",
        "loader,addr=0x40070000,data=0x17ffffffd503207f,data-len=8",
        "-device",
        "loader,addr=0x40070000,cpu-num=1",
        "-device",
        "loader,addr=0x40070000,cpu-num=2",
        "-device",
        "loader,addr=0x40070000,cpu-num=3",
        "-device",
        loader_kern.c_str(),
        "-device",
        loader_seed.c_str(),
        "-device",
        loader_hosttime.c_str(),
        "-device",
        loader_root.c_str(),
        "-device",
        "usb-hub,id=native-hub",
        "-device",
        "usb-kbd,port=1.1",
        "-device",
        "usb-mouse,port=1.2",
        "-device",
        "usb-net,netdev=n0,port=1.3",
        "-netdev",
        "user,id=n0",
        "-name",
        "Darling Embedded ARM64",
        "-serial",
        "stdio",
        "-monitor",
        "none",
        "-display",
        display_mode.c_str(),
        "-no-reboot",
        "-qmp",
        qmp_arg.c_str(),
        nullptr,
    };
    execvp(args[0], const_cast<char* const*>(args.data()));
    _exit(127);
  }

  close(stdin_pipe[0]);
  close(stdout_pipe[1]);
  int to_guest = stdin_pipe[1];
  int from_guest = stdout_pipe[0];
  fcntl(from_guest, F_SETFL, O_NONBLOCK);

  auto cleanup = [&]() {
    close(to_guest);
    close(from_guest);
    kill(qemu_pid, SIGTERM);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    kill(qemu_pid, SIGKILL);
    int st = 0;
    waitpid(qemu_pid, &st, 0);
    fs::remove_all(work_dir);
  };

  QmpClient qmp;
  if (!qmp.Connect(qmp_sock, 30000)) {
    std::cerr << "Failed to connect to QEMU QMP socket\n";
    cleanup();
    return 1;
  }

  std::string serial_accum;
  std::string line_buf;
  std::map<std::string, std::pair<int, int>> button_coords;
  // Desktop shell layout: "menubar::<title>", "dock::<name>", "menu::<title>".
  std::map<std::string, std::pair<int, int>> shell_coords;
  bool shell_ready = false;
  int ptr_x = 512, ptr_y = 384;
  bool kernel_seen = false;
  bool shell_prompt_seen = false;
  bool desktop_session_ready = false;
  bool fastdmg_win_ready = false;
  bool fastdmg_nib_loaded = false;

  auto pump_serial = [&](int wait_ms) {
    struct pollfd pfd = {from_guest, POLLIN, 0};
    int r = poll(&pfd, 1, wait_ms);
    if (r > 0 && (pfd.revents & POLLIN)) {
      char buf[1024];
      ssize_t n = 0;
      while ((n = read(from_guest, buf, sizeof(buf))) > 0) {
        std::cout.write(buf, n);
        std::cout.flush();
        serial_accum.append(buf, static_cast<size_t>(n));
        line_buf.append(buf, static_cast<size_t>(n));
        size_t pos = 0;
        while ((pos = line_buf.find('\n')) != std::string::npos) {
          std::string line = line_buf.substr(0, pos);
          if (!line.empty() && line.back() == '\r') line.pop_back();
          line_buf.erase(0, pos + 1);

          if (line.find("Darwin Kernel Version 25.5.0") != std::string::npos) {
            kernel_seen = true;
          }
          if (line.find("DARLING_DESKTOP_SESSION_READY:") !=
              std::string::npos) {
            desktop_session_ready = true;
            std::regex ptr_re("ptr=([0-9]+):([0-9]+)");
            std::smatch m;
            if (std::regex_search(line, m, ptr_re)) {
              ptr_x = std::stoi(m[1].str());
              ptr_y = std::stoi(m[2].str());
            }
          }
          if (line.find("DARLING_WINDOW_READY:FastDMG:") != std::string::npos) {
            fastdmg_win_ready = true;
          }
          if (line.find("[AppKit] loaded nib") != std::string::npos &&
              line.find("FastDMG.app") != std::string::npos &&
              line.find("MainWindow.nib") != std::string::npos) {
            fastdmg_nib_loaded = true;
          }
          if (line.find("DARLING_SHELL_READY:") != std::string::npos) {
            shell_ready = true;
          }
          static const std::pair<const char*, const char*> kShellPrefixes[] = {
              {"DARLING_MENUBAR_ITEM:", "menubar"},
              {"DARLING_DOCK_ITEM:", "dock"},
              {"DARLING_MENU_ITEM:", "menu"}};
          for (const auto& [prefix, kind] : kShellPrefixes) {
            size_t at = line.find(prefix);
            if (at == std::string::npos) continue;
            // <prefix><title>:<x>:<y>; titles may contain ':'.
            std::string rest = line.substr(at + std::strlen(prefix));
            size_t c2 = rest.rfind(':');
            if (c2 == std::string::npos || c2 == 0) continue;
            size_t c1 = rest.rfind(':', c2 - 1);
            if (c1 == std::string::npos) continue;
            try {
              shell_coords[std::string(kind) + "::" + rest.substr(0, c1)] = {
                  std::stoi(rest.substr(c1 + 1, c2 - c1 - 1)), std::stoi(rest.substr(c2 + 1))};
            } catch (...) {
            }
          }
          if (line.rfind("DARLING_BUTTON_POS:", 0) == 0) {
            // DARLING_BUTTON_POS:<WinTitle>:<BtnTitle>:<rx>:<ry>
            std::vector<std::string> parts;
            std::stringstream ss(line);
            std::string item;
            while (std::getline(ss, item, ':')) parts.push_back(item);
            if (parts.size() >= 5) {
              std::string key = parts[1] + "::" + parts[2];
              int bx = std::stoi(parts[3]);
              int by = std::stoi(parts[4]);
              button_coords[key] = {bx, by};
            }
          }
        }
        if (serial_accum.find("root@Darwin# ") != std::string::npos) {
          shell_prompt_seen = true;
        }
      }
    }
  };

  auto wait_until = [&](auto predicate, int timeout_sec,
                        const char* desc) -> bool {
    auto start = std::chrono::steady_clock::now();
    while (!predicate()) {
      if (g_shutdown_requested) {
        return false;
      }
      int st = 0;
      if (waitpid(qemu_pid, &st, WNOHANG) == qemu_pid) {
        if (interactive) {
          std::cout << "\n[QEMU window closed by user]\n";
          return false;
        }
        std::cerr << "\n[VERIFY FAIL] QEMU exited prematurely during: " << desc
                  << "\n";
        return false;
      }
      pump_serial(100);
      auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
                         std::chrono::steady_clock::now() - start)
                         .count();
      if (elapsed >= timeout_sec) {
        std::cerr << "\n[VERIFY FAIL] Timed out waiting for: " << desc << "\n";
        return false;
      }
    }
    return true;
  };

  if (!wait_until(
          [&]() {
            return kernel_seen && shell_prompt_seen && desktop_session_ready;
          },
          120, "XNU kernel boot + Xorg/Xfce desktop session")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 20; ++i) pump_serial(100);

  // 1. Darling CLI over the serial console.
  std::string cli_cmds =
      "/usr/bin/sw_vers && /usr/bin/darling --version && "
      "/usr/bin/darling run /usr/bin/hello_macosx --cli\n";
  write(to_guest, cli_cmds.data(), cli_cmds.size());
  if (!wait_until(
          [&]() {
            return serial_accum.find("ProductName:") != std::string::npos &&
                   serial_accum.find("Darling Embedded 0.1.0") != std::string::npos &&
                   serial_accum.find("DARLING_HELLO_CLI_OK:") != std::string::npos;
          },
          60, "sw_vers + darling --version + hello_macosx --cli")) {
    cleanup();
    return 1;
  }
  std::cout << "\n[VERIFY PASS] Darling CLI tools\n";

  auto capture_screenshot_with_retry =
      [&](const fs::path& ppm_path, const fs::path& png_path,
          int timeout_sec) -> bool {
    auto settle_until = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (std::chrono::steady_clock::now() < settle_until) pump_serial(100);
    auto start = std::chrono::steady_clock::now();
    while (true) {
      if (qmp.Screendump(ppm_path) && ValidatePpmScanout(ppm_path, 1024, 768) &&
          ConvertPpmToPng(ppm_path, png_path)) {
        return true;
      }
      auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
                         std::chrono::steady_clock::now() - start)
                         .count();
      if (elapsed >= timeout_sec) {
        ConvertPpmToPng(ppm_path, png_path);
        return false;
      }
      pump_serial(300);
    }
  };

  auto click_button = [&](const std::string& win_title,
                          const std::string& btn_title) -> bool {
    std::string key = win_title + "::" + btn_title;
    auto it = button_coords.find(key);
    if (it == button_coords.end()) {
      std::cerr << "[VERIFY FAIL] Unknown button coordinates for " << key << "\n";
      return false;
    }
    int dx = it->second.first - ptr_x;
    int dy = it->second.second - ptr_y;
    if (!qmp.MoveMouseRelative(dx, dy)) return false;
    ptr_x = it->second.first;
    ptr_y = it->second.second;
    return qmp.ClickLeftButton();
  };

  auto click_at = [&](int x, int y) -> bool {
    if (!qmp.MoveMouseRelative(x - ptr_x, y - ptr_y)) return false;
    ptr_x = x;
    ptr_y = y;
    return qmp.ClickLeftButton();
  };
  auto click_shell = [&](const std::string& key) -> bool {
    auto it = shell_coords.find(key);
    if (it == shell_coords.end()) {
      std::cerr << "[VERIFY FAIL] Unknown desktop shell item " << key << "\n";
      return false;
    }
    return click_at(it->second.first, it->second.second);
  };
  auto window_origin = [&](const std::string& marker, size_t from, int* x, int* y) -> bool {
    size_t at = serial_accum.find(marker, from);
    if (at == std::string::npos) return false;
    std::smatch m;
    std::string tail = serial_accum.substr(at + marker.size(), 64);
    if (!std::regex_search(tail, m, std::regex("^(-?[0-9]+):(-?[0-9]+)"))) return false;
    *x = std::stoi(m[1].str());
    *y = std::stoi(m[2].str());
    return true;
  };

  // 1b. Mac OS X desktop shell: menu bar, Dock, Apple menu, About This Mac,
  //     Finder and the global menu of a Cocoa application.
  std::cout << "\n--- Desktop shell (menu bar, Dock, Finder) ---\n";
  if (!wait_until([&]() { return shell_ready; }, 90, "desktop shell (menu bar + Dock)")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 30; ++i) pump_serial(100);
  capture_screenshot_with_retry(work_dir / "desktop.ppm", screenshots_dir / "darling_desktop.png",
                                20);
  std::cout << "[VERIFY PASS] Desktop with menu bar and Dock\n";

  size_t apple_start = serial_accum.size();
  if (!click_shell("menubar::Apple") ||
      !wait_until([&]() { return shell_coords.count("menu::About This Mac") > 0; }, 20,
                  "Apple menu")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 8; ++i) pump_serial(50);
  capture_screenshot_with_retry(work_dir / "apple_menu.ppm",
                                screenshots_dir / "darling_apple_menu.png", 15);
  if (!click_shell("menu::About This Mac") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_ABOUT_MAC_WINDOW:", apple_start) !=
                   std::string::npos;
          },
          20, "About This Mac window")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 15; ++i) pump_serial(50);
  capture_screenshot_with_retry(work_dir / "about_mac.ppm",
                                screenshots_dir / "darling_about_this_mac.png", 15);
  std::cout << "[VERIFY PASS] Apple menu -> About This Mac\n";
  int wx = 0, wy = 0;
  if (window_origin("DARLING_ABOUT_MAC_WINDOW:", apple_start, &wx, &wy)) {
    click_at(wx + 20, wy + 16);  // red close button
  }

  size_t finder_start = serial_accum.size();
  if (!click_shell("dock::Finder") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_FINDER_WINDOW:", finder_start) !=
                   std::string::npos;
          },
          20, "Finder window from the Dock")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 20; ++i) pump_serial(50);
  capture_screenshot_with_retry(work_dir / "finder.ppm", screenshots_dir / "darling_finder.png",
                                15);
  std::cout << "[VERIFY PASS] Finder Applications window\n";
  if (window_origin("DARLING_FINDER_WINDOW:", finder_start, &wx, &wy)) {
    click_at(wx + 20, wy + 20);
  }

  // A Cocoa application launched from the Dock publishes its menus to the
  // global menu bar; its application menu offers the standard About panel,
  // and Command-Q quits it.
  size_t dockapp_start = serial_accum.size();
  if (!click_shell("dock::FastDMG") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_WINDOW_READY:FastDMG:", dockapp_start) !=
                       std::string::npos &&
                   shell_coords.count("menubar::FastDMG") > 0;
          },
          60, "FastDMG launched from the Dock with its menus in the menu bar")) {
    capture_screenshot_with_retry(work_dir / "dock_fail.ppm",
                                  screenshots_dir / "darling_app_menu.png", 10);
    cleanup();
    return 1;
  }
  for (int i = 0; i < 30; ++i) pump_serial(100);
  shell_coords.erase("menu::Quit FastDMG");
  if (!click_shell("menubar::FastDMG") ||
      !wait_until([&]() { return shell_coords.count("menu::Quit FastDMG") > 0; }, 20,
                  "FastDMG application menu (from its MainMenu.nib)")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 8; ++i) pump_serial(50);
  capture_screenshot_with_retry(work_dir / "app_menu.ppm",
                                screenshots_dir / "darling_app_menu.png", 15);
  std::cout << "[VERIFY PASS] Global menu bar shows FastDMG's own menus\n";
  click_shell("menubar::FastDMG");  // close the menu again
  for (int i = 0; i < 5; ++i) pump_serial(50);
  size_t quit_start = serial_accum.size();
  qmp.SendKeyChord({"meta_l", "q"});
  if (!wait_until(
          [&]() {
            return serial_accum.find("DARLING_APP_TERMINATE", quit_start) != std::string::npos;
          },
          20, "Command-Q quits FastDMG")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] Command-Q terminated FastDMG\n";
  for (int i = 0; i < 20; ++i) pump_serial(100);

  // WidgetGallery has no MainMenu.nib: AppKit supplies the standard
  // application menu, whose About item opens the standard About panel.
  size_t wg_dock_start = serial_accum.size();
  shell_coords.erase("menubar::WidgetGallery");
  if (!click_shell("dock::WidgetGallery") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_WINDOW_READY:", wg_dock_start) != std::string::npos &&
                   shell_coords.count("menubar::WidgetGallery") > 0;
          },
          60, "WidgetGallery launched from the Dock")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 20; ++i) pump_serial(100);
  shell_coords.erase("menu::About WidgetGallery");
  if (!click_shell("menubar::WidgetGallery") ||
      !wait_until([&]() { return shell_coords.count("menu::About WidgetGallery") > 0; }, 20,
                  "WidgetGallery application menu")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 5; ++i) pump_serial(50);
  size_t about_app_start = serial_accum.size();
  if (!click_shell("menu::About WidgetGallery") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_WINDOW_READY:About WidgetGallery:",
                                     about_app_start) != std::string::npos;
          },
          20, "standard About panel")) {
    cleanup();
    return 1;
  }
  // The background window repaints itself as inactive; large windows take a
  // few seconds to redraw under emulation.
  for (int i = 0; i < 140; ++i) pump_serial(50);
  capture_screenshot_with_retry(work_dir / "about_app.ppm",
                                screenshots_dir / "darling_about_app.png", 15);
  std::cout << "[VERIFY PASS] Application menu -> standard About panel\n";
  quit_start = serial_accum.size();
  qmp.SendKeyChord({"meta_l", "q"});
  if (!wait_until(
          [&]() {
            return serial_accum.find("DARLING_APP_TERMINATE", quit_start) != std::string::npos;
          },
          20, "Command-Q quits WidgetGallery")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] Command-Q terminated the application\n";
  for (int i = 0; i < 20; ++i) pump_serial(100);
  if (quick_desktop) {
    std::cout << "\nPASS: desktop shell checks (--quick-desktop)\n";
    cleanup();
    return 0;
  }

  // 2. FastDMG.app: unmodified third-party ARM64 binary. Its window must come
  //    from its own MainWindow.nib (decoded by AppKit's NIBArchive loader).
  std::cout << "\n--- FastDMG.app (vendored, unmodified Xcode-built binary) ---\n";
  std::string open_fastdmg = "/usr/bin/open /Applications/FastDMG.app\n";
  // FastDMG already ran from the Dock above; wait for this new instance.
  fastdmg_nib_loaded = false;
  fastdmg_win_ready = false;
  write(to_guest, open_fastdmg.data(), open_fastdmg.size());
  if (!wait_until([&]() { return fastdmg_nib_loaded && fastdmg_win_ready; }, 60,
                  "FastDMG MainWindow.nib loaded and window mapped")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 20; ++i) pump_serial(50);
  fs::path ppm_fastdmg = work_dir / "darling_fastdmg.ppm";
  fs::path png_fastdmg = screenshots_dir / "darling_fastdmg.png";
  if (!capture_screenshot_with_retry(ppm_fastdmg, png_fastdmg, 30)) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] FastDMG window from its own nib: " << png_fastdmg
            << "\n";

  // The nib binds "Run in background" to NSUserDefaults (values.InBackground
  // or similar); toggling it must write the bound default.
  if (!click_button("FastDMG", "Run in background") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_DEFAULTS_SET:") != std::string::npos;
          },
          30, "FastDMG 'Run in background' checkbox bound to NSUserDefaults")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] FastDMG checkbox binding updated NSUserDefaults\n";
  for (int i = 0; i < 10; ++i) pump_serial(50);
  fs::path ppm_fastdmg2 = work_dir / "darling_fastdmg_toggled.ppm";
  fs::path png_fastdmg2 = screenshots_dir / "darling_fastdmg_toggled.png";
  capture_screenshot_with_retry(ppm_fastdmg2, png_fastdmg2, 15);

  // "Quit" is connected in the nib to First Responder's terminate:.
  size_t before_quit = serial_accum.size();
  if (!click_button("FastDMG", "Quit") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_APP_TERMINATE", before_quit) !=
                   std::string::npos;
          },
          30, "FastDMG 'Quit' -> terminate: via responder chain")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] FastDMG Quit button terminated the app\n";

  // 3. Platypus-format apps (unmodified ScriptExec runtime from Platypus
  //    5.5.0). "System Info" runs a shell script in a Text Window; when the
  //    script's output reaches EOF, ScriptExec retitles its Cancel button to
  //    "Quit" (cleanupInterface), which is observable as a button position.
  std::cout << "\n--- System Info.app (Platypus ScriptExec, Text Window) ---\n";
  size_t sysinfo_start = serial_accum.size();
  std::string open_sysinfo = "/usr/bin/open '/Applications/System Info.app'\n";
  write(to_guest, open_sysinfo.data(), open_sysinfo.size());
  if (!wait_until(
          [&]() {
            return serial_accum.find("DARLING_BUTTON_POS:System Info:Quit:", sysinfo_start) !=
                   std::string::npos;
          },
          90, "System Info script finished (Cancel button became Quit)")) {
    capture_screenshot_with_retry(work_dir / "si_fail.ppm",
                                  screenshots_dir / "darling_system_info.png", 10);
    cleanup();
    return 1;
  }
  for (int i = 0; i < 20; ++i) pump_serial(50);
  fs::path ppm_sysinfo = work_dir / "darling_system_info.ppm";
  fs::path png_sysinfo = screenshots_dir / "darling_system_info.png";
  capture_screenshot_with_retry(ppm_sysinfo, png_sysinfo, 20);
  std::cout << "[VERIFY PASS] System Info ran its script in ScriptExec: " << png_sysinfo
            << "\n";
  size_t before_si_quit = serial_accum.size();
  if (!click_button("System Info", "Quit") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_APP_TERMINATE", before_si_quit) !=
                   std::string::npos;
          },
          30, "System Info 'Quit' button")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] System Info Quit button terminated the app\n";

  //    "ProgressBar" is Platypus's own ProgressBar example: its script emits
  //    PROGRESS:n lines and finally QUITAPP, which makes ScriptExec terminate.
  std::cout << "\n--- ProgressBar.app (Platypus example, Progress Bar) ---\n";
  size_t pb_start = serial_accum.size();
  std::string open_pb = "/usr/bin/open /Applications/ProgressBar.app\n";
  write(to_guest, open_pb.data(), open_pb.size());
  if (!wait_until(
          [&]() {
            return serial_accum.find("DARLING_WINDOW_READY:ProgressBar:", pb_start) !=
                   std::string::npos;
          },
          60, "ProgressBar window")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 80; ++i) pump_serial(50);
  fs::path ppm_pb = work_dir / "darling_progressbar.ppm";
  fs::path png_pb = screenshots_dir / "darling_progressbar.png";
  capture_screenshot_with_retry(ppm_pb, png_pb, 20);
  if (!wait_until(
          [&]() {
            return serial_accum.find("DARLING_APP_TERMINATE", pb_start) != std::string::npos;
          },
          90, "ProgressBar script QUITAPP")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] ProgressBar showed progress and quit via QUITAPP: " << png_pb
            << "\n";

  // 4. WidgetGallery.app: in-tree showcase of implemented AppKit GUI widgets.
  std::cout << "\n--- WidgetGallery.app (Darling AppKit Widget Showcase) ---\n";
  size_t wg_start = serial_accum.size();
  std::string open_wg = "/usr/bin/open /Applications/WidgetGallery.app\n";
  write(to_guest, open_wg.data(), open_wg.size());
  const char* wg_title = "Mac OS X Widget Gallery - Darling AppKit";
  if (!wait_until(
          [&]() {
            return serial_accum.find(
                       std::string("DARLING_BUTTON_POS:") + wg_title + ":Quit:",
                       wg_start) != std::string::npos;
          },
          60, "WidgetGallery window and buttons")) {
    cleanup();
    return 1;
  }
  size_t before_step = serial_accum.size();
  if (!click_button(wg_title, "Step +15%") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_GALLERY_STEP:80", before_step) !=
                   std::string::npos;
          },
          30, "WidgetGallery 'Step +15%' button")) {
    cleanup();
    return 1;
  }
  for (int i = 0; i < 15; ++i) pump_serial(50);
  fs::path ppm_wg = work_dir / "darling_widget_gallery.ppm";
  fs::path png_wg = screenshots_dir / "darling_widget_gallery.png";
  capture_screenshot_with_retry(ppm_wg, png_wg, 20);
  std::cout << "[VERIFY PASS] WidgetGallery rendered and updated: " << png_wg
            << "\n";
  size_t before_wg_quit = serial_accum.size();
  if (!click_button(wg_title, "Quit") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_APP_TERMINATE", before_wg_quit) !=
                   std::string::npos;
          },
          30, "WidgetGallery 'Quit' button")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] WidgetGallery Quit button terminated the app\n";

  if (!baseline_only) {
  // 4b. ZoomUninstaller.app: unmodified third-party ARM64 Cocoa GUI app from
  //     zoom.us.app/Contents/Frameworks/ZoomUninstaller.app. Builds its window
  //     ("Zoom Workplace") programmatically using NSLayoutConstraint VFL and
  //     loads UTF-16LE Localizable.strings from Resources/en.lproj.
  std::cout << "\n--- ZoomUninstaller.app (vendored from zoom.us.app, unmodified ARM64 binary) ---\n";
  size_t zoom_start = serial_accum.size();
  std::string open_zoom =
      "ls -d /Applications/balenaEtcher.app /Applications/OBS.app "
      "/Applications/OBS-Intel.app /Applications/zoom.us.app "
      "/Applications/ZoomUninstaller.app && "
      "/usr/bin/open /Applications/ZoomUninstaller.app\n";
  write(to_guest, open_zoom.data(), open_zoom.size());
  if (!wait_until(
          [&]() {
            return serial_accum.find(
                       "DARLING_BUTTON_POS:Zoom Workplace:Cancel:",
                       zoom_start) != std::string::npos &&
                   serial_accum.find(
                       "DARLING_BUTTON_POS:Zoom Workplace:OK:",
                       zoom_start) != std::string::npos;
          },
          60, "ZoomUninstaller window, VFL layout, and localized Cancel/OK buttons")) {
    capture_screenshot_with_retry(
        work_dir / "zoom_fail.ppm",
        screenshots_dir / "darling_zoom_uninstaller.png", 10);
    cleanup();
    return 1;
  }
  for (int i = 0; i < 15; ++i) pump_serial(50);
  fs::path ppm_zoom = work_dir / "darling_zoom_uninstaller.ppm";
  fs::path png_zoom = screenshots_dir / "darling_zoom_uninstaller.png";
  if (!capture_screenshot_with_retry(ppm_zoom, png_zoom, 20)) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] ZoomUninstaller window rendered with localized strings: "
            << png_zoom << "\n";
  size_t before_zoom_cancel = serial_accum.size();
  if (!click_button("Zoom Workplace", "Cancel") ||
      !wait_until(
          [&]() {
            return serial_accum.find("DARLING_APP_TERMINATE", before_zoom_cancel) !=
                   std::string::npos;
          },
          30, "ZoomUninstaller 'Cancel' button -> cancelButtonAction: -> terminate:")) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] ZoomUninstaller Cancel button terminated the app\n";

  // 4c. Verify all 12 newly added Mac OS X ARM64/ARM64e apps from vendor/*
  //     and GG_APPS/*:
  struct ExtraGuiApp {
    const char* bundle_path;
    const char* slug;
    const char* desc;
  };
  const std::vector<ExtraGuiApp> extra_gui_apps = {
      {"/Applications/ZoomAutoUpdater.app", "zoom_autoupdater",
       "ZoomAutoUpdater.app (from zoom.us.app, ZMAUPureWindow)"},
      {"/Applications/SparkleUpdater.app", "sparkle_updater",
       "SparkleUpdater.app (from Codex.app, SUStatus.nib)"},
      {"/Applications/Stickies.app", "stickies",
       "Stickies.app (Mac OS X arm64e + StickiesDocument.nib)"},
      {"/Applications/Digital Color Meter.app", "digital_color_meter",
       "Digital Color Meter.app (Mac OS X arm64e + MainMenu.nib + CG Window Capture)"},
      {"/Applications/Image Capture.app", "image_capture",
       "Image Capture.app (Mac OS X arm64e + ICApplication.nib)"},
      {"/Applications/Folder Actions Setup.app", "folder_actions_setup",
       "Folder Actions Setup.app (Mac OS X arm64e + Main.storyboardc)"},
      {"/Applications/Ticket Viewer.app", "ticket_viewer",
       "Ticket Viewer.app (Mac OS X arm64e + MainMenu.nib)"},
      {"/Applications/Expansion Slot Utility.app", "expansion_slot_utility",
       "Expansion Slot Utility.app (Mac OS X arm64e + Main.storyboardc)"},
      {"/Applications/Install Command Line Developer Tools.app",
       "install_clt",
       "Install Command Line Developer Tools.app (Mac OS X arm64e + MainMenu.nib)"},
      {"/Applications/AppleScript Utility.app", "applescript_utility",
       "AppleScript Utility.app (Mac OS X arm64e + MainMenu.nib)"},
      {"/Applications/Bluetooth File Exchange.app", "bluetooth_file_exchange",
       "Bluetooth File Exchange.app (Mac OS X arm64e + FileTransferClientWindow.nib)"},
      {"/Applications/Directory Utility.app", "directory_utility",
       "Directory Utility.app (Mac OS X arm64e + MainMenu.nib)"},
  };
  for (const auto& app : extra_gui_apps) {
    std::cout << "\n--- " << app.desc << " ---\n";
    size_t app_start = serial_accum.size();
    std::string cmd = std::string("/usr/bin/darling open '") + app.bundle_path +
                      "' & APP_PID=$!\n";
    write(to_guest, cmd.data(), cmd.size());
    if (!wait_until(
            [&]() {
              return serial_accum.find("DARLING_WINDOW_READY:", app_start) !=
                     std::string::npos;
            },
            60, app.desc)) {
      capture_screenshot_with_retry(
          work_dir / (std::string("fail_") + app.slug + ".ppm"),
          screenshots_dir / (std::string("darling_") + app.slug + ".png"), 10);
      cleanup();
      return 1;
    }
    for (int i = 0; i < 15; ++i) pump_serial(50);
    fs::path ppm_app = work_dir / (std::string("darling_") + app.slug + ".ppm");
    fs::path png_app =
        screenshots_dir / (std::string("darling_") + app.slug + ".png");
    if (!capture_screenshot_with_retry(ppm_app, png_app, 20)) {
      cleanup();
      return 1;
    }
    std::cout << "[VERIFY PASS] " << app.desc << ": " << png_app << "\n";
    size_t kill_start = serial_accum.size();
    std::string kill_cmd =
        "kill -9 $APP_PID 2>/dev/null; wait $APP_PID 2>/dev/null; echo DARLING_KILLED_OK\n";
    write(to_guest, kill_cmd.data(), kill_cmd.size());
    wait_until(
        [&]() {
          return serial_accum.find("DARLING_KILLED_OK", kill_start) !=
                 std::string::npos;
        },
        15, "Terminate previous GUI app");
  }

  }  // Optional legacy bundles, excluded by --baseline-only.

  // 5. Chromium (headless_shell + ANGLE + SwiftShader WebGL) running side-by-side
  //    with Mac OS X FastDMG.app on the Xfce desktop.
  std::cout << "\n--- Chromium + FastDMG.app Side-by-Side ---\n";
  size_t ch_start = serial_accum.size();
  std::string launch_side_by_side =
      "/usr/bin/open /Applications/FastDMG.app; "
      "/bin/chromium file:///usr/share/chromium/test.html >/dev/console 2>&1 &\n";
  write(to_guest, launch_side_by_side.data(), launch_side_by_side.size());
  if (!wait_until(
          [&]() {
            return serial_accum.find("DARLING_WINDOW_READY:FastDMG:", ch_start) !=
                       std::string::npos &&
                   serial_accum.find("WEBGL_READY:ANGLE", ch_start) !=
                       std::string::npos;
          },
          180, "Chromium WebGL (ANGLE/SwiftShader) + FastDMG side-by-side")) {
    capture_screenshot_with_retry(
        work_dir / "chromium_fail.ppm",
        screenshots_dir / "darling_chromium_side_by_side.png", 10);
    cleanup();
    return 1;
  }
  // Give Chromium time to composite its first full frame.
  auto composite_until = std::chrono::steady_clock::now() + std::chrono::seconds(12);
  while (std::chrono::steady_clock::now() < composite_until) pump_serial(100);
  fs::path ppm_chromium = work_dir / "darling_chromium_side_by_side.ppm";
  fs::path png_chromium = screenshots_dir / "darling_chromium_side_by_side.png";
  if (!capture_screenshot_with_retry(ppm_chromium, png_chromium, 30)) {
    cleanup();
    return 1;
  }
  std::cout << "[VERIFY PASS] Chromium + FastDMG running side-by-side: "
            << png_chromium << "\n";

  fs::path ppm_final = work_dir / "darling_desktop_final.ppm";
  fs::path png_final = screenshots_dir / "darling_desktop_final.png";
  capture_screenshot_with_retry(ppm_final, png_final, 15);

  std::cout << "\n==========================================================\n"
            << "PASS: Darling Embedded ARM64 on XNU/Darwin 25.5.0\n"
            << "  - CLI:      sw_vers, darling --version, hello_macosx --cli\n"
            << "  - FastDMG:  window instantiated from its own MainWindow.nib;\n"
            << "              checkbox binding and Quit (terminate:) work\n"
            << "  - Platypus: ScriptExec runs System Info (Text Window) and\n"
            << "              ProgressBar (Progress Bar, QUITAPP)\n"
            << "  - Gallery:  WidgetGallery.app showcases AppKit GUI widgets\n"
            << (baseline_only ? "  - Legacy optional bundles: skipped (--baseline-only)\n" :
                "  - Legacy optional bundles: window checks passed\n")
            << "  - Chromium: Native Chromium + ANGLE/SwiftShader WebGL running\n"
            << "              side-by-side with Mac OS X apps\n"
            << "  - Screenshots: " << screenshots_dir << "\n"
            << "==========================================================\n";

  if (interactive && !g_shutdown_requested) {
    std::cout << "\nInteractive session: Chromium and FastDMG are open. Lines typed"
                 " here are sent to the guest shell (e.g. /usr/bin/open"
                 " /Applications/WidgetGallery.app). Close the QEMU window or press"
                 " Ctrl+C to exit.\n";
    std::cout.flush();
    fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
    while (!g_shutdown_requested) {
      int st = 0;
      if (waitpid(qemu_pid, &st, WNOHANG) == qemu_pid) break;
      char in_buf[256];
      ssize_t in_n = read(STDIN_FILENO, in_buf, sizeof(in_buf));
      if (in_n > 0 && write(to_guest, in_buf, static_cast<size_t>(in_n)) < 0) break;
      pump_serial(100);
    }
  }

  cleanup();
  return 0;
}
