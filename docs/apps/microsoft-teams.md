# Microsoft Teams

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Microsoft Teams.app`.
- Observation: **exited without a window**.
- Staging: launcher, bundled Mach-O images and selected resources (partial bundle).
- Original regular-file size: 1107.1 MiB (symlinks excluded).
- Prepared Mach-O images: 15; omitted native images: 0.
- Local bundle version: `26261.303.5165.1465`.
- Evidence: [screenshot](../../docs/screenshots/apps/microsoft-teams-6fcb0bf2.png), [launch log](../../docs/app-results/microsoft-teams-6fcb0bf2.log), [direct-import report](../../docs/app-results/microsoft-teams-6fcb0bf2-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _SCNetworkConnectionCreateWithServiceID
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Swift runtime and SwiftUI, AppIntents, Combine. SwiftUI requires a separate UI implementation.
1. libc++, libSystem, Security, IOKit, Foundation, CoreVideo, CoreFoundation.
1. WebView2 (`MSWebView2.framework`) carries the same Chromium requirements as Claude.app: CFRunLoop + Mach rendezvous, QuartzCore/IOSurface presentation, CoreText, AppKit text input.
1. OneAuth (MSAL) sign-in needs the Keychain, `AuthenticationServices` and network trust.
1. Use a disk-backed root for the complete bundle and writable application data.

[Complete current survey](current-status.md).
