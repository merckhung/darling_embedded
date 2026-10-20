# Codex

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Codex.app`.
- Observation: **exited without a window**.
- Staging: launcher, bundled Mach-O images and selected resources (partial bundle).
- Original regular-file size: 1307.1 MiB (symlinks excluded).
- Prepared Mach-O images: 7; omitted native images: 10.
- Local bundle version: `26.623.101652`.
- Evidence: [screenshot](../../docs/screenshots/apps/codex-80f219f3.png), [launch log](../../docs/app-results/codex-80f219f3.log), [direct-import report](../../docs/app-results/codex-80f219f3-imports.txt).

First recorded diagnostic:

```text
dlopen /Applications/codex-80f219f3/Codex.app/Contents/MacOS/../Frameworks/Codex Framework.framework/Versions/149.0.7827.197/Codex Framework: cannot open native library: /System/Library/Frameworks/Accelerate.framework/Versions/A/Accelerate.XNU_EXC: exc=10 codes=0x6000000 0x0
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. **First milestone:** run `Contents/Resources/codex` (Rust CLI) in the guest. It needs libSystem, networking (DNS/TLS), `Security` trust evaluation and the Keychain for sign-in.
1. Use a disk-backed root for the complete bundle and writable application data.
1. Everything listed for Claude.app (CFRunLoop + Mach rendezvous, QuartzCore/IOSurface presentation, AppKit, CoreText, CoreGraphics, Security, IOKit, SystemConfiguration, media stubs).
1. Helpers in this framework include `Codex (Service).app`, `Codex (Alerts).app`, `app_mode_loader` and `web_app_shortcut_copier`. The Service/Alerts helpers use XPC/UserNotifications.

[Complete current survey](current-status.md).
