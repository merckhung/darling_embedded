# SparkleUpdater

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Codex.app/Contents/Frameworks/Sparkle.framework/Updater.app`.
- Observation: **exited without a window**.
- Staging: complete bundle copy.
- Original regular-file size: 0.3 MiB (symlinks excluded).
- Local bundle version: `2.9.1`.
- Evidence: [screenshot](../../docs/screenshots/apps/updater-04b0da8f.png), [launch log](../../docs/app-results/updater-04b0da8f.log), [direct-import report](../../docs/app-results/updater-04b0da8f-imports.txt).

- Source: `vendor/Codex.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app`.
- Observation: **exited without a window**.
- Staging: complete bundle copy.
- Original regular-file size: 0.3 MiB (symlinks excluded).
- Local bundle version: `2.9.1`.
- Evidence: [screenshot](../../docs/screenshots/apps/updater-e9ab72fa.png), [launch log](../../docs/app-results/updater-e9ab72fa.log), [direct-import report](../../docs/app-results/updater-e9ab72fa-imports.txt).

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Remove both workarounds: start the updater the way Sparkle's `Autoupdate`/installer launcher does, with real arguments.
1. `NSXPCConnection initWithMachServiceName:` to a real (or loopback) Mach service; `NSUserDefaults initWithSuiteName:`; `-[NSBundle privateFrameworksURL]`, `isEqualTo:`; `-[NSWorkspace iconForFile:]`; `-[NSApplication activate]`; `-[NSWindowController setShouldCascadeWindows:]`.

[Complete current survey](current-status.md).
