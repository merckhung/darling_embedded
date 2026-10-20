# Build and validation snapshot

Run date: 2026-10-20 (UTC). Linux x86_64 host, Bazel 9.1.0, LLVM 20 and QEMU
10.1.0. The build uses the pinned upstream commits in `MODULE.bazel`.

## Build

```bash
export PATH=/usr/lib/llvm-20/bin:$PATH
./tools/fetch_demo_apps.sh
bazel build //:arm64 //:verify_arm64 //:macho_import_report //:nibdump
bazel build //:macho_sign @darwin_embedded//tools/libdmg-hfsplus:hfsplus
bazel build //:all
```

The guest image and host tools built successfully. Both demo archive hashes
passed verification. The final guest build log is [build.log](app-results/build.log).
The [all-target build](app-results/build-all.log) also passed, including `run_gui`.
The root image is 384 MiB, with SHA-256:

```text
55e0f2d47ef7b595ec0905cff7d3decf62673d4f2b00e355a02f818872ff7643
```

## Baseline verification

```bash
bazel run //:verify_arm64 -- --baseline-only
```

Exited successfully. The retained [serial log](app-results/baseline.log) records
17 `[VERIFY PASS]` checks covering CLI startup, desktop/menu/Dock interactions,
FastDMG nib loading, preference binding and Quit, System Info script output and
Quit, ProgressBar output and automatic termination, WidgetGallery interaction
and Quit, and native Chromium's `WEBGL_READY:ANGLE` marker alongside FastDMG.
The optional historical flat-layout Zoom/Apple utility checks were skipped;
the recursive app survey supplies separate current launch attempts.

Screenshots were retaken with an elapsed-time settling interval before each
framebuffer dump. Visual inspection found these limits despite the verifier's
markers passing:

- [FastDMG](screenshots/darling_fastdmg.png) initially shows `Version X.X` and a
  blank credits area. A later [side-by-side capture](screenshots/darling_chromium_side_by_side.png)
  has its actual version/credits populated. This is not a disk-image mounting test.
- Chromium's window is white in the current side-by-side capture, even though
  the WebGL readiness marker was emitted. The marker does not validate visible
  page presentation or a rendered 3D scene.
- HelloWorld's source-demo labels include simplified OS/memory reporting. These
  labels are not independent measurements of the QEMU/kernel configuration.
- Empty optional bundle directories/desktop launchers may still appear in the
  baseline image. The survey inventory comes from actual local inputs and
  executable/metadata checks, rather than the Finder's directory list.

These are recorded as the current status. No kernel, dyld, framework or runtime
compatibility fixes were made to change those outcomes.

## Application survey

The [complete survey](apps/current-status.md) records every recursive vendor
bundle/alias and four source app configurations, with individual screenshots,
logs, original executable hashes and staging limits. The default startup bound
is eight seconds. Small bundles are copied completely; larger bundles get the
launcher, prepared native libraries and selected resources within a 250 MiB
budget. Omitted libraries are recorded. Helpers are launched individually.

The source-app pilot confirmed windows for HelloWorld, WidgetGallery, System
Info and ProgressBar. Their functionality beyond the baseline checks was not
validated. Startup failures, crashes, missing metadata, timeouts and background
services without a window are retained as observations, not converted into
successes.

Import reports cover direct main-executable imports against the baseline system
root, without a full bundle dependency closure or selector/behavior coverage.
See [PLAN.md](../PLAN.md) for the remaining work and interpretation limits.

## Snapshot audit

All 262 inventory entries have a launch log and a verified 1024×768 PNG whose
SHA-256 matches the manifest. The survey contains 258 vendor bundles/aliases and
four source configurations: 31 startup windows, 165 exits without a window,
64 bounded no-window observations and two missing-input cases. There are 236
complete vendor copies and 22 partial probes, plus the four source apps.

All 256 available vendor executables have direct-import reports. The current
inventory and original executable hashes were rechecked against the filesystem,
the guest image hash matches the captured run, documentation links resolve,
and local build-machine paths were removed. The [audit record](app-results/audit.json)
contains the verified counts. `vendor/` has no tracked files.
