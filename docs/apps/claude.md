# Claude

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Claude.app`.
- Observation: **exited without a window**.
- Staging: launcher, bundled Mach-O images and selected resources (partial bundle).
- Original regular-file size: 713.9 MiB (symlinks excluded).
- Prepared Mach-O images: 15; omitted native images: 0.
- Local bundle version: `1.18286.0`.
- Evidence: [screenshot](../../docs/screenshots/apps/claude-d65561dd.png), [launch log](../../docs/app-results/claude-d65561dd.log), [direct-import report](../../docs/app-results/claude-d65561dd-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _os_unfair_lock_trylock
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. A complete bundle needs more storage than this probe; see the measured size and staging scope above.
1. **CFRunLoop with Mach-port sources**: Chromium's `MessagePumpCFRunLoop`/`MessagePumpNSApplication` depend on real run-loop sources, timers and observers.
1. **Child processes**: helpers (Renderer, GPU, Plugin) are spawned with `posix_spawn` and rendezvous with the browser through Mach ports (`MachPortRendezvous`, bootstrap). This needs launchd bootstrap support in the guest, or `--single-process` (partly supported by Electron).
1. **Presentation**: even the software compositor hands frames to `CALayer` contents (`IOSurface` or `CGImage`). This needs QuartzCore (`CALayer`, `CATransaction`, `CVDisplayLink`) and `IOSurface` mapped onto X11 windows.
1. **AppKit**: incomplete export/API coverage; Chromium's `NSWindow`/`NSView` subclasses, layer hosting, `NSEvent` with `NSTextInputClient`, `NSTrackingArea`, `NSScreen`, cursors, drag and drop, menus.
1. **CoreText** (absent): Skia on macOS loads and shapes fonts with CoreText; implement it on FreeType/HarfBuzz.
1. **CoreGraphics**, **CoreFoundation**, libSystem (Mach, dispatch, xpc, os_log).
1. **Security**: `SecTrust` evaluation for TLS (CA bundle) and the Keychain used by `safeStorage`.
1. SystemConfiguration, Network/CFNetwork, IOKit (power and idle time), DiskArbitration; media frameworks (CoreAudio, AVFoundation, VideoToolbox, CoreMedia) can start as *unavailable* stubs.
1. Updater frameworks Squirrel/Mantle/ReactiveObjC: keep auto-update disabled or provide the Foundation APIs they use.
1. Node.js side: FSEvents (CoreServices) for `fs.watch`; correct filesystem-event delivery needs functional validation.

[Complete current survey](current-status.md).
