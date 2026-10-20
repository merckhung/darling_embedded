# Digital Color Meter

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/Applications/Utilities/Digital Color Meter.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 0.8 MiB (symlinks excluded).
- Local bundle version: `6.11`.
- Evidence: [screenshot](../../docs/screenshots/apps/digital-color-meter-f4fd3e7f.png), [launch log](../../docs/app-results/digital-color-meter-f4fd3e7f.log), [direct-import report](../../docs/app-results/digital-color-meter-f4fd3e7f-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _SLSDisplayGetCurrentHeadroom
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Screen capture: `CGWindowListCreateImage` / `ScreenCaptureKit` (`SCScreenshotManager`) on top of `XGetImage` of the root window.
1. `ColorSync` and `SkyLight` stubs: display profile and colour-space queries; `-[NSScreen colorSpace]`.
1. QuartzCore (`EDRLayerView` uses layers), `NSTrackingArea` (`initWithRect:options:owner:userInfo:`, `addTrackingArea:`), `-[NSWindow setFrameUsingName:]`, `setDisplaysWhenScreenProfileChanges:`.
1. Live pointer tracking: deliver mouse-moved events without a button press, plus a timer-driven refresh.

[Complete current survey](current-status.md).
