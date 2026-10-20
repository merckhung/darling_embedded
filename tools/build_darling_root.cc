// SPDX-License-Identifier: GPL-3.0-or-later
// Host C++20 Builder for the Darling Embedded ARM64 HFS+ Root Image.
// Compiles libobjc.A.dylib, Foundation.framework, AppKit.framework, Darling
// CLI tools (/usr/bin/darling, /usr/bin/open, /usr/bin/sw_vers), and native
// the HelloWorld.app framework smoke test, installs the unmodified vendored
// FastDMG.app bundle, signs all Mach-O
// images, and injects them into the 128 MiB HFS+ graphical root image.

#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

int RunCommand(const std::vector<std::string>& args) {
  if (args.empty()) return 1;
  std::ostringstream cmd;
  for (size_t i = 0; i < args.size(); ++i) {
    if (i > 0) cmd << ' ';
    cmd << "'";
    for (char c : args[i]) {
      if (c == '\'') {
        cmd << "'\\''";
      } else {
        cmd << c;
      }
    }
    cmd << "'";
  }
  int status = std::system(cmd.str().c_str());
  if (status != 0) {
    std::cerr << "Command failed (" << status << "): " << cmd.str() << "\n";
    return 1;
  }
  return 0;
}

std::string CaptureCommand(const std::string& cmd) {
  FILE* pipe = popen(cmd.c_str(), "r");
  if (!pipe) return "";
  std::string out;
  char buf[512];
  while (fgets(buf, sizeof(buf), pipe)) {
    out += buf;
  }
  pclose(pipe);
  while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) {
    out.pop_back();
  }
  return out;
}

void WriteTextFile(const fs::path& path, const std::string& content) {
  fs::create_directories(path.parent_path());
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  out.write(content.data(), static_cast<std::streamsize>(content.size()));
}

}  // namespace

