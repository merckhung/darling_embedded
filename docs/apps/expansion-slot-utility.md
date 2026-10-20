# Expansion Slot Utility

Current snapshot: 2026-10-20 (UTC).

- Source: `vendor/Golden Gate Apps/CoreServices/Applications/Expansion Slot Utility.app`.
- Observation: **window observed (functionality unverified)**.
- Staging: complete bundle copy.
- Original regular-file size: 0.6 MiB (symlinks excluded).
- Local bundle version: `2.0`.
- Evidence: [screenshot](../../docs/screenshots/apps/expansion-slot-utility-8ab79634.png), [launch log](../../docs/app-results/expansion-slot-utility-8ab79634.log), [direct-import report](../../docs/app-results/expansion-slot-utility-8ab79634-imports.txt).

First recorded diagnostic:

```text
native dyld warning: unresolved import: _AECreateAppleEvent
```

The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.

## Remaining work

1. Load `Main.storyboardc` through `NSStoryboard` initial controller instantiation instead of the `ESUWindow` special case.
1. `ExpansionSlotSupport` private framework reporting zero slots, plus IOKit registry iteration stubs.
1. AppKit: `NSLevelIndicator` styles/colours, `-[NSStackView setCustomSpacing:afterView:]`, `-[NSView addSubview:positioned:relativeTo:]`, `+[NSFont systemFontSizeForControlSize:]`, `-[NSMutableArray initWithCapacity:]`.

[Complete current survey](current-status.md).
