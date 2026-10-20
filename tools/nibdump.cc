// SPDX-License-Identifier: GPL-3.0-or-later
// Host tool: dumps the object graph of a compiled NIBArchive (.nib) file.
// Usage: nibdump <file.nib>

#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

#include "darling/frameworks/nibarchive.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: nibdump <file.nib>\n";
    return 2;
  }
  std::ifstream in(argv[1], std::ios::binary);
  std::vector<uint8_t> buf((std::istreambuf_iterator<char>(in)),
                           std::istreambuf_iterator<char>());
  darling_nib::NibArchive nib;
  if (!darling_nib::ParseNibArchive(buf.data(), buf.size(), &nib)) {
    std::cerr << "not a valid NIBArchive: " << argv[1] << "\n";
    return 1;
  }
  std::cout << "objects=" << nib.object_count << " keys=" << nib.key_count
            << " values=" << nib.value_count << " classes=" << nib.class_count
            << "\n";
  for (uint32_t i = 0; i < nib.object_count; ++i) {
    const auto& o = nib.objects[i];
    std::cout << "#" << i << " " << nib.ClassNameOf(i) << "\n";
    for (uint32_t k = 0; k < o.value_count; ++k) {
      const auto& v = nib.values[o.first_value + k];
      std::string key(nib.keys[v.key_index].ptr, nib.keys[v.key_index].len);
      std::cout << "    " << key << " = ";
      switch (v.type) {
        case darling_nib::kInt8:
        case darling_nib::kInt16:
        case darling_nib::kInt32:
        case darling_nib::kInt64:
          std::cout << v.int_value;
          break;
        case darling_nib::kTrue:
          std::cout << "true";
          break;
        case darling_nib::kFalse:
          std::cout << "false";
          break;
        case darling_nib::kFloat:
        case darling_nib::kDouble:
          std::cout << v.double_value;
          break;
        case darling_nib::kData: {
          bool printable = true;
          for (uint32_t b = 0; b < v.data_len; ++b) {
            uint8_t c = v.data[b];
            if ((c < 0x20 && c != '\n' && c != '\t') || c == 0x7f) {
              printable = false;
              break;
            }
          }
          if (printable) {
            std::cout << '"'
                      << std::string(reinterpret_cast<const char*>(v.data),
                                     v.data_len)
                      << '"';
          } else {
            std::cout << "<data " << v.data_len << " bytes>";
          }
          break;
        }
        case darling_nib::kNil:
          std::cout << "nil";
          break;
        case darling_nib::kObjectRef:
          std::cout << "@" << v.object_ref << " ("
                    << (nib.ClassNameOf(v.object_ref)
                            ? nib.ClassNameOf(v.object_ref)
                            : "?")
                    << ")";
          break;
      }
      std::cout << "\n";
    }
  }
  return 0;
}
