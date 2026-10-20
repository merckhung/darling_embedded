# Install Command Line Developer Tools

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/CoreServices/Install Command Line Developer Tools.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 2.3 MiB (symlinks excluded).
- Local bundle version: `2418`.
- Evidence: [screenshot](../../docs/screenshots/apps/install-command-line-developer-tools-37cd490d.png), [launch log](../../docs/app-results/install-command-line-developer-tools-37cd490d.log), [direct-import report](../../docs/app-results/install-command-line-developer-tools-37cd490d-imports.txt).

First recorded diagnostic:

```text
[ObjC] Method not found: [NSApplication activate]
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Support `.loctable` localisation tables (binary plist of language → strings) in `NSBundle localizedStringForKey:value:table:` so alert texts resolve.
1. Drive the app the way `xcode-select --install` does (launch arguments / XPC), then remove the special case.
1. `PackageKit`/`SoftwareUpdate` stubs (catalog lookup returning *not available*); `-[NSApplication activate]`.

[Complete current survey](current-status.md).