int main(int argc, char** argv) {
  fs::path base_root;
  fs::path sdk_tar;
  fs::path x11_headers_tar;
  fs::path hfs_tool;
  fs::path signer_tool;
  fs::path darling_sw_vers;
  fs::path workspace_root;
  fs::path output_img;
  fs::path dyld_bin;      // /usr/lib/dyld built from darling/dyld
  fs::path libunwind_dir; // LLVM libunwind sources (darwin_embedded copy)
  fs::path inter_font_dir; // Inter static TTFs (UI font)
  fs::path inter_license;

  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    auto next_val = [&]() -> std::string {
      return (i + 1 < argc) ? argv[++i] : "";
    };
    if (arg == "--base-root") {
      base_root = next_val();
    } else if (arg == "--sdk") {
      sdk_tar = next_val();
    } else if (arg == "--x11-headers") {
      x11_headers_tar = next_val();
    } else if (arg == "--hfs-tool") {
      hfs_tool = next_val();
    } else if (arg == "--signer") {
      signer_tool = next_val();
    } else if (arg == "--darling-sw-vers") {
      darling_sw_vers = next_val();
    } else if (arg == "--workspace-root") {
      workspace_root = next_val();
    } else if (arg == "--output") {
      output_img = next_val();
    } else if (arg == "--libunwind-dir") {
      libunwind_dir = next_val();
    } else if (arg == "--dyld") {
      dyld_bin = next_val();
    } else if (arg == "--inter-font-dir") {
      inter_font_dir = next_val();
    } else if (arg == "--inter-license") {
      inter_license = next_val();
    } else {
      std::cerr << "Unknown argument: " << arg << "\n";
      return 1;
    }
  }

  if (base_root.empty() || sdk_tar.empty() || x11_headers_tar.empty() ||
      hfs_tool.empty() || signer_tool.empty() || darling_sw_vers.empty() ||
      workspace_root.empty() || output_img.empty()) {
    std::cerr << "Missing required arguments to build_darling_root\n";
    return 1;
  }

  fs::create_directories(output_img.parent_path());
  fs::path work = output_img.parent_path() / ".darling_root_work";
  fs::remove_all(work);
  fs::create_directories(work);

  fs::path sdk_dir = work / "sdk";
  fs::path x11_dir = work / "x11_headers";
  fs::path rootfs_extract = work / "rootfs";
  fs::path build_dir = work / "build";
  fs::create_directories(sdk_dir);
  fs::create_directories(x11_dir);
  fs::create_directories(rootfs_extract);
  fs::create_directories(build_dir);

  if (RunCommand({"tar", "-xf", sdk_tar.string(), "-C", sdk_dir.string()}) !=
          0 ||
      RunCommand({"tar", "-xf", x11_headers_tar.string(), "-C",
                  x11_dir.string()}) != 0) {
    return 1;
  }

  fs::path img = work / "darling.img";
  fs::copy_file(base_root, img, fs::copy_options::overwrite_existing);
  fs::permissions(img, fs::perms::owner_read | fs::perms::owner_write,
                  fs::perm_options::add);

  // Extract existing rootfs libraries so ld64.lld can link against
  // libSystem.B.dylib, libX11.6.dylib, libcairo.2.dylib, etc.
  if (RunCommand({hfs_tool.string(), img.string(), "extractall", "/",
                  rootfs_extract.string()}) != 0) {
    return 1;
  }

  std::string clang_res = CaptureCommand("clang-20 -print-resource-dir");
  if (clang_res.empty()) {
    std::cerr << "Failed to query clang-20 resource dir\n";
    return 1;
  }

  fs::path darling_inc = workspace_root / "darling/include";
  std::vector<std::string> common_flags = {
      "--target=arm64-apple-macos26.5",
      "-O2",
      "-fPIC",
      "-ffreestanding",
      "-fno-builtin",
      "-fno-stack-protector",
      "-nostdinc",
      "-mcpu=cortex-a72",
      "-mno-outline-atomics",
      "-D_DARWIN_C_SOURCE=1",
      "-D_FORTIFY_SOURCE=0",
      "-Wall",
      "-Wextra",
      "-Werror",
      "-Wno-availability",
      "-Wno-deprecated-objc-isa-usage",
      "-Wno-cast-function-type-mismatch",
      "-I",
      darling_inc.string(),
      "-isystem",
      clang_res + "/include",
      "-isystem",
      (sdk_dir / "usr/include").string(),
      "-I",
      (x11_dir / "usr/include").string(),
      "-I",
      (x11_dir / "usr/include/cairo").string(),
  };

  std::vector<std::string> objcxx_flags = {
      "-ObjC++",
      "-std=gnu++20",
      "-fobjc-runtime=macosx-11.0",
      "-fno-objc-exceptions",
      "-fno-exceptions",
      "-fno-rtti",
      "-fno-threadsafe-statics",
      "-nostdinc++",
  };

  std::vector<std::string> cxx_flags = {
      "-std=gnu++20",
      "-fno-exceptions",
      "-fno-rtti",
      "-fno-threadsafe-statics",
      "-nostdinc++",
  };

  fs::path usr_lib = rootfs_extract / "usr/lib";
  fs::path usr_lib_system = rootfs_extract / "usr/lib/system";
  fs::path libsystem = usr_lib / "libSystem.B.dylib";
  fs::path libx11 = usr_lib / "libX11.6.dylib";
  fs::path libcairo = usr_lib / "libcairo.2.dylib";
  fs::path libxext = usr_lib / "libXext.6.dylib";
  fs::path libxrender = usr_lib / "libXrender.1.dylib";

  auto sign_macho = [&](const fs::path& bin) -> bool {
    return RunCommand({signer_tool.string(), bin.string()}) == 0;
  };

  // 0. Augment /usr/lib/system/libsystem_native_blocks.dylib with stack protector & GCD
  fs::path libsystem_ext_o = build_dir / "libsystem_ext.o";
  fs::path blocks_base = build_dir / "libsystem_native_blocks_base.dylib";
  fs::path augmented_blocks = build_dir / "libsystem_native_blocks.dylib";
  {
    fs::copy_file(usr_lib_system / "libsystem_native_blocks.dylib", blocks_base,
                  fs::copy_options::overwrite_existing);
    fs::permissions(blocks_base,
                    fs::perms::owner_read | fs::perms::owner_write,
                    fs::perm_options::add);
    if (RunCommand({"llvm-install-name-tool", "-id",
                    "/usr/lib/system/libsystem_native_blocks_base.dylib",
                    blocks_base.string()}) != 0 ||
        !sign_macho(blocks_base)) {
      return 1;
    }

    std::vector<std::string> cmd_ext = {"clang-20", "-std=gnu11"};
    cmd_ext.insert(cmd_ext.end(), common_flags.begin(), common_flags.end());
    cmd_ext.insert(
        cmd_ext.end(),
        {"-c", (workspace_root / "darling/libSystem/libsystem_ext.c").string(),
         "-o", libsystem_ext_o.string()});

    // LLVM libunwind (unmodified upstream sources) provides the _Unwind_*
    // C++ exception ABI, which Apple ships as part of libSystem.
    std::vector<std::string> unwind_objs;
    if (!libunwind_dir.empty()) {
      const std::vector<std::string> uw_flags = {
          "-I", (libunwind_dir / "include").string(),
          "-D_LIBUNWIND_IS_NATIVE_ONLY", "-DNDEBUG"};
      struct UwSrc {
        const char* file;
        bool cxx;
      };
      for (const UwSrc& src : {UwSrc{"UnwindLevel1.c", false},
                               UwSrc{"UnwindLevel1-gcc-ext.c", false},
                               UwSrc{"UnwindRegistersSave.S", false},
                               UwSrc{"UnwindRegistersRestore.S", false},
                               UwSrc{"libunwind.cpp", true}}) {
        fs::path obj = build_dir / (std::string("unwind_") + src.file + ".o");
        std::vector<std::string> cmd = {src.cxx ? "clang++-20" : "clang-20"};
        if (src.cxx) {
          cmd.insert(cmd.end(), {"-std=c++17", "-nostdinc++", "-fno-exceptions",
                                 "-fno-rtti"});
        }
        for (const auto& f : common_flags) {
          if (f != "-Wall" && f != "-Wextra" && f != "-Werror") cmd.push_back(f);
        }
        cmd.insert(cmd.end(), uw_flags.begin(), uw_flags.end());
        cmd.insert(cmd.end(), {"-c", (libunwind_dir / "src" / src.file).string(),
                               "-o", obj.string()});
        if (RunCommand(cmd) != 0) return 1;
        unwind_objs.push_back(obj.string());
      }
    }

    std::vector<std::string> cmd_link = {
        "ld64.lld",
        "-arch",
        "arm64",
        "-dylib",
        "-no_fixup_chains",
        "-platform_version",
        "macos",
        "26.5",
        "26.5",
        "-install_name",
        "/usr/lib/system/libsystem_native_blocks.dylib",
        "-current_version",
        "1.0.0",
        "-compatibility_version",
        "1.0.0",
        "-undefined",
        "dynamic_lookup",
        "-reexport_library",
        blocks_base.string(),
        libsystem_ext_o.string(),
        "-o",
        augmented_blocks.string(),
    };
    cmd_link.insert(cmd_link.end(), unwind_objs.begin(), unwind_objs.end());

    if (RunCommand(cmd_ext) != 0 || RunCommand(cmd_link) != 0 ||
        !sign_macho(augmented_blocks)) {
      return 1;
    }
  }

  // 1. Build /usr/lib/libobjc.A.dylib
  // 1. Build /usr/lib/libobjc.A.dylib (Objective-C runtime & root NSObject class)
  fs::path objc_asm_o = build_dir / "objc_msgsend_arm64.o";
  fs::path objc_rt_o = build_dir / "objc_runtime.o";
  fs::path nsobj_o = build_dir / "nsobject.o";
  fs::path libobjc = build_dir / "libobjc.A.dylib";
  {
    std::vector<std::string> cmd_asm = {
        "clang-20",
        "--target=arm64-apple-macos26.5",
        "-mcpu=cortex-a72",
        "-c",
        (workspace_root / "darling/objc/objc_msgsend_arm64.S").string(),
        "-o",
        objc_asm_o.string(),
    };
    std::vector<std::string> cmd_rt = {"clang++-20"};
    cmd_rt.insert(cmd_rt.end(), cxx_flags.begin(), cxx_flags.end());
    cmd_rt.insert(cmd_rt.end(), common_flags.begin(), common_flags.end());
    cmd_rt.insert(cmd_rt.end(),
                  {"-c",
                   (workspace_root / "darling/objc/objc_runtime.cc").string(),
                   "-o", objc_rt_o.string()});
    std::vector<std::string> cmd_nsobj = {"clang++-20"};
    cmd_nsobj.insert(cmd_nsobj.end(), objcxx_flags.begin(), objcxx_flags.end());
    cmd_nsobj.insert(cmd_nsobj.end(), common_flags.begin(), common_flags.end());
    cmd_nsobj.insert(
        cmd_nsobj.end(),
        {"-c", (workspace_root / "darling/objc/NSObject.mm").string(),
         "-o", nsobj_o.string()});
    std::vector<std::string> cmd_link = {
        "ld64.lld",
        "-arch",
        "arm64",
        "-dylib",
        "-no_fixup_chains",
        "-platform_version",
        "macos",
        "26.5",
        "26.5",
        "-install_name",
        "/usr/lib/libobjc.A.dylib",
        "-current_version",
        "228.0.0",
        "-compatibility_version",
        "1.0.0",
        "-undefined",
        "dynamic_lookup",
        "-L",
        usr_lib_system.string(),
        "-o",
        libobjc.string(),
        objc_asm_o.string(),
        objc_rt_o.string(),
        nsobj_o.string(),
        libsystem.string(),
    };
    if (RunCommand(cmd_asm) != 0 || RunCommand(cmd_rt) != 0 ||
        RunCommand(cmd_nsobj) != 0 || RunCommand(cmd_link) != 0 ||
        !sign_macho(libobjc)) {
      return 1;
    }
  }

  // 2. Build /System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices
  fs::path appservices_o = build_dir / "applicationservices.o";
  fs::path libappservices = build_dir / "ApplicationServices";
  {
    std::vector<std::string> cmd_cc = {"clang-20", "-std=gnu11"};
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c",
         (workspace_root / "darling/frameworks/applicationservices.c").string(),
         "-o", appservices_o.string()});
    std::vector<std::string> cmd_link = {
        "ld64.lld",
        "-arch",
        "arm64",
        "-dylib",
        "-no_fixup_chains",
        "-platform_version",
        "macos",
        "26.5",
        "26.5",
        "-install_name",
        "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/"
        "ApplicationServices",
        "-current_version",
        "65.0.0",
        "-compatibility_version",
        "1.0.0",
        "-undefined",
        "dynamic_lookup",
        "-L",
        usr_lib_system.string(),
        "-o",
        libappservices.string(),
        appservices_o.string(),
        libsystem.string(),
    };
    if (RunCommand(cmd_cc) != 0 || RunCommand(cmd_link) != 0 ||
        !sign_macho(libappservices)) {
      return 1;
    }
  }

  // 3. Build /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
  fs::path corefound_o = build_dir / "corefoundation.o";
  fs::path libcorefoundation = build_dir / "CoreFoundation";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), objcxx_flags.begin(), objcxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c",
         (workspace_root / "darling/frameworks/corefoundation.mm").string(),
         "-o", corefound_o.string()});
    std::vector<std::string> cmd_link = {
        "ld64.lld",
        "-arch",
        "arm64",
        "-dylib",
        "-no_fixup_chains",
        "-platform_version",
        "macos",
        "26.5",
        "26.5",
        "-install_name",
        "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/"
        "CoreFoundation",
        "-current_version",
        "3423.0.0",
        "-compatibility_version",
        "150.0.0",
        "-undefined",
        "dynamic_lookup",
        "-L",
        usr_lib_system.string(),
        "-o",
        libcorefoundation.string(),
        corefound_o.string(),
        libobjc.string(),
        libsystem.string(),
    };
    if (RunCommand(cmd_cc) != 0 || RunCommand(cmd_link) != 0 ||
        !sign_macho(libcorefoundation)) {
      return 1;
    }
  }

  // 4. Build /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
  fs::path found_o = build_dir / "foundation.o";
  fs::path libfoundation = build_dir / "Foundation";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), objcxx_flags.begin(), objcxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c", (workspace_root / "darling/frameworks/foundation.mm").string(),
         "-o", found_o.string()});
    std::vector<std::string> cmd_link = {
        "ld64.lld",
        "-arch",
        "arm64",
        "-dylib",
        "-no_fixup_chains",
        "-platform_version",
        "macos",
        "26.5",
        "26.5",
        "-install_name",
        "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
        "-current_version",
        "3423.0.0",
        "-compatibility_version",
        "300.0.0",
        "-undefined",
        "dynamic_lookup",
        "-L",
        usr_lib_system.string(),
        "-o",
        libfoundation.string(),
        found_o.string(),
        libcorefoundation.string(),
        libobjc.string(),
        libsystem.string(),
    };
    if (RunCommand(cmd_cc) != 0 || RunCommand(cmd_link) != 0 ||
        !sign_macho(libfoundation)) {
      return 1;
    }
  }

  // 5. Build /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
  fs::path appkit_o = build_dir / "appkit.o";
  fs::path libappkit = build_dir / "AppKit";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), objcxx_flags.begin(), objcxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c", (workspace_root / "darling/frameworks/appkit.mm").string(),
         "-o", appkit_o.string()});
    std::vector<std::string> cmd_link = {
        "ld64.lld",
        "-arch",
        "arm64",
        "-dylib",
        "-no_fixup_chains",
        "-platform_version",
        "macos",
        "26.5",
        "26.5",
        "-install_name",
        "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
        "-current_version",
        "2575.50.26",
        "-compatibility_version",
        "45.0.0",
        "-undefined",
        "dynamic_lookup",
        "-L",
        usr_lib_system.string(),
        "-L",
        usr_lib.string(),
        "-o",
        libappkit.string(),
        appkit_o.string(),
        libobjc.string(),
        libfoundation.string(),
        libcorefoundation.string(),
        libappservices.string(),
        libx11.string(),
        libxext.string(),
        libcairo.string(),
        libsystem.string(),
    };
    if (RunCommand(cmd_cc) != 0 || RunCommand(cmd_link) != 0 ||
        !sign_macho(libappkit)) {
      return 1;
    }
  }

  // 5b. Small frameworks needed by real applications: CoreGraphics,
  // Security, CoreServices, WebKit and the Cocoa umbrella.
  struct SmallFramework {
    std::string name;
    std::string source;  // in darling/frameworks/small
    bool objcxx;
    std::vector<std::string> libs;      // linked dylibs
    std::vector<std::string> reexports; // re-exported dylibs
  };
  const std::vector<SmallFramework> small_frameworks = {
      {"CoreGraphics", "coregraphics.c", false, {libcorefoundation.string()}, {}},
      {"Security", "security.c", false, {libcorefoundation.string()}, {}},
      {"CoreServices", "coreservices.mm", true,
       {libobjc.string(), libcorefoundation.string(), libfoundation.string()}, {}},
      {"WebKit", "webkit.mm", true,
       {libobjc.string(), libcorefoundation.string(), libfoundation.string(),
        libappkit.string()},
       {}},
      {"Cocoa", "cocoa.c", false, {},
       {libappkit.string(), libfoundation.string(), libcorefoundation.string()}},
  };
  std::vector<std::pair<std::string, fs::path>> small_framework_bins;
  for (const auto& fw : small_frameworks) {
    fs::path obj = build_dir / (fw.name + ".o");
    fs::path bin = build_dir / fw.name;
    std::vector<std::string> cmd_cc = {fw.objcxx ? "clang++-20" : "clang-20"};
    if (fw.objcxx) {
      cmd_cc.insert(cmd_cc.end(), objcxx_flags.begin(), objcxx_flags.end());
    } else {
      cmd_cc.push_back("-std=gnu11");
    }
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(cmd_cc.end(),
                  {"-c", (workspace_root / "darling/frameworks/small" / fw.source).string(),
                   "-o", obj.string()});
    std::vector<std::string> cmd_link = {
        "ld64.lld", "-arch", "arm64", "-dylib", "-no_fixup_chains",
        "-platform_version", "macos", "26.5", "26.5", "-install_name",
        "/System/Library/Frameworks/" + fw.name + ".framework/Versions/A/" + fw.name,
        "-current_version", "1.0.0", "-compatibility_version", "1.0.0",
        "-undefined", "dynamic_lookup", "-L", usr_lib_system.string(),
        "-o", bin.string(), obj.string()};
    for (const auto& r : fw.reexports) {
      cmd_link.push_back("-reexport_library");
      cmd_link.push_back(r);
    }
    cmd_link.insert(cmd_link.end(), fw.libs.begin(), fw.libs.end());
    cmd_link.push_back(libsystem.string());
    if (RunCommand(cmd_cc) != 0 || RunCommand(cmd_link) != 0 || !sign_macho(bin)) {
      return 1;
    }
    small_framework_bins.push_back({fw.name, bin});
  }

  // Helper to link a Mach-O executable
  auto link_exec = [&](const fs::path& obj, const fs::path& out,
                       const std::vector<std::string>& extra_libs) -> bool {
    std::vector<std::string> cmd = {
        "ld64.lld",
        "-arch",
        "arm64",
        "-pie",
        "-e",
        "_main",
        "-no_fixup_chains",
        "-dead_strip",
        "-platform_version",
        "macos",
        "26.5",
        "26.5",
        "-undefined",
        "dynamic_lookup",
        "-L",
        usr_lib_system.string(),
        "-L",
        usr_lib.string(),
        "-o",
        out.string(),
        obj.string(),
    };
    cmd.insert(cmd.end(), extra_libs.begin(), extra_libs.end());
    cmd.push_back(libsystem.string());
    return RunCommand(cmd) == 0 && sign_macho(out);
  };

  // 4. Build /usr/bin/sw_vers from @darling//:src/tools/sw_vers.c
  fs::path sw_vers_o = build_dir / "sw_vers.o";
  fs::path sw_vers_bin = build_dir / "sw_vers";
  {
    std::vector<std::string> cmd_cc = {"clang-20", "-std=gnu11"};
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(cmd_cc.end(), {"-c", darling_sw_vers.string(), "-o",
                                 sw_vers_o.string()});
    if (RunCommand(cmd_cc) != 0 ||
        !link_exec(sw_vers_o, sw_vers_bin,
                   {libobjc.string(), libcorefoundation.string(),
                    libfoundation.string()})) {
      return 1;
    }
  }

  // 5. Build /usr/bin/darling
  fs::path darling_o = build_dir / "darling_cli.o";
  fs::path darling_bin = build_dir / "darling";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), cxx_flags.begin(), cxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c", (workspace_root / "darling/tools/darling_cli.cc").string(),
         "-o", darling_o.string()});
    if (RunCommand(cmd_cc) != 0 || !link_exec(darling_o, darling_bin, {})) {
      return 1;
    }
  }

  // 6. Build /usr/bin/open
  fs::path open_o = build_dir / "open_cli.o";
  fs::path open_bin = build_dir / "open";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), cxx_flags.begin(), cxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c", (workspace_root / "darling/tools/open_cli.cc").string(), "-o",
         open_o.string()});
    if (RunCommand(cmd_cc) != 0 || !link_exec(open_o, open_bin, {})) {
      return 1;
    }
  }

  // 7. Build /bin/darling-desktop-start
  fs::path desktop_start_o = build_dir / "darling_desktop_start.o";
  fs::path desktop_start_bin = build_dir / "darling-desktop-start";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), cxx_flags.begin(), cxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c",
         (workspace_root / "darling/tools/darling_desktop_start.cc").string(),
         "-o", desktop_start_o.string()});
    if (RunCommand(cmd_cc) != 0 ||
        !link_exec(desktop_start_o, desktop_start_bin, {libx11.string()})) {
      return 1;
    }
  }

  // 7b. Build /System/Library/CoreServices/darling-shell (menu bar, Dock,
  // Finder window, wallpaper and cursor for the Mac OS X desktop).
  fs::path shell_o = build_dir / "darling_shell.o";
  fs::path shell_bin = build_dir / "darling-shell";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), cxx_flags.begin(), cxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(cmd_cc.end(),
                  {"-c", (workspace_root / "darling/tools/darling_shell.cc").string(),
                   "-o", shell_o.string()});
    if (RunCommand(cmd_cc) != 0 ||
        !link_exec(shell_o, shell_bin,
                   {libx11.string(), libxext.string(), libxrender.string(),
                    libcairo.string()})) {
      return 1;
    }
  }

  // 8. Build /Applications/HelloWorld.app/Contents/MacOS/HelloWorld
  fs::path hello_o = build_dir / "hello_main.o";
  fs::path hello_bin = build_dir / "HelloWorld";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), objcxx_flags.begin(), objcxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c", (workspace_root / "apps/HelloWorld/main.mm").string(), "-o",
         hello_o.string()});
    if (RunCommand(cmd_cc) != 0 ||
        !link_exec(hello_o, hello_bin,
                   {libobjc.string(), libcorefoundation.string(),
                    libfoundation.string(), libappkit.string(),
                    libx11.string(), libcairo.string()})) {
      return 1;
    }
  }

  // 8b. Build /Applications/WidgetGallery.app/Contents/MacOS/WidgetGallery
  fs::path gallery_o = build_dir / "widget_gallery_main.o";
  fs::path gallery_bin = build_dir / "WidgetGallery";
  {
    std::vector<std::string> cmd_cc = {"clang++-20"};
    cmd_cc.insert(cmd_cc.end(), objcxx_flags.begin(), objcxx_flags.end());
    cmd_cc.insert(cmd_cc.end(), common_flags.begin(), common_flags.end());
    cmd_cc.insert(
        cmd_cc.end(),
        {"-c", (workspace_root / "apps/WidgetGallery/main.mm").string(), "-o",
         gallery_o.string()});
    if (RunCommand(cmd_cc) != 0 ||
        !link_exec(gallery_o, gallery_bin,
                   {libobjc.string(), libcorefoundation.string(),
                    libfoundation.string(), libappkit.string(),
                    libx11.string(), libcairo.string()})) {
      return 1;
    }
  }

  // 15. Prepare and sign vendored /Applications/FastDMG.app/Contents/MacOS/FastDMG
  fs::path fastdmg_bin = build_dir / "FastDMG";
  fs::copy_file(workspace_root / "vendor/FastDMG.app/Contents/MacOS/FastDMG",
                fastdmg_bin, fs::copy_options::overwrite_existing);
  fs::permissions(fastdmg_bin,
                  fs::perms::owner_read | fs::perms::owner_write |
                      fs::perms::owner_exec,
                  fs::perm_options::add);
  if (!sign_macho(fastdmg_bin)) {
    return 1;
  }

  // 15b. Prepare and sign vendored ZoomUninstaller, ZoomAutoUpdater, zoom.us,
  // balenaEtcher, and OBS (ARM64) Mach-O binaries.
  auto prep_signed_bin = [&](const fs::path& src_rel,
                             const std::string& out_name) -> fs::path {
    fs::path out = build_dir / out_name;
    if (!fs::exists(workspace_root / src_rel)) {
      std::cerr << "Skipping absent optional binary: " << src_rel << "\n";
      return {};
    }
    fs::copy_file(workspace_root / src_rel, out,
                  fs::copy_options::overwrite_existing);
    fs::permissions(out,
                    fs::perms::owner_read | fs::perms::owner_write |
                        fs::perms::owner_exec,
                    fs::perm_options::add);
    if (!sign_macho(out)) {
      std::exit(1);
    }
    return out;
  };
  fs::path zoom_uninstaller_bin = prep_signed_bin(
      "vendor/zoom.us.app/Contents/Frameworks/ZoomUninstaller.app/Contents/MacOS/ZoomUninstaller",
      "ZoomUninstaller");
  fs::path zoom_autoupdater_bin = prep_signed_bin(
      "vendor/zoom.us.app/Contents/Frameworks/ZoomAutoUpdater.app/Contents/MacOS/ZoomAutoUpdater",
      "ZoomAutoUpdater");
  fs::path zoom_main_bin = prep_signed_bin(
      "vendor/zoom.us.app/Contents/MacOS/zoom.us", "zoom.us");
  fs::path etcher_bin = prep_signed_bin(
      "vendor/balenaEtcher.app/Contents/MacOS/balenaEtcher", "balenaEtcher");
  fs::path obs_arm64_bin = prep_signed_bin(
      "vendor/OBS.app/Contents/MacOS/OBS", "OBS_arm64");
  fs::path obs_mux_arm64_bin = prep_signed_bin(
      "vendor/OBS.app/Contents/MacOS/obs-ffmpeg-mux", "obs-ffmpeg-mux_arm64");

  // 16. Platypus-format applications: the unmodified ScriptExec runtime and
  // MainMenu.nib from Platypus 5.5.0 (vendor/Platypus-5.5.0) plus each app's
  // AppSettings.plist, script and Info.plist (apps/PlatypusApps/<Name>).
  // ScriptExec is thinned to its arm64 slice and ad-hoc signed.
  fs::path scriptexec_bin = build_dir / "ScriptExec";
  if (RunCommand({"llvm-lipo", "-thin", "arm64",
                  (workspace_root / "vendor/Platypus-5.5.0/ScriptExec").string(),
                  "-output", scriptexec_bin.string()}) != 0 ||
      !sign_macho(scriptexec_bin)) {
    return 1;
  }
  std::vector<std::string> platypus_apps;
  for (const auto& entry :
       fs::directory_iterator(workspace_root / "apps/PlatypusApps")) {
    if (entry.is_directory()) platypus_apps.push_back(entry.path().filename().string());
  }
  std::sort(platypus_apps.begin(), platypus_apps.end());

  // Prepare Xfce4 session & panel XML configurations for Darling Embedded
  fs::path xfce_session_xml = build_dir / "xfce4-session.xml";
  WriteTextFile(
      xfce_session_xml,
      R"(<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSessionName" type="string" value="Failsafe"/>
    <property name="LockCommand" type="string" value=""/>
  </property>
  <property name="sessions" type="empty">
    <property name="Failsafe" type="empty">
      <property name="IsFailsafe" type="bool" value="true"/>
      <property name="Count" type="int" value="3"/>
      <property name="Client0_Command" type="array">
        <value type="string" value="xfwm4"/>
      </property>
      <property name="Client0_Priority" type="int" value="15"/>
      <property name="Client0_PerScreen" type="bool" value="false"/>
      <property name="Client1_Command" type="array">
        <value type="string" value="xfce4-panel"/>
      </property>
      <property name="Client1_Priority" type="int" value="25"/>
      <property name="Client1_PerScreen" type="bool" value="false"/>
      <property name="Client2_Command" type="array">
        <value type="string" value="xfdesktop"/>
      </property>
      <property name="Client2_Priority" type="int" value="35"/>
      <property name="Client2_PerScreen" type="bool" value="false"/>
    </property>
  </property>
</channel>
)");

  fs::path xfce_panel_xml = build_dir / "xfce4-panel.xml";
  std::string panel_xml =
      R"(<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <value type="int" value="2"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="16"/>
      <property name="size" type="uint" value="26"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
      </property>
    </property>
    <property name="panel-2" type="empty">
      <property name="autohide-behavior" type="uint" value="0"/>
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="1"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="48"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
        <value type="int" value="14"/>
