## Spatial Display v2.3 — activation and settings fix

- Removed the leading symbol from Settings → Spatial Display.
- Turning on Spatial Output now enters a visible full-screen viewer; an explicit Enter Spatial Mode control is included.
- Viewer works without an existing LiveProcess multitask window, shows a demonstrable 2D/SBS screen plane, motion status, and Reset View / Exit controls.
- Viewer reads iPhone motion, supported GameController motion, and UDP sensor bridge data; reports missing Joy-Con/XREAL sensor support instead of showing a silent no-op.
- Attempts snapshots of hosted multitasking windows (limited to ~12 fps; some iOS remote surfaces may be blank).
- Suspends the older multitask rig while the viewer is showing to avoid competing UDP listeners and conflicting host transforms.
- External output still uses iOS mirroring and may not switch XREAL glasses to native stereo. Not verified by an iOS device build.

## v2.2 — Swift notification build fix
- Fixed SwiftUI spatial settings using bare `GCControllerDidConnect` / `GCControllerDidDisconnect` instead of Swift `NSNotification.Name.GCControllerDidConnect` / `.GCControllerDidDisconnect`.
- Preserves v2.1 Reset View, controller sources, and spatial modes.
- Validated patch smoke test; full Xcode/iOS build not available in this environment.

## v2.1 — gyroscope-source recenter calibration

- Added **Reset View (Look Straight Ahead)** immediately below the gyro motion-source picker. The next valid sample from whichever tracking source is selected becomes the forward view.
- For `GCMotion.hasAttitude` controllers, reset now uses a reference quaternion and relative rotation, compensating for a constant mounting angle (such as a Joy-Con taped to the glasses' side). This does not guarantee iOS exposes Joy-Con gyro data, and rotation-rate-only input may still need axis mapping.
- Preserved all v2 display and motion-source options; kept the automatic wear detection caveat.
- This remains untested on iOS/XREAL hardware, and stereo output is experimental.

## v2.0 — Spatial Display phone-rendered prototype
- Added experimental Side-by-side stereo test capturing LiveContainer's multitask host (15 fps snapshot cap) with 60 Hz motion-driven viewport shifts.
- Added GameController motion enumeration and Joy-Con diagnostic; read GCMotion attitude or integrate rotation rate where actually supported.
- Added XREAL-name GameController discovery test (not raw USB HID access), device refresh, eye-plane separation setting, clear compatibility notices.
- Retained iPhone CoreMotion, UDP sensor bridge and recentering, 2D hosted-window panning, other Plus patches.
- **Limitations:** not XREAL 3840×1080 mode negotiation, full iOS external scene output, reliable remote-process capture, or tested IPA.

# Changelog

## 1.1.0 (spatial workspace prototype)

- Optional Settings → Spatial Display screen with mono workspace pan, manual recenter, external-display detection, sensor source and sensitivity
- Applies to LiveContainer virtual windows that host LiveProcess guest apps without injecting the guests
- iPhone CoreMotion demonstration and UDP tracker feed supporting `yaw`, `pitch`, optional `worn` transition
- Recenter on display reattachment or bridge-provided wear-on event; do not claim direct XREAL sensor support

## 1.0.2

- Grid layout: the long-press menu now matches the list layout (containers, open data folder, run or multitask,
  add to Home Screen with copy launch URL / save icon / create app clip, settings, uninstall)

## 1.0.1

- Use your own source by attaching `source.zip` to a release (`source = release`); missing submodules and build scripts
  are completed automatically from the official repository's pins
- Source fetching moved to `scripts/fetch-source.sh`
- Lite workflow: built-in Mach-O injector replaces the third-party `insert_dylib` build, Xcode selection and compiler
  diagnostics added

## 1.0.0

Initial release.

- Multiple instances per app (up to 16) with shared data
- Concurrent audio and video across windows
- Window snapping: edges, center, neighboring windows, smart fractions, configurable grids, presets, Tile all
- Full-screen windows when the dock is collapsed
- Dock controls and default window scale
- Custom background, Liquid Glass banners and grid home screen
- Branded build (LiveContainer Plus, `com.kdt.livecontainer.plus`)
- Build workflow with stable/nightly channels, LiveContainer and LiveContainer+SideStore packages, and official, mirror,
  fork, release asset or URL sources
- Lite workflow that adds a window menu to an existing IPA
