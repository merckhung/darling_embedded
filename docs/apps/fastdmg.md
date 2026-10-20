# FastDMG

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/FastDMG.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 1.3 MiB (symlinks excluded).
- Local bundle version: `1.0.3`.
- Evidence: [screenshot](../../docs/screenshots/apps/fastdmg-2bbdfcf2.png), [launch log](../../docs/app-results/fastdmg-2bbdfcf2.log), [direct-import report](../../docs/app-results/fastdmg-2bbdfcf2-imports.txt).

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Mounting a disk image (`hdiutil attach` via `NSTask`) needs a `hdiutil`/DiskImages implementation in the guest; opening a `.dmg` from the Finder or the Dock is the next functional step.
1. Dock / Finder document opening: `application:openFiles:` delivery from `/usr/bin/open <file>`.

[Complete current survey](current-status.md).