@@DOCK_IDS@@      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="grouping" type="uint" value="0"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="pager"/>
    <property name="plugin-5" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-6" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-7" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-8" type="string" value="clock"/>
    <property name="plugin-9" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-10" type="string" value="actions"/>
    <property name="plugin-11" type="string" value="showdesktop"/>
    <property name="plugin-12" type="string" value="separator"/>
    <property name="plugin-13" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="darling-fastdmg.desktop"/>
      </property>
    </property>
    <property name="plugin-14" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="darling-helloworld.desktop"/>
      </property>
    </property>
@@DOCK_PLUGINS@@  </property>
</channel>
)";
  // One dock launcher per Platypus-format app + WidgetGallery.
  std::string dock_ids, dock_plugins;
  std::vector<std::pair<fs::path, std::string>> app_desktop_files;
  for (size_t i = 0; i < platypus_apps.size(); ++i) {
    const std::string id = std::to_string(15 + i);
    const std::string file = "darling-app-" + id + ".desktop";
    dock_ids += "        <value type=\"int\" value=\"" + id + "\"/>\n";
    dock_plugins += "    <property name=\"plugin-" + id +
                    "\" type=\"string\" value=\"launcher\">\n"
                    "      <property name=\"items\" type=\"array\">\n"
                    "        <value type=\"string\" value=\"" + file + "\"/>\n"
                    "      </property>\n    </property>\n";
    fs::path desktop = build_dir / file;
    WriteTextFile(desktop, "[Desktop Entry]\nVersion=1.0\nType=Application\nName=" +
                               platypus_apps[i] +
                               "\nComment=Platypus ScriptExec application\n"
                               "Exec=/usr/bin/open \"/Applications/" + platypus_apps[i] +
                               ".app\"\nIcon=utilities-terminal\nTerminal=false\n"
                               "Categories=Utility;\n");
    app_desktop_files.push_back({desktop, file});
  }
  {
    const std::string id = std::to_string(15 + platypus_apps.size());
    dock_ids += "        <value type=\"int\" value=\"" + id + "\"/>\n";
    dock_plugins += "    <property name=\"plugin-" + id +
                    "\" type=\"string\" value=\"launcher\">\n"
                    "      <property name=\"items\" type=\"array\">\n"
                    "        <value type=\"string\" value=\"darling-widgetgallery.desktop\"/>\n"
                    "      </property>\n    </property>\n";
  }
  {
    const std::string id = std::to_string(16 + platypus_apps.size());
    dock_ids += "        <value type=\"int\" value=\"" + id + "\"/>\n";
    dock_plugins += "    <property name=\"plugin-" + id +
                    "\" type=\"string\" value=\"launcher\">\n"
                    "      <property name=\"items\" type=\"array\">\n"
                    "        <value type=\"string\" value=\"darling-zoomuninstaller.desktop\"/>\n"
                    "      </property>\n    </property>\n";
  }
  {
    const std::string id = std::to_string(17 + platypus_apps.size());
    dock_ids += "        <value type=\"int\" value=\"" + id + "\"/>\n";
    dock_plugins += "    <property name=\"plugin-" + id +
                    "\" type=\"string\" value=\"launcher\">\n"
                    "      <property name=\"items\" type=\"array\">\n"
                    "        <value type=\"string\" value=\"chromium.desktop\"/>\n"
                    "      </property>\n    </property>\n";
  }
  panel_xml.replace(panel_xml.find("@@DOCK_IDS@@"), 12, dock_ids);
  panel_xml.replace(panel_xml.find("@@DOCK_PLUGINS@@"), 16, dock_plugins);
  WriteTextFile(xfce_panel_xml, panel_xml);

  fs::path desktop_session_cfg = build_dir / "desktop-session";
  WriteTextFile(desktop_session_cfg, "/bin/darling-desktop-start\n");

  // Fontconfig: Inter is the preferred sans-serif / UI family.
  fs::path fontconfig_local = build_dir / "local.conf";
  WriteTextFile(fontconfig_local,
                R"(<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Darling Embedded: Mac OS X-like user interface fonts. -->
<fontconfig>
  <dir>/usr/share/fonts/inter</dir>
  <alias binding="strong">
    <family>sans-serif</family>
    <prefer><family>Inter</family></prefer>
  </alias>
  <alias binding="strong">
    <family>system-ui</family>
    <prefer><family>Inter</family></prefer>
  </alias>
  <alias binding="same">
    <family>Helvetica Neue</family>
    <accept><family>Inter</family></accept>
  </alias>
  <alias binding="same">
    <family>Lucida Grande</family>
    <accept><family>Inter</family></accept>
  </alias>
  <alias binding="same">
    <family>Menlo</family>
    <accept><family>DejaVu Sans Mono</family></accept>
  </alias>
</fontconfig>
)");

  fs::path hello_desktop = build_dir / "darling-helloworld.desktop";
  WriteTextFile(hello_desktop,
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Type=Application\n"
                "Name=HelloWorld (Mac OS X)\n"
                "Comment=Native Mac OS X Hello World Cocoa App via Darling\n"
                "Exec=/usr/bin/darling open /Applications/HelloWorld.app\n"
                "Icon=applications-system\n"
                "Terminal=false\n"
                "Categories=System;Utility;\n");

  fs::path fastdmg_desktop = build_dir / "darling-fastdmg.desktop";
  WriteTextFile(fastdmg_desktop,
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Type=Application\n"
                "Name=FastDMG (Mac OS X)\n"
                "Comment=Real Vendored Mac OS X FastDMG App via Darling\n"
                "Exec=/usr/bin/darling open /Applications/FastDMG.app\n"
                "Icon=drive-removable-media\n"
                "Terminal=false\n"
                "Categories=Utility;System;\n");

  fs::path gallery_desktop = build_dir / "darling-widgetgallery.desktop";
  WriteTextFile(gallery_desktop,
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Type=Application\n"
                "Name=Widget Gallery (Mac OS X)\n"
                "Comment=Darling AppKit Cocoa GUI Widget Showcase\n"
                "Exec=/usr/bin/open /Applications/WidgetGallery.app\n"
                "Icon=preferences-desktop-theme\n"
                "Terminal=false\n"
                "Categories=Development;Utility;\n");

  fs::path zoom_uninstaller_desktop = build_dir / "darling-zoomuninstaller.desktop";
  WriteTextFile(zoom_uninstaller_desktop,
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Type=Application\n"
                "Name=Zoom Workplace Uninstaller (Mac OS X)\n"
                "Comment=Vendored Mac OS X Zoom Workplace Uninstaller App via Darling\n"
                "Exec=/usr/bin/open /Applications/ZoomUninstaller.app\n"
                "Icon=system-software-install\n"
                "Terminal=false\n"
                "Categories=Utility;System;\n");

  fs::path chromium_wrapper = build_dir / "chromium";
  WriteTextFile(
      chromium_wrapper,
      "#!/bin/sh\n"
      "if [ -z \"$DISPLAY\" ]; then\n"
      "    export DISPLAY=:0\n"
      "fi\n"
      "exec /bin/headless_shell \\\n"
      "    --no-sandbox \\\n"
      "    --no-zygote \\\n"
      "    --single-process \\\n"
      "    --ozone-platform=x11 \\\n"
      "    --use-gl=angle \\\n"
      "    --use-angle=swiftshader-webgl \\\n"
      "    --enable-webgl \\\n"
      "    --enable-unsafe-swiftshader \\\n"
      "    --ignore-gpu-blocklist \\\n"
      "    --disable-gpu-compositing \\\n"
      "    --disable-gpu-rasterization \\\n"
      "    --disable-smooth-scrolling \\\n"
      "    --force-prefers-reduced-motion \\\n"
      "    --autoplay-policy=document-user-activation-required \\\n"
      "    --disable-features=MediaEngagementBypassAutoplayPolicies,BackForwardCache \\\n"
      "    --enable-logging=stderr --v=0 \\\n"
      "    --window-size=500,590 --window-position=16,48 \\\n"
      "    --user-data-dir=/var/tmp/chromium-profile \\\n"
      "    --js-flags=\"--max-old-space-size=192 --max-semi-space-size=8\" \\\n"
      "    \"$@\"\n");

  fs::path chromium_test_html = build_dir / "test.html";
  WriteTextFile(
      chromium_test_html,
      "<!DOCTYPE html>\n"
      "<html>\n"
      "<head><title>Darwin Chromium SwiftShader</title></head>\n"
      "<body style=\"background:#103060;color:#ffffff;font-family:sans-serif;padding:20px;margin:0;overflow-wrap:break-word\">\n"
      "<h1 id=\"hdr\" style=\"font-size:21px;margin:0 0 12px 0\">Hello from Chromium on Darwin 25.5.0</h1>\n"
      "<h2 id=\"gl-info\" style=\"font-size:14px;line-height:1.4;font-weight:normal;color:#b8d8ff;margin:0 0 12px 0\">Initializing WebGL...</h2>\n"
      "<h2 id=\"scroll-info\" style=\"font-size:15px;margin:0 0 14px 0\">ScrollY: 0 | ARM64 Mach-O + ANGLE + SwiftShader</h2>\n"
      "<div id=\"box\" style=\"width:200px;height:52px;background:#e02020;margin-bottom:12px;border-radius:6px\"></div>\n"
      "<canvas id=\"c\" width=\"240\" height=\"120\" style=\"border:2px solid #ffffff;border-radius:6px\"></canvas>\n"
      "<script>\n"
      "const gl = document.getElementById(\"c\").getContext(\"webgl\");\n"
      "if (gl) {\n"
      "  gl.clearColor(0.1, 0.85, 0.3, 1.0);\n"
      "  gl.clear(gl.COLOR_BUFFER_BIT);\n"
      "}\n"
      "const dbg = gl ? gl.getExtension(\"WEBGL_debug_renderer_info\") : null;\n"
      "const renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : (gl ? gl.getParameter(gl.RENDERER) : \"no-webgl\");\n"
      "document.getElementById(\"gl-info\").textContent = renderer;\n"
      "document.body.setAttribute(\"data-renderer\", renderer);\n"
      "console.log(\"WEBGL_READY:\" + renderer);\n"
      "</script>\n"
      "</body>\n"
      "</html>\n");

  fs::path chromium_desktop = build_dir / "chromium.desktop";
  WriteTextFile(
      chromium_desktop,
      "[Desktop Entry]\n"
      "Version=1.0\n"
      "Type=Application\n"
      "Name=Chromium Web Browser\n"
      "Comment=Native Chromium on Darwin 25.5.0 with ANGLE + SwiftShader WebGL\n"
      "Exec=/bin/chromium file:///usr/share/chromium/test.html\n"
      "Icon=web-browser\n"
      "Terminal=false\n"
      "Categories=Network;WebBrowser;\n"
      "StartupNotify=false\n");

  auto hfs_mkdir_p = [&](const std::string& dir_path) {
    fs::path check = rootfs_extract / dir_path.substr(1);
    if (!fs::is_directory(check)) {
      RunCommand({hfs_tool.string(), img.string(), "mkdir", dir_path});
      fs::create_directories(check);
    }
  };

  const std::vector<std::string> dirs_to_create = {
      "/System",
      "/System/Library",
      "/System/Library/CoreServices",
      "/System/Library/Frameworks",
      "/System/Library/Frameworks/Foundation.framework",
      "/System/Library/Frameworks/Foundation.framework/Versions",
      "/System/Library/Frameworks/Foundation.framework/Versions/C",
      "/System/Library/Frameworks/CoreFoundation.framework",
      "/System/Library/Frameworks/CoreFoundation.framework/Versions",
      "/System/Library/Frameworks/CoreFoundation.framework/Versions/A",
      "/System/Library/Frameworks/AppKit.framework",
      "/System/Library/Frameworks/AppKit.framework/Versions",
      "/System/Library/Frameworks/AppKit.framework/Versions/C",
      "/System/Library/Frameworks/ApplicationServices.framework",
      "/System/Library/Frameworks/ApplicationServices.framework/Versions",
      "/System/Library/Frameworks/ApplicationServices.framework/Versions/A",
      "/Applications",
      "/Applications/HelloWorld.app",
      "/Applications/HelloWorld.app/Contents",
      "/Applications/HelloWorld.app/Contents/MacOS",
      "/Applications/WidgetGallery.app",
      "/Applications/WidgetGallery.app/Contents",
      "/Applications/WidgetGallery.app/Contents/MacOS",
      "/Applications/FastDMG.app",
      "/Applications/FastDMG.app/Contents",
      "/Applications/FastDMG.app/Contents/MacOS",
      "/Applications/FastDMG.app/Contents/Resources",
      "/Applications/FastDMG.app/Contents/Resources/Base.lproj",
      "/Applications/FastDMG.app/Contents/_CodeSignature",
      "/Applications/balenaEtcher.app",
      "/Applications/balenaEtcher.app/Contents",
      "/Applications/balenaEtcher.app/Contents/MacOS",
      "/Applications/balenaEtcher.app/Contents/Resources",
      "/Applications/balenaEtcher.app/Contents/Frameworks",
      "/Applications/balenaEtcher.app/Contents/Frameworks/Electron Framework.framework",
      "/Applications/balenaEtcher.app/Contents/Frameworks/Electron Framework.framework/Versions",
      "/Applications/balenaEtcher.app/Contents/Frameworks/Electron Framework.framework/Versions/A",
      "/Applications/balenaEtcher.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources",
      "/Applications/OBS.app",
      "/Applications/OBS.app/Contents",
      "/Applications/OBS.app/Contents/MacOS",
      "/Applications/OBS.app/Contents/Resources",
      "/Applications/OBS-Intel.app",
      "/Applications/OBS-Intel.app/Contents",
      "/Applications/OBS-Intel.app/Contents/MacOS",
      "/Applications/OBS-Intel.app/Contents/Resources",
      "/Applications/zoom.us.app",
      "/Applications/zoom.us.app/Contents",
      "/Applications/zoom.us.app/Contents/MacOS",
      "/Applications/zoom.us.app/Contents/Resources",
      "/Applications/zoom.us.app/Contents/Frameworks",
      "/Applications/ZoomUninstaller.app",
  };
  for (const auto& d : dirs_to_create) {
    hfs_mkdir_p(d);
  }

  struct InstallItem {
    fs::path src;
    std::string dst;
    std::string mode;
  };
  const std::vector<InstallItem> items = {
      {blocks_base, "/usr/lib/system/libsystem_native_blocks_base.dylib", "755"},
      {augmented_blocks, "/usr/lib/system/libsystem_native_blocks.dylib", "755"},
      {libobjc, "/usr/lib/libobjc.A.dylib", "755"},
      {libcorefoundation,
       "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
       "755"},
      {libcorefoundation,
       "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/"
       "CoreFoundation",
       "755"},
      {libcorefoundation, "/usr/lib/libCoreFoundation.dylib", "755"},
      {libfoundation,
       "/System/Library/Frameworks/Foundation.framework/Foundation", "755"},
      {libfoundation,
       "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation",
       "755"},
      {libfoundation, "/usr/lib/libFoundation.dylib", "755"},
      {libappservices,
       "/System/Library/Frameworks/ApplicationServices.framework/"
       "ApplicationServices",
       "755"},
      {libappservices,
       "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/"
       "ApplicationServices",
       "755"},
      {libappservices, "/usr/lib/libApplicationServices.dylib", "755"},
      {libappkit, "/System/Library/Frameworks/AppKit.framework/AppKit", "755"},
      {libappkit,
       "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit", "755"},
      {libappkit, "/usr/lib/libAppKit.dylib", "755"},
      {sw_vers_bin, "/usr/bin/sw_vers", "755"},
      {darling_bin, "/usr/bin/darling", "755"},
      {open_bin, "/usr/bin/open", "755"},
      {desktop_start_bin, "/bin/darling-desktop-start", "755"},
      {shell_bin, "/System/Library/CoreServices/darling-shell", "755"},
      {fontconfig_local, "/etc/fonts/local.conf", "644"},
      {hello_bin, "/Applications/HelloWorld.app/Contents/MacOS/HelloWorld",
       "755"},
      {hello_bin, "/usr/bin/hello_macosx", "755"},
      {workspace_root / "apps/HelloWorld/Info.plist",
       "/Applications/HelloWorld.app/Contents/Info.plist", "644"},
      {gallery_bin,
       "/Applications/WidgetGallery.app/Contents/MacOS/WidgetGallery", "755"},
      {workspace_root / "apps/WidgetGallery/Info.plist",
       "/Applications/WidgetGallery.app/Contents/Info.plist", "644"},
      {fastdmg_bin, "/Applications/FastDMG.app/Contents/MacOS/FastDMG", "755"},
      {fastdmg_bin, "/usr/bin/fastdmg", "755"},
      {workspace_root / "vendor/FastDMG.app/Contents/Info.plist",
       "/Applications/FastDMG.app/Contents/Info.plist", "644"},
      {workspace_root / "vendor/FastDMG.app/Contents/Resources/Credits.rtf",
       "/Applications/FastDMG.app/Contents/Resources/Credits.rtf", "644"},
      {workspace_root /
           "vendor/FastDMG.app/Contents/Resources/Base.lproj/MainMenu.nib",
       "/Applications/FastDMG.app/Contents/Resources/Base.lproj/MainMenu.nib",
       "644"},
      {workspace_root /
           "vendor/FastDMG.app/Contents/Resources/Base.lproj/MainWindow.nib",
       "/Applications/FastDMG.app/Contents/Resources/Base.lproj/MainWindow.nib",
       "644"},
      {workspace_root /
           "vendor/FastDMG.app/Contents/Resources/fastdmg.icns",
       "/Applications/FastDMG.app/Contents/Resources/fastdmg.icns", "644"},
      {workspace_root /
           "vendor/FastDMG.app/Contents/Resources/diskimage.icns",
       "/Applications/FastDMG.app/Contents/Resources/diskimage.icns", "644"},
      {workspace_root /
           "vendor/FastDMG.app/Contents/_CodeSignature/CodeResources",
       "/Applications/FastDMG.app/Contents/_CodeSignature/CodeResources",
       "644"},
      {workspace_root / "darling/tools/SystemVersion.plist",
       "/System/Library/CoreServices/SystemVersion.plist", "644"},
      {desktop_session_cfg, "/etc/desktop-session", "644"},
      {xfce_session_xml,
       "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml", "644"},
      {xfce_panel_xml,
       "/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml", "644"},
      {xfce_panel_xml, "/etc/xdg/xfce4/panel/default.xml", "644"},
      {hello_desktop, "/usr/share/applications/darling-helloworld.desktop",
       "644"},
      {fastdmg_desktop, "/usr/share/applications/darling-fastdmg.desktop",
       "644"},
      {gallery_desktop,
       "/usr/share/applications/darling-widgetgallery.desktop", "644"},
      {zoom_uninstaller_desktop,
       "/usr/share/applications/darling-zoomuninstaller.desktop", "644"},
      {hello_desktop, "/var/root/Desktop/HelloWorld.desktop", "755"},
      {fastdmg_desktop, "/var/root/Desktop/FastDMG.desktop", "755"},
      {gallery_desktop, "/var/root/Desktop/WidgetGallery.desktop", "755"},
      {zoom_uninstaller_desktop, "/var/root/Desktop/ZoomUninstaller.desktop", "755"},
      {chromium_wrapper, "/bin/chromium", "755"},
      {chromium_test_html, "/usr/share/chromium/test.html", "644"},
      {chromium_desktop, "/usr/share/applications/chromium.desktop", "644"},
      {chromium_desktop, "/var/root/Desktop/Chromium.desktop", "755"},
      // Vendored balenaEtcher.app (2.1.7, arm64)
      {etcher_bin,
       "/Applications/balenaEtcher.app/Contents/MacOS/balenaEtcher", "755"},
      {workspace_root / "vendor/balenaEtcher.app/Contents/Info.plist",
       "/Applications/balenaEtcher.app/Contents/Info.plist", "644"},
      {workspace_root / "vendor/balenaEtcher.app/Contents/PkgInfo",
       "/Applications/balenaEtcher.app/Contents/PkgInfo", "644"},
      {workspace_root / "vendor/balenaEtcher.app/Contents/Resources/electron.icns",
       "/Applications/balenaEtcher.app/Contents/Resources/electron.icns", "644"},
      {workspace_root /
           "vendor/balenaEtcher.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/MainMenu.nib",
       "/Applications/balenaEtcher.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/MainMenu.nib",
       "644"},
      // Vendored OBS.app (32.2.2, arm64)
      {obs_arm64_bin, "/Applications/OBS.app/Contents/MacOS/OBS", "755"},
      {obs_mux_arm64_bin,
       "/Applications/OBS.app/Contents/MacOS/obs-ffmpeg-mux", "755"},
      {workspace_root / "vendor/OBS.app/Contents/Info.plist",
       "/Applications/OBS.app/Contents/Info.plist", "644"},
      {workspace_root / "vendor/OBS.app/Contents/PkgInfo",
       "/Applications/OBS.app/Contents/PkgInfo", "644"},
      {workspace_root / "vendor/OBS.app/Contents/Resources/AppIcon.icns",
       "/Applications/OBS.app/Contents/Resources/AppIcon.icns", "644"},
      // Vendored OBS-Intel.app (32.2.2, x86_64)
      {workspace_root / "vendor/OBS-Intel.app/Contents/MacOS/OBS",
       "/Applications/OBS-Intel.app/Contents/MacOS/OBS", "755"},
      {workspace_root / "vendor/OBS-Intel.app/Contents/MacOS/obs-ffmpeg-mux",
       "/Applications/OBS-Intel.app/Contents/MacOS/obs-ffmpeg-mux", "755"},
      {workspace_root / "vendor/OBS-Intel.app/Contents/Info.plist",
       "/Applications/OBS-Intel.app/Contents/Info.plist", "644"},
      {workspace_root / "vendor/OBS-Intel.app/Contents/PkgInfo",
       "/Applications/OBS-Intel.app/Contents/PkgInfo", "644"},
      {workspace_root / "vendor/OBS-Intel.app/Contents/Resources/AppIcon.icns",
       "/Applications/OBS-Intel.app/Contents/Resources/AppIcon.icns", "644"},
      // Vendored zoom.us.app (6.2.6.41824, arm64)
      {zoom_main_bin, "/Applications/zoom.us.app/Contents/MacOS/zoom.us", "755"},
      {workspace_root / "vendor/zoom.us.app/Contents/Info.plist",
       "/Applications/zoom.us.app/Contents/Info.plist", "644"},
      {workspace_root / "vendor/zoom.us.app/Contents/PkgInfo",
       "/Applications/zoom.us.app/Contents/PkgInfo", "644"},
      {workspace_root / "vendor/zoom.us.app/Contents/Resources/ZPLogo.icns",
       "/Applications/zoom.us.app/Contents/Resources/ZPLogo.icns", "644"},
  };

  std::vector<InstallItem> all_items = items;
  auto install_bundle_tree = [&](const fs::path& src_bundle,
                                 const std::string& dst_bundle,
                                 const std::string& exec_name,
                                 const fs::path& signed_exec) {
    hfs_mkdir_p(dst_bundle);
    if (!fs::is_directory(src_bundle)) return;
    std::vector<fs::path> dirs;
    std::vector<fs::path> files;
    for (const auto& entry : fs::recursive_directory_iterator(src_bundle)) {
      if (entry.is_directory()) {
        dirs.push_back(entry.path());
      } else if (entry.is_regular_file()) {
        files.push_back(entry.path());
      }
    }
    std::sort(dirs.begin(), dirs.end());
    std::sort(files.begin(), files.end());
    for (const auto& d : dirs) {
      std::string rel = fs::relative(d, src_bundle).generic_string();
      hfs_mkdir_p(dst_bundle + "/" + rel);
    }
    for (const auto& f : files) {
      std::string rel = fs::relative(f, src_bundle).generic_string();
      if (rel == "Contents/MacOS/" + exec_name) {
        all_items.push_back({signed_exec, dst_bundle + "/" + rel, "755"});
      } else {
        all_items.push_back({f, dst_bundle + "/" + rel, "644"});
      }
    }
  };
  install_bundle_tree(
      workspace_root / "vendor/zoom.us.app/Contents/Frameworks/ZoomUninstaller.app",
      "/Applications/ZoomUninstaller.app", "ZoomUninstaller", zoom_uninstaller_bin);
  install_bundle_tree(
      workspace_root / "vendor/zoom.us.app/Contents/Frameworks/ZoomUninstaller.app",
      "/Applications/zoom.us.app/Contents/Frameworks/ZoomUninstaller.app",
      "ZoomUninstaller", zoom_uninstaller_bin);
  install_bundle_tree(
      workspace_root / "vendor/zoom.us.app/Contents/Frameworks/ZoomAutoUpdater.app",
      "/Applications/zoom.us.app/Contents/Frameworks/ZoomAutoUpdater.app",
      "ZoomAutoUpdater", zoom_autoupdater_bin);
  install_bundle_tree(
      workspace_root / "vendor/zoom.us.app/Contents/Frameworks/ZoomAutoUpdater.app",
      "/Applications/ZoomAutoUpdater.app",
      "ZoomAutoUpdater", zoom_autoupdater_bin);

  struct ExtraBundle {
    std::string vendor_dir;
    std::string dst_dir;
    std::string exec_name;
    std::string build_bin_name;
  };
  const std::vector<ExtraBundle> extra_bundles = {
      {"vendor/SparkleUpdater.app", "/Applications/SparkleUpdater.app", "Updater", "SparkleUpdater_bin"},
      {"vendor/Stickies.app", "/Applications/Stickies.app", "Stickies", "Stickies_bin"},
      {"vendor/Digital Color Meter.app", "/Applications/Digital Color Meter.app", "Digital Color Meter", "DigitalColorMeter_bin"},
      {"vendor/Image Capture.app", "/Applications/Image Capture.app", "Image Capture", "ImageCapture_bin"},
      {"vendor/Folder Actions Setup.app", "/Applications/Folder Actions Setup.app", "Folder Actions Setup", "FolderActionsSetup_bin"},
      {"vendor/Ticket Viewer.app", "/Applications/Ticket Viewer.app", "Ticket Viewer", "TicketViewer_bin"},
      {"vendor/Expansion Slot Utility.app", "/Applications/Expansion Slot Utility.app", "Expansion Slot Utility", "ExpansionSlotUtility_bin"},
      {"vendor/Install Command Line Developer Tools.app", "/Applications/Install Command Line Developer Tools.app", "Install Command Line Developer Tools", "InstallCLT_bin"},
      {"vendor/AppleScript Utility.app", "/Applications/AppleScript Utility.app", "AppleScript Utility", "AppleScriptUtility_bin"},
      {"vendor/Bluetooth File Exchange.app", "/Applications/Bluetooth File Exchange.app", "Bluetooth File Exchange", "BluetoothFileExchange_bin"},
      {"vendor/Directory Utility.app", "/Applications/Directory Utility.app", "Directory Utility", "DirectoryUtility_bin"},
  };
  for (const auto& eb : extra_bundles) {
    fs::path signed_bin = prep_signed_bin(
        eb.vendor_dir + "/Contents/MacOS/" + eb.exec_name, eb.build_bin_name);
    install_bundle_tree(workspace_root / eb.vendor_dir, eb.dst_dir, eb.exec_name,
                        signed_bin);
  }
  for (const auto& [desktop, file] : app_desktop_files) {
    all_items.push_back({desktop, "/usr/share/applications/" + file, "644"});
  }
  for (const std::string& app : platypus_apps) {
    const std::string base = "/Applications/" + app + ".app";
    for (const std::string& d :
         {base, base + "/Contents", base + "/Contents/MacOS", base + "/Contents/Resources",
          base + "/Contents/Resources/MainMenu.nib"}) {
      hfs_mkdir_p(d);
    }
    const fs::path src = workspace_root / "apps/PlatypusApps" / app;
    all_items.push_back({scriptexec_bin, base + "/Contents/MacOS/" + app, "755"});
    all_items.push_back({src / "Info.plist", base + "/Contents/Info.plist", "644"});
    all_items.push_back({src / "AppSettings.plist",
                         base + "/Contents/Resources/AppSettings.plist", "644"});
    all_items.push_back({src / "script", base + "/Contents/Resources/script", "755"});
    all_items.push_back(
        {workspace_root / "vendor/Platypus-5.5.0/MainMenu.nib/keyedobjects.nib",
         base + "/Contents/Resources/MainMenu.nib/keyedobjects.nib", "644"});
    all_items.push_back({workspace_root / "vendor/Platypus-5.5.0/PlatypusDefault.icns",
                         base + "/Contents/Resources/AppIcon.icns", "644"});
  }
  for (const auto& [name, bin] : small_framework_bins) {
    const std::string base = "/System/Library/Frameworks/" + name + ".framework";
    for (const std::string& d : {base, base + "/Versions", base + "/Versions/A"}) {
      hfs_mkdir_p(d);
    }
    all_items.push_back({bin, base + "/Versions/A/" + name, "755"});
    all_items.push_back({bin, base + "/" + name, "755"});
  }
  if (!dyld_bin.empty()) {
    all_items.push_back({dyld_bin, "/usr/lib/dyld", "755"});
  }
  if (!inter_font_dir.empty()) {
    hfs_mkdir_p("/usr/share/fonts");
    hfs_mkdir_p("/usr/share/fonts/inter");
    for (const char* f : {"Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf",
                          "Inter-Bold.ttf"}) {
      all_items.push_back(
          {inter_font_dir / f, std::string("/usr/share/fonts/inter/") + f, "644"});
    }
    if (!inter_license.empty()) {
      hfs_mkdir_p("/usr/share/licenses");
      hfs_mkdir_p("/usr/share/licenses/inter");
      all_items.push_back({inter_license, "/usr/share/licenses/inter/LICENSE.txt", "644"});
    }
  }
  for (const auto& item : all_items) {
    if (item.src.empty() || !fs::exists(item.src)) {
      std::cerr << "Skipping absent optional resource: " << item.src << "\n";
      if (!item.src.empty() && item.src.string().find((workspace_root / "vendor").string()) != 0) {
        return 1;
      }
      continue;
    }
    if (RunCommand({hfs_tool.string(), img.string(), "add", item.src.string(),
                    item.dst}) != 0 ||
        RunCommand({hfs_tool.string(), img.string(), "chmod", item.mode,
                    item.dst}) != 0) {
      return 1;
    }
  }

  fs::copy_file(img, output_img, fs::copy_options::overwrite_existing);
  fs::remove_all(work);
  std::cout << "Built Darling Embedded ARM64 HFS+ root image: " << output_img
            << "\n";
  return 0;
}
