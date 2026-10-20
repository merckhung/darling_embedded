# Third-Party Notices & License Compatibility

`darling_embedded` is distributed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)** (see [`LICENSE`](LICENSE)) to align with **Darling** (`https://github.com/darlinghq/darling`), while preserving all upstream notices and separation rules for **XNU/Darwin** (`https://github.com/merckhung/darwin_embedded`).

---

## 1. Darling (`https://github.com/darlinghq/darling`)
- **Pinned Commit**: `60ba801decee7a00782f74f6be4c8ffb013f79ff`
- **License**: `GPL-3.0-or-later` (with components under `BSD-3-Clause` such as `src/tools/sw_vers.c` by Finlay Dobbie).
- **Usage**: Fetched via Bazel repository rule `@darling` (`bazel/repositories.bzl`). Only `src/tools/sw_vers.c` is compiled into the image. The in-tree Foundation/AppKit/libobjc in `darling/` are an independent implementation; no Darling or Cocotron framework code is used.

## 2. Darwin Embedded (`https://github.com/merckhung/darwin_embedded`)
- **Pinned Commit**: `de354247bb098c3549e132938e97bda65d8a4f57`
- **Orchestration & Native Bootloader/Scripts License**: `BSD-2-Clause` (Copyright (c) 2026 Merck Hung and contributors; PureDarwin Project).
- **Apple XNU Kernel & Core Darwin Libraries**:
  - **XNU `12377.121.6`** and **Darwin `25.5.0`** (`Libc`, `libmalloc`, `libpthread`, `libplatform`, `IOStorageFamily`, `hfs`, `HFSEncodings`) are licensed under the **Apple Public Source License v2.0 (`APSL-2.0`)**.
  - **Compatibility Note**: Under **GPLv3 Section 1 ("System Libraries")**, the kernel (`XNU`) and core operating system runtime libraries (`dyld`, `libSystem.B.dylib`) constitute the Major Components and System Libraries of the Darwin operating system on which the Darling userland and Mac OS X applications execute as separate Mach-O user processes across standard syscall/Mach IPC and dynamic-linking boundaries.
- **Graphical Base System Components (in `@darwin_embedded`)**:
  - `Xorg`, `libX11`, `pixman`, `cairo`, `freetype`, `fontconfig`, `harfbuzz`, `pango`: `MIT` / `FTL` / `MPL-1.1`
  - `glib`, `gtk3`, `libxfce4util`, `libxfce4ui`, `xfconf`, `xfce4-panel`, `xfce4-session`: `LGPL-2.0-or-later` / `GPL-2.0-or-later`
  - `xfwm4`, `xfdesktop`, `xfce4-terminal`, `busybox`: `GPL-2.0-or-later` / `GPL-2.0-only` (executed strictly as separate, unmodified user-space processes on the HFS+ root filesystem).
- **Modified dyld**: `darling/dyld/` is a copy of darwin_embedded's `userland/native/dyld` (`BSD-2-Clause`) with chained-fixup and export-trie support added; it keeps its original license.

## 3. LLVM libunwind (`src/Applications/cxx/libunwind/20.1.8` in darwin_embedded)
- **License**: `Apache-2.0 WITH LLVM-exception`.
- **Usage**: Unmodified sources compiled into `/usr/lib/system/libsystem_native_blocks.dylib` to provide the `_Unwind_*` ABI.

## 4. Inter 4.1 (user-interface font)
- **Author**: Rasmus Andersson and the Inter project authors (`https://rsms.me/inter`).
- **License**: SIL Open Font License 1.1 (`OFL-1.1`); the license text is installed as `/usr/share/licenses/inter/LICENSE.txt`.
- **Source**: `https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip` (sha256 `9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e`), fetched by the Bazel repository `@inter_font`.
- **Usage**: The unmodified static `Inter-Regular/Medium/SemiBold/Bold.ttf` files are installed in `/usr/share/fonts/inter` and used as the system font by AppKit, the desktop shell and (via `/etc/fonts/local.conf`) other X clients.
