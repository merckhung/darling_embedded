# Bluetooth File Exchange

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/Applications/Utilities/Bluetooth File Exchange.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 1.2 MiB (symlinks excluded).
- Local bundle version: `9.0`.
- Evidence: [screenshot](../../docs/screenshots/apps/bluetooth-file-exchange-3d3f28a2.png), [launch log](../../docs/app-results/bluetooth-file-exchange-3d3f28a2.log), [direct-import report](../../docs/app-results/bluetooth-file-exchange-3d3f28a2-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _AnalyticsSendEventLazy
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Remove the `FileTransferClientWindow` special case once the real startup path works.
1. Provide `IOBluetooth`/`IOBluetoothUI` frameworks: the device selector (`IOBluetoothDeviceSelectorController`), `IOBluetoothValidateHardwareWithDescription` and the OBEX file-transfer classes. Without Bluetooth hardware they should report *no Bluetooth hardware* the way macOS does.
1. `CoreAnalytics` (`AnalyticsSendEventLazy`) can be a no-op stub.
1. AppKit: `NSBeginAlertSheet`, `NSGetAlertPanel`/`NSReleaseAlertPanel` (unresolved imports), `-[NSMutableArray initWithCapacity:]` (logged).

[Complete current survey](current-status.md).
