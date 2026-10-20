# Ticket Viewer

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/CoreServices/Applications/Ticket Viewer.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 1.8 MiB (symlinks excluded).
- Local bundle version: `4.1`.
- Evidence: [screenshot](../../docs/screenshots/apps/ticket-viewer-11555a59.png), [launch log](../../docs/app-results/ticket-viewer-11555a59.log), [direct-import report](../../docs/app-results/ticket-viewer-11555a59-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _GSSItemAdd
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Core Data (`NSManagedObjectModel mergedModelFromBundles:`, `NSPersistentStoreCoordinator initWithManagedObjectModel:`, `NSEntityDescription insertNewObjectForEntityForName:inManagedObjectContext:`), at least an in-memory store; `NSSortDescriptor sortDescriptorWithKey:ascending:`.
1. GSS / Heimdal: credential iteration returning no tickets.
1. Table column titles come from the nib's header cells (currently `AutomaticTableColumnIdentifier.0`).

[Complete current survey](current-status.md).
