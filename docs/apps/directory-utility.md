# Directory Utility

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/CoreServices/Applications/Directory Utility.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 3.0 MiB (symlinks excluded).
- Local bundle version: `7.0`.
- Evidence: [screenshot](../../docs/screenshots/apps/directory-utility-f3ff94c0.png), [launch log](../../docs/app-results/directory-utility-f3ff94c0.log), [direct-import report](../../docs/app-results/directory-utility-f3ff94c0-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _select
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Replace the *Search Policy* label special case: read the item label from the nib/strings tables.
1. OpenDirectory : `ODSession`, `ODNode`, `ODQuery` returning the local node (`/Local/Default`) and its record types.
1. SystemConfiguration : `SCDynamicStore*`, `SCPreferences*`, `SCNetworkSet*`.
1. SecurityFoundation/SecurityInterface (`SFAuthorizationView`: `setAuthorizationRights:`, `authorization`, `updateStatus:`), ServiceManagement, Carbon.
1. AppKit gaps logged at runtime: `-[NSWindow setContentMinSize:]`, `setDocumentEdited:`, `setToolbarStyle:`, `setShowsToolbarButton:`, `standardWindowButton:`; `-[NSPopUpButton synchronizeTitleAndSelectedItem]`; `-[NSTableColumn setDataCell:]`; `-[NSMutableArray sortUsingFunction:context:]`; `-[NSApplication isActive]`; `NSButtonCell` setters on cells.
1. Layout: the bottom row (lock button, *Apply*) is clipped at the window edge; window content size and autoresizing need checking.

[Complete current survey](current-status.md).
