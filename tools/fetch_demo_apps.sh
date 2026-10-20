#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Restore demo dependencies. Other app bundles are supplied locally.
set -euo pipefail
cd "$(dirname "$0")/.."
fetch_work=$(mktemp -d)
trap 'rm -rf "$fetch_work"' EXIT
curl -fL https://github.com/sveinbjornt/FastDMG/releases/download/1.0.3/FastDMG-1.0.3.zip -o "$fetch_work/fastdmg.zip"
curl -fL https://github.com/sveinbjornt/Platypus/releases/download/v5.5.0/platypus5.5.0.zip -o "$fetch_work/platypus.zip"
(cd "$fetch_work" && sha256sum -c <<'HASHES'
71d0854f7ed483b7e5b9bdad84e93377a617a1b3eff0d52a54fc79149e4f48ae  fastdmg.zip
2fad132e717e6543b41e5e7aeb357e8846baf8c9f3b3cb2919dc0f5eec3de415  platypus.zip
HASHES
)
mkdir -p vendor
unzip -q -o "$fetch_work/fastdmg.zip" -d vendor
unzip -q "$fetch_work/platypus.zip" -d "$fetch_work/platypus"
platypus_resources="$fetch_work/platypus/Platypus.app/Contents/Resources"
mkdir -p vendor/Platypus-5.5.0
base64 -d "$platypus_resources/ScriptExec.b64" > vendor/Platypus-5.5.0/ScriptExec
chmod +x vendor/Platypus-5.5.0/ScriptExec
cp -r "$platypus_resources/MainMenu.nib" vendor/Platypus-5.5.0/
cp "$platypus_resources/PlatypusDefault.icns" "$platypus_resources/License.html" vendor/Platypus-5.5.0/
