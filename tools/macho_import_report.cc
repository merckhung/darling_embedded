// SPDX-License-Identifier: GPL-3.0-or-later
// Host tool: reports which dylibs and symbols a Mach-O image imports and
// whether each one is provided by a guest root filesystem.
//
// Usage: macho_import_report --root <extracted-rootfs-dir> <image> [<image>...]
//
// Imports are read from LC_DYLD_CHAINED_FIXUPS (or classic LC_DYLD_INFO bind
// opcodes). Exports are read from each dependency's export trie
// (LC_DYLD_EXPORTS_TRIE or LC_DYLD_INFO), following LC_REEXPORT_DYLIB.

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr uint32_t kMagic64 = 0xfeedfacf;
constexpr uint32_t kFatMagic = 0xcafebabe;
constexpr uint32_t kCpuArm64 = 0x0100000c;
constexpr uint32_t kLcReqDyld = 0x80000000;
constexpr uint32_t kLcLoadDylib = 0xc;
constexpr uint32_t kLcLoadWeakDylib = 0x18 | kLcReqDyld;
constexpr uint32_t kLcReexportDylib = 0x1f | kLcReqDyld;
constexpr uint32_t kLcLazyLoadDylib = 0x20;
constexpr uint32_t kLcLoadUpwardDylib = 0x23 | kLcReqDyld;
constexpr uint32_t kLcDyldInfo = 0x22;
constexpr uint32_t kLcDyldInfoOnly = 0x22 | kLcReqDyld;
constexpr uint32_t kLcDyldExportsTrie = 0x33 | kLcReqDyld;
constexpr uint32_t kLcDyldChainedFixups = 0x34 | kLcReqDyld;

uint32_t Rd32(const uint8_t* p) {
  uint32_t v;
  memcpy(&v, p, 4);
  return v;
}
uint32_t Rd32Be(const uint8_t* p) {
  return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) |
         p[3];
}
uint64_t Rd64(const uint8_t* p) {
  uint64_t v;
  memcpy(&v, p, 8);
  return v;
}

uint64_t Uleb(const uint8_t*& p, const uint8_t* end) {
  uint64_t r = 0;
  int shift = 0;
  while (p < end) {
    uint8_t b = *p++;
    r |= uint64_t(b & 0x7f) << shift;
    if (!(b & 0x80)) break;
    shift += 7;
  }
  return r;
}

struct Image {
  std::vector<uint8_t> file;
  size_t base = 0;  // offset of the arm64 slice
  size_t size = 0;
  std::vector<std::string> deps;       // load-command order (ordinal-1)
  std::vector<bool> dep_weak;
  std::vector<std::string> reexports;
  std::vector<std::pair<std::string, int>> imports;  // name, lib ordinal
  std::set<std::string> exports;
};

