# Windows App

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Windows App.app`.
- Observation: **exited without a window**.
- Staging: launcher, bundled Mach-O images and selected resources (partial bundle).
- Original regular-file size: 217.7 MiB (symlinks excluded).
- Prepared Mach-O images: 10; omitted native images: 0.
- Local bundle version: `11.4.1`.
- Evidence: [screenshot](../../docs/screenshots/apps/windows-app-b67af608.png), [launch log](../../docs/app-results/windows-app-b67af608.log), [direct-import report](../../docs/app-results/windows-app-b67af608-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: ___gss_c_nt_hostbased_service_oid_desc
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Swift runtime + overlays (`libswiftCore`, Foundation overlay 428, Combine 71) and SwiftUI ; SwiftUI is closed source.
1. WebRTC/VideoToolbox, Metal/MetalKit, CoreAudio, IOSurface, SystemConfiguration, Network, StoreKit, PCSC (smart cards).
1. Mac App Store receipt and XPC services.

[Complete current survey](current-status.md).
