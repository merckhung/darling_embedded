// SPDX-License-Identifier: GPL-3.0-or-later
// Host C++20 Mach-O 64-bit ad-hoc SHA-256 CodeDirectory/SuperBlob signer & auditor.

#include <openssl/sha.h>

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

uint32_t ReadLE32(const uint8_t* p) {
  uint32_t v;
  std::memcpy(&v, p, sizeof(v));
  return v;
}

uint64_t ReadLE64(const uint8_t* p) {
  uint64_t v;
  std::memcpy(&v, p, sizeof(v));
  return v;
}

void WriteLE32(uint8_t* p, uint32_t v) { std::memcpy(p, &v, sizeof(v)); }

void WriteLE64(uint8_t* p, uint64_t v) { std::memcpy(p, &v, sizeof(v)); }

uint32_t ReadBE32(const uint8_t* p) {
  return (static_cast<uint32_t>(p[0]) << 24) |
         (static_cast<uint32_t>(p[1]) << 16) |
         (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
}

void AppendBE32(std::vector<uint8_t>& out, uint32_t v) {
  out.push_back(static_cast<uint8_t>((v >> 24) & 0xff));
  out.push_back(static_cast<uint8_t>((v >> 16) & 0xff));
  out.push_back(static_cast<uint8_t>((v >> 8) & 0xff));
  out.push_back(static_cast<uint8_t>(v & 0xff));
}

void AppendBE64(std::vector<uint8_t>& out, uint64_t v) {
  AppendBE32(out, static_cast<uint32_t>(v >> 32));
  AppendBE32(out, static_cast<uint32_t>(v & 0xffffffffULL));
}

void RewriteArm64ePacInstructions(uint8_t* buf, size_t len) {
  for (size_t off = 0; off + 4 <= len; off += 4) {
    uint32_t insn = ReadLE32(buf + off);
    uint32_t repl = insn;
    if (insn == 0xd503237fU || insn == 0xd503233fU || insn == 0xd50323ffU ||
        insn == 0xd50323bfU || (insn & 0xfffffd1fU) == 0xd503211fU) {
      repl = 0xd503201fU;  // nop (HINT PAC/AUT/XPAC)
    } else if ((insn & 0xffff8000U) == 0xdac10000U) {
      repl = 0xd503201fU;  // nop (1-source PAC*/AUT*/XPAC*)
    } else if ((insn & 0xffe0fc00U) == 0x9ac03000U) {
      repl = 0xd2800000U | (insn & 0x1fU);  // pacga Xd, Xn, Xm -> mov Xd, #0
    } else if (insn == 0xd65f0bffU || insn == 0xd65f0fffU) {
      repl = 0xd65f03c0U;  // retaa / retab -> ret
    } else if ((insn & 0xfedff800U) == 0xd61f0800U) {
      uint32_t rn_bits = insn & 0x3e0U;
      if ((insn & 0x00200000U) == 0) {
        repl = 0xd61f0000U | rn_bits;  // braa / brab / braaz / brabz -> br Xn
      } else {
        repl = 0xd63f0000U | rn_bits;  // blraa / blrab / blraaz / blrabz -> blr Xn
      }
    } else if (insn == 0xd4388e20U) {
      repl = 0xd503201fU;  // brk #0xc471 (PAC auth trap) -> nop
    }
    if (repl != insn) {
      WriteLE32(buf + off, repl);
    }
  }
}

void SignMachOFile(const fs::path& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    throw std::runtime_error("Cannot open Mach-O file: " + path.string());
  }
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(in)),
                            std::istreambuf_iterator<char>());
  in.close();

  // If this is a Universal (Fat) binary, extract the ARM64 or ARM64e slice.
  if (data.size() >= 8 && ReadBE32(data.data()) == 0xcafebabeU) {
    uint32_t narch = ReadBE32(data.data() + 4);
    if (8ULL + static_cast<uint64_t>(narch) * 20ULL > data.size()) {
      throw std::runtime_error("Truncated fat header in: " + path.string());
    }
    uint32_t chosen_off = 0;
    uint32_t chosen_size = 0;
    bool found_exact_arm64 = false;
    for (uint32_t i = 0; i < narch; ++i) {
      const uint8_t* arch = data.data() + 8 + i * 20;
      uint32_t cputype = ReadBE32(arch);
      uint32_t cpusubtype = ReadBE32(arch + 4);
      uint32_t slice_off = ReadBE32(arch + 8);
      uint32_t slice_size = ReadBE32(arch + 12);
      if (cputype == 0x0100000cU &&
          static_cast<uint64_t>(slice_off) + slice_size <= data.size()) {
        if ((cpusubtype & 0xffU) == 0) {
          chosen_off = slice_off;
          chosen_size = slice_size;
          found_exact_arm64 = true;
          break;
        }
        if (!found_exact_arm64 && chosen_size == 0) {
          chosen_off = slice_off;
          chosen_size = slice_size;
        }
      }
    }
    if (chosen_size == 0) {
      throw std::runtime_error("No ARM64/ARM64e slice in fat Mach-O: " +
                               path.string());
    }
    data = std::vector<uint8_t>(data.begin() + chosen_off,
                                data.begin() + chosen_off + chosen_size);
  }

  if (data.size() < 32 || ReadLE32(data.data()) != 0xfeedfacfU) {
    throw std::runtime_error("Expected little-endian 64-bit Mach-O: " + path.string());
  }

  // Normalize ARM64e cpusubtype (e.g. 0x80000002) to standard ARM64 (0).
  uint32_t cpusubtype = ReadLE32(data.data() + 8);
  if (cpusubtype != 0) {
    WriteLE32(data.data() + 8, 0);
  }

  uint32_t filetype = ReadLE32(data.data() + 12);
  uint32_t ncmds = ReadLE32(data.data() + 16);
  uint32_t sizeofcmds = ReadLE32(data.data() + 20);
  if ((filetype != 2 && filetype != 6 && filetype != 7 && filetype != 8) ||
      sizeofcmds > data.size() - 32) {
    throw std::runtime_error("Invalid Mach-O filetype or load commands: " + path.string());
  }

  size_t sig_cmd_off = 0;
  size_t linkedit_off = 0;
  size_t text_off = 0;
  size_t cursor = 32;
  for (uint32_t i = 0; i < ncmds; ++i) {
    if (cursor + 8 > 32 + sizeofcmds) {
      throw std::runtime_error("Truncated Mach-O load command");
    }
    uint32_t cmd = ReadLE32(data.data() + cursor);
    uint32_t cmdsize = ReadLE32(data.data() + cursor + 4);
    if (cmdsize < 8 || (cmdsize % 8) != 0 || cursor + cmdsize > 32 + sizeofcmds) {
      throw std::runtime_error("Invalid Mach-O load command size");
    }
    if (cmd == 0x1dU) {  // LC_CODE_SIGNATURE
      if (cmdsize != 16 || sig_cmd_off != 0) {
        throw std::runtime_error("Invalid or duplicate LC_CODE_SIGNATURE");
      }
      sig_cmd_off = cursor;
    } else if (cmd == 0x19U) {  // LC_SEGMENT_64
      if (cmdsize < 72) {
        throw std::runtime_error("Truncated LC_SEGMENT_64 command");
      }
      char segname[17] = {0};
      std::memcpy(segname, data.data() + cursor + 8, 16);
      std::string name(segname);
      if (name == "__LINKEDIT") {
        linkedit_off = cursor;
      } else if (name == "__TEXT") {
        text_off = cursor;
      }
      uint32_t nsects = ReadLE32(data.data() + cursor + 64);
      if (72ULL + static_cast<uint64_t>(nsects) * 80ULL <= cmdsize) {
        for (uint32_t s = 0; s < nsects; ++s) {
          size_t sec_off = cursor + 72 + s * 80;
          uint64_t sect_size = ReadLE64(data.data() + sec_off + 40);
          uint32_t sect_fileoff = ReadLE32(data.data() + sec_off + 48);
          uint32_t sect_flags = ReadLE32(data.data() + sec_off + 64);
          if ((sect_flags & 0x80000400U) != 0 && sect_size >= 4 &&
              static_cast<uint64_t>(sect_fileoff) + sect_size <= data.size()) {
            RewriteArm64ePacInstructions(data.data() + sect_fileoff,
                                         static_cast<size_t>(sect_size));
          }
        }
      }
    }
    cursor += cmdsize;
  }

  if (cursor != 32 + sizeofcmds || !sig_cmd_off || !linkedit_off || !text_off) {
    throw std::runtime_error("Missing LC_CODE_SIGNATURE, __TEXT, or __LINKEDIT in " +
                             path.string());
  }

  uint32_t dataoff = ReadLE32(data.data() + sig_cmd_off + 8);
  uint32_t old_datasize = ReadLE32(data.data() + sig_cmd_off + 12);
  uint64_t link_fileoff = ReadLE64(data.data() + linkedit_off + 40);
  if (dataoff < 32 + sizeofcmds || (dataoff % 16) != 0 ||
      static_cast<size_t>(dataoff) + old_datasize > data.size() ||
      dataoff < link_fileoff) {
    throw std::runtime_error("Code signature must be the final aligned region in " +
                             path.string());
  }

  data.resize(dataoff);
  std::string ident = path.filename().string();
  std::vector<uint8_t> ident_bytes(ident.begin(), ident.end());
  ident_bytes.push_back(0);

  uint32_t slots = (dataoff + 4095U) / 4096U;
  uint32_t hash_offset = static_cast<uint32_t>(88U + ident_bytes.size());
  uint32_t directory_size = hash_offset + slots * 32U;
  uint32_t signature_size = 20U + directory_size;
  uint64_t end = static_cast<uint64_t>(dataoff) + signature_size;

  WriteLE32(data.data() + sig_cmd_off + 12, signature_size);
  WriteLE64(data.data() + linkedit_off + 48, end - link_fileoff);
  WriteLE64(data.data() + linkedit_off + 32, (end - link_fileoff + 16383ULL) & ~16383ULL);

  uint64_t text_fileoff = ReadLE64(data.data() + text_off + 40);
  uint64_t text_filesize = ReadLE64(data.data() + text_off + 48);

  std::vector<uint8_t> blob;
  blob.reserve(signature_size);
  // SuperBlob header
  AppendBE32(blob, 0xfade0cc0U);
  AppendBE32(blob, signature_size);
  AppendBE32(blob, 1U);
  AppendBE32(blob, 0U);
  AppendBE32(blob, 20U);

  // CodeDirectory (v0x20400)
  AppendBE32(blob, 0xfade0c02U);
  AppendBE32(blob, directory_size);
  AppendBE32(blob, 0x20400U);
  AppendBE32(blob, 0x20302U);  // CS_ADHOC | CS_HARD | CS_KILL | CS_LINKER_SIGNED
  AppendBE32(blob, hash_offset);
  AppendBE32(blob, 88U);
  AppendBE32(blob, 0U);
  AppendBE32(blob, slots);
  AppendBE32(blob, dataoff);
  blob.push_back(32U);  // hashSize (SHA-256)
  blob.push_back(2U);   // hashType (CS_HASHTYPE_SHA256)
  blob.push_back(0U);   // platform
  blob.push_back(12U);  // pageSize (2^12 = 4096)
  AppendBE32(blob, 0U);
  AppendBE32(blob, 0U);
  AppendBE32(blob, 0U);
  AppendBE32(blob, 0U);
  AppendBE64(blob, 0ULL);
  AppendBE64(blob, text_fileoff);
  AppendBE64(blob, text_filesize);
  AppendBE64(blob, filetype == 2 ? 1ULL : 0ULL);

  blob.insert(blob.end(), ident_bytes.begin(), ident_bytes.end());

  for (uint32_t start = 0; start < dataoff; start += 4096U) {
    size_t chunk_len = std::min<size_t>(4096U, dataoff - start);
    uint8_t digest[SHA256_DIGEST_LENGTH];
    SHA256(data.data() + start, chunk_len, digest);
    blob.insert(blob.end(), digest, digest + SHA256_DIGEST_LENGTH);
  }

  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) {
    throw std::runtime_error("Cannot write signed Mach-O: " + path.string());
  }
  out.write(reinterpret_cast<const char*>(data.data()),
            static_cast<std::streamsize>(data.size()));
  out.write(reinterpret_cast<const char*>(blob.data()),
            static_cast<std::streamsize>(blob.size()));
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::cerr << "Usage: " << argv[0] << " <macho-file> [macho-file...]\n";
    return 1;
  }
  try {
    for (int i = 1; i < argc; ++i) {
      SignMachOFile(argv[i]);
    }
  } catch (const std::exception& e) {
    std::cerr << "macho_sign error: " << e.what() << "\n";
    return 1;
  }
  return 0;
}