bool LoadImage(const fs::path& path, Image* img) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return false;
  img->file.assign(std::istreambuf_iterator<char>(in), {});
  const uint8_t* f = img->file.data();
  if (img->file.size() < 32) return false;
  if (Rd32Be(f) == kFatMagic) {
    uint32_t n = Rd32Be(f + 4);
    for (uint32_t i = 0; i < n; ++i) {
      const uint8_t* a = f + 8 + i * 20;
      if (Rd32Be(a) == kCpuArm64) {
        img->base = Rd32Be(a + 8);
        img->size = Rd32Be(a + 12);
      }
    }
    if (!img->size) return false;
  } else {
    img->size = img->file.size();
  }
  const uint8_t* m = f + img->base;
  if (Rd32(m) != kMagic64) return false;
  uint32_t ncmds = Rd32(m + 16);
  const uint8_t* lc = m + 32;
  uint32_t chained_off = 0, chained_size = 0;
  uint32_t bind_off = 0, bind_size = 0, lazy_off = 0, lazy_size = 0,
           weak_off = 0, weak_size = 0, export_off = 0, export_size = 0;
  for (uint32_t i = 0; i < ncmds; ++i) {
    uint32_t cmd = Rd32(lc), sz = Rd32(lc + 4);
    if (cmd == kLcLoadDylib || cmd == kLcLoadWeakDylib || cmd == kLcReexportDylib ||
        cmd == kLcLazyLoadDylib || cmd == kLcLoadUpwardDylib) {
      std::string name(reinterpret_cast<const char*>(lc + Rd32(lc + 8)));
      img->deps.push_back(name);
      img->dep_weak.push_back(cmd == kLcLoadWeakDylib);
      if (cmd == kLcReexportDylib) img->reexports.push_back(name);
    } else if (cmd == kLcDyldChainedFixups) {
      chained_off = Rd32(lc + 8);
      chained_size = Rd32(lc + 12);
    } else if (cmd == kLcDyldExportsTrie) {
      export_off = Rd32(lc + 8);
      export_size = Rd32(lc + 12);
    } else if (cmd == kLcDyldInfo || cmd == kLcDyldInfoOnly) {
      bind_off = Rd32(lc + 16);
      bind_size = Rd32(lc + 20);
      weak_off = Rd32(lc + 24);
      weak_size = Rd32(lc + 28);
      lazy_off = Rd32(lc + 32);
      lazy_size = Rd32(lc + 36);
      export_off = Rd32(lc + 40);
      export_size = Rd32(lc + 44);
    }
    lc += sz;
  }
  // Imports from chained fixups.
  if (chained_size) {
    const uint8_t* h = m + chained_off;
    uint32_t imports_off = Rd32(h + 8), symbols_off = Rd32(h + 12);
    uint32_t count = Rd32(h + 16), fmt = Rd32(h + 20);
    const uint8_t* imp = h + imports_off;
    const char* syms = reinterpret_cast<const char*>(h + symbols_off);
    for (uint32_t i = 0; i < count; ++i) {
      int ord;
      uint32_t name_off;
      if (fmt == 1 || fmt == 2) {
        uint32_t v = Rd32(imp + i * (fmt == 1 ? 4 : 8));
        ord = int8_t(v & 0xff);
        name_off = v >> 9;
      } else {
        uint64_t v = Rd64(imp + i * 16);
        ord = int16_t(v & 0xffff);
        name_off = uint32_t(v >> 32);
      }
      img->imports.push_back({syms + name_off, ord});
    }
  }
  // Imports from classic bind opcodes.
  auto parse_binds = [&](uint32_t off, uint32_t size) {
    const uint8_t* p = m + off;
    const uint8_t* end = p + size;
    int ord = 0;
    while (p < end) {
      uint8_t b = *p++;
      uint8_t op = b & 0xf0, imm = b & 0x0f;
      switch (op) {
        case 0x10: ord = imm; break;                         // ORDINAL_IMM
        case 0x20: ord = int(Uleb(p, end)); break;           // ORDINAL_ULEB
        case 0x30: ord = imm ? int(int8_t(0xf0 | imm)) : 0; break;  // SPECIAL
        case 0x40: {                                         // SYMBOL
          std::string name(reinterpret_cast<const char*>(p));
          p += name.size() + 1;
          img->imports.push_back({name, ord});
          break;
        }
        case 0x50: break;                                    // TYPE_IMM
        case 0x60: { uint64_t t = Uleb(p, end); (void)t; break; }  // ADDEND
        case 0x70: Uleb(p, end); break;                      // SEG_OFFSET
        case 0x80: Uleb(p, end); break;                      // ADD_ADDR
        case 0x90: break;                                    // DO_BIND
        case 0xA0: Uleb(p, end); break;                      // DO_BIND_ADD_ULEB
        case 0xB0: break;                                    // DO_BIND_ADD_SCALED
        case 0xC0: Uleb(p, end); Uleb(p, end); break;        // ULEB_TIMES_SKIP
        default: break;
      }
    }
  };
  if (!chained_size) {
    if (bind_size) parse_binds(bind_off, bind_size);
    if (lazy_size) parse_binds(lazy_off, lazy_size);
    if (weak_size) parse_binds(weak_off, weak_size);
  }
  // Exports trie.
  if (export_size) {
    const uint8_t* start = m + export_off;
    const uint8_t* end = start + export_size;
    std::vector<std::pair<uint64_t, std::string>> stack = {{0, ""}};
    std::set<uint64_t> seen;
    while (!stack.empty()) {
      auto [off, prefix] = stack.back();
      stack.pop_back();
      if (off >= export_size || !seen.insert(off).second) continue;
      const uint8_t* p = start + off;
      uint64_t term = Uleb(p, end);
      if (term) img->exports.insert(prefix);
      p += term;
      if (p >= end) continue;
      uint8_t children = *p++;
      for (uint8_t c = 0; c < children && p < end; ++c) {
        std::string edge(reinterpret_cast<const char*>(p));
        p += edge.size() + 1;
        uint64_t child = Uleb(p, end);
        stack.push_back({child, prefix + edge});
      }
    }
  }
  return true;
}

