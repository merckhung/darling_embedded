# LINE

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/LINE.app`.
- Observation: **no window within observation period**.
- Staging: launcher, bundled Mach-O images and selected resources (partial bundle).
- Original regular-file size: 629.1 MiB (symlinks excluded).
- Prepared Mach-O images: 41; omitted native images: 1.
- Local bundle version: `26.5.0`.
- Evidence: [screenshot](../../docs/screenshots/apps/line-10fe9d5c.png), [launch log](../../docs/app-results/line-10fe9d5c.log), [direct-import report](../../docs/app-results/line-10fe9d5c-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: __ZN7skottie6Canvas12initWithDataE10QByteArray
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Complete libc++/libc++abi exports in the guest (missing exports, e.g. `std::__1` string/stream symbols, `operator new`).
1. Swift runtime: `libswiftCore` plus overlays (Foundation, Dispatch, …) from the open-source Swift toolchain, or reimplemented.
1. Qt `cocoa` QPA needs AppKit (`NSView` layer hosting, `NSOpenGLContext`/OpenGL, `CAMetalLayer`), CoreText, CoreGraphics, CoreVideo, IOSurface. Alternatively run with `QT_QPA_PLATFORM=offscreen` for a first boot.
1. Media: AVFoundation, CoreMedia, VideoToolbox, AudioToolbox (calls); can be unavailable stubs initially.
1. Mac App Store receipt (`_MASReceipt`) validation and the XPC services in `Contents/XPCServices`.
1. Use a disk-backed root for the complete bundle and writable application data.

[Complete current survey](current-status.md).
