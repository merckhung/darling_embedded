# Stickies

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/Applications/Stickies.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 1.4 MiB (symlinks excluded).
- Local bundle version: `10.3`.
- Evidence: [screenshot](../../docs/screenshots/apps/stickies-79b465c0.png), [launch log](../../docs/app-results/stickies-79b465c0.log), [direct-import report](../../docs/app-results/stickies-79b465c0-imports.txt).

First recorded diagnostic:

```text
[AppKit] nib: class 'NSFontEffectsBox' not found
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Remove the text injection: load notes through `NSDocument`/`NSDocumentController` from `~/Library/Containers/com.apple.Stickies/Data/Library/Stickies/*.rtfd` and render RTF/RTFD (font, colour attributes) in `NSTextView`.
1. Note colour comes from the document (`SNDocument`), not from the nib loader.
1. AppKit/Foundation gaps: `-[NSString enumerateLinesUsingBlock:]`, `-[NSApplication changeWindowsItem:title:filename:]`, `-[NSWindowController setShouldCascadeWindows:]`, `-[NSDocument fileURL]`, the `NSFontEffectsBox` class.
1. QuartzCore and UniformTypeIdentifiers (absent) stubs.

[Complete current survey](current-status.md).