struct Root {
  fs::path dir;
  std::map<std::string, Image> cache;
  std::map<std::string, bool> present;

  // All symbols exported by `install_name`, following re-exports.
  void CollectExports(const std::string& install_name, std::set<std::string>* out,
                      int depth = 0) {
    if (depth > 8) return;
    auto it = cache.find(install_name);
    if (it == cache.end()) {
      Image img;
      fs::path p = dir / install_name.substr(install_name[0] == '/' ? 1 : 0);
      bool ok = fs::exists(p) && LoadImage(p, &img);
      present[install_name] = ok;
      it = cache.emplace(install_name, std::move(img)).first;
    }
    out->insert(it->second.exports.begin(), it->second.exports.end());
    std::vector<std::string> re = it->second.reexports;
    for (const auto& r : re) CollectExports(r, out, depth + 1);
  }
};

}  // namespace

int main(int argc, char** argv) {
  Root root;
  std::vector<fs::path> images;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--root" && i + 1 < argc) {
      root.dir = argv[++i];
    } else {
      images.push_back(a);
    }
  }
  if (root.dir.empty() || images.empty()) {
    std::cerr << "usage: macho_import_report --root <rootfs> <image>...\n";
    return 2;
  }
  for (const auto& path : images) {
    Image img;
    if (!LoadImage(path, &img)) {
      std::cerr << "cannot parse arm64 Mach-O: " << path << "\n";
      return 1;
    }
    std::cout << "==== " << path.filename().string() << " ====\n";
    std::cout << "Linked dylibs: " << img.deps.size()
              << ", imported symbols: " << img.imports.size() << "\n\n";
    size_t total_ok = 0, total = 0, libs_missing = 0;
    std::cout << "  present  provided/imported  library\n";
    for (size_t d = 0; d < img.deps.size(); ++d) {
      const std::string& lib = img.deps[d];
      size_t n = 0, ok = 0;
      std::vector<std::string> missing;
      bool self_ref = lib.rfind("@", 0) == 0;
      std::set<std::string> exports;
      if (!self_ref) root.CollectExports(lib, &exports);
      bool present = !self_ref && root.present[lib];
      for (const auto& [sym, ord] : img.imports) {
        if (ord != int(d + 1)) continue;
        ++n;
        if (exports.count(sym)) {
          ++ok;
        } else if (missing.size() < 6) {
          missing.push_back(sym);
        }
      }
      if (self_ref) continue;
      if (!present) ++libs_missing;
      total += n;
      total_ok += ok;
      std::cout << "  " << (present ? "yes" : "NO ") << "      " << ok << "/" << n
                << "\t" << lib << (img.dep_weak[d] ? " (weak)" : "") << "\n";
      if (present && ok < n) {
        std::cout << "             e.g. missing:";
        for (const auto& s : missing) std::cout << " " << s;
        std::cout << "\n";
      }
    }
    std::cout << "\nSummary for " << path.filename().string() << ": "
              << libs_missing << " of " << img.deps.size()
              << " linked libraries are absent from the guest root; "
              << total_ok << " of " << total
              << " imported symbols are provided ("
              << (total ? (100.0 * double(total_ok) / double(total)) : 0.0)
              << "%).\n\n";
  }
  return 0;
}
