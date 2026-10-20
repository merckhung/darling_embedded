# Image Capture

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/Applications/Image Capture.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 2.9 MiB (symlinks excluded).
- Local bundle version: `8.0`.
- Evidence: [screenshot](../../docs/screenshots/apps/image-capture-261900a9.png), [launch log](../../docs/app-results/image-capture-261900a9.log), [direct-import report](../../docs/app-results/image-capture-261900a9-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _NSToolbarFlexibleSpaceItemIdentifier
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Provide `ImageCaptureCore` (`ICDeviceBrowser` reporting no devices) and `Quartz`/ImageKit view classes so the nib uses the real classes.
1. `ICADevices` stub.

[Complete current survey](current-status.md).
