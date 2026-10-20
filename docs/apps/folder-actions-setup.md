# Folder Actions Setup

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/CoreServices/Applications/Folder Actions Setup.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 0.7 MiB (symlinks excluded).
- Local bundle version: `1.2`.
- Evidence: [screenshot](../../docs/screenshots/apps/folder-actions-setup-17e4aad7.png), [launch log](../../docs/app-results/folder-actions-setup-17e4aad7.log), [direct-import report](../../docs/app-results/folder-actions-setup-17e4aad7-imports.txt).

First recorded diagnostic:

```text
[ObjC] Method not found: [NSObject automationAppLaunched]
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. `FolderActionsKit` stub (dispatcher and automation hooks: `sharedDispatcher`, `automationAppLaunched`).
1. AppKit: `-[NSSplitView arrangedSubviews]`, `setClipsToBounds:`, `-[NSSegmentedControl setEnabled:forSegment:]`.
1. `libDiagnosticMessagesClient` (absent) can be a stub.

[Complete current survey](current-status.md).
