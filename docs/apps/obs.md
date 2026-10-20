# OBS

Current snapshot: 2026-10-20 (UTC).

This bundle is **absent from the current vendor inventory**. Earlier launch claims and symbol totals are not current measurements. No fresh screenshot can be attributed to it.

## Remaining work

1. Vendor the complete bundle: `Contents/Frameworks/Qt*.framework`, `libobs.framework`, `obs-frontend-api`, plug-ins (`Contents/PlugIns`), `Resources/data`.
1. Then the same Qt `cocoa` requirements as LINE.app (AppKit, OpenGL or Metal for the preview, CoreText), plus AVFoundation/CoreMediaIO capture, CoreAudio, IOKit, DiskArbitration, `libcurl`.
1. For a first boot, Qt `offscreen` and OBS's `--disable-shutdown-check` / no-capture-source profile.

[Complete current survey](current-status.md).
