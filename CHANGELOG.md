# Changelog

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
