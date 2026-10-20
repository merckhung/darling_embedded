# AppleScript Utility

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/CoreServices/AppleScript Utility.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 1.7 MiB (symlinks excluded).
- Local bundle version: `1.1.2`.
- Evidence: [screenshot](../../docs/screenshots/apps/applescript-utility-d9f8e65f.png), [launch log](../../docs/app-results/applescript-utility-d9f8e65f.log), [direct-import report](../../docs/app-results/applescript-utility-d9f8e65f-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _AESend
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Implement `+[NSObject instancesRespondToSelector:]` in the runtime (logged as missing).
1. Provide Launch Services queries used to fill the *Default Script Editor* popup (`LSCopyApplicationURLsForURL`, `LSCopyItemInfoForURL`, `_LSCopyApplicationArray`) from the `/Applications` bundles.
1. Stub `TCC.framework` (accessibility / automation permission checks) and `AXIsProcessTrusted` so *Enable GUI Scripting* reflects a consistent state.
1. Carbon Apple Event APIs (`AECreateAppleEvent`, `AESend`, …) are unresolved; the Script-menu options need at least no-op implementations.
1. Labels are right-aligned into frames sized for SF Pro; check text metrics with Inter so that no label is clipped.

[Complete current survey](current-status.md).
