# Architecture

LiveContainer Plus does not fork LiveContainer. `patcher/apply.py` modifies a checkout of LiveContainer's source and adds
new files, so the same patches can be applied to different LiveContainer versions.

## Layout

```
.github/workflows/   build.yml (source build), patch-ipa.yml (lite IPA patch)
patcher/apply.py     the patch engine and the feature groups
payload/swift/       Swift files copied into LiveContainerSwiftUI/LCPlus/
payload/objc/        Objective-C snippets inserted into LiveContainer's sources
lite/                small library for the IPA-only workflow
tools/               selftest.sh and syntax_check.py
docs/                documentation
```

## Patch engine

Edits are anchored on method names and unique statements, never on line numbers. Each feature group is applied as a unit:
if one anchor is missing because LiveContainer changed that code, the group is rolled back, listed as skipped in the
release notes, and the other groups are still applied. `--strict` turns a skipped group into a failure.

New Swift files are placed in `LiveContainerSwiftUI/LCPlus/`, a folder the Xcode project compiles automatically, so no
project file edits are needed.

## Feature groups

| Group | Main touchpoints |
|---|---|
| `branding` | `xcconfigs/Global.xcconfig`, display name, SideStore references, library identifiers |
| `multi_instance` | `MultitaskManager`, `AppSceneViewController`, `LCBootstrap`, `LiveProcess/main.m`, run actions, dock identities |
| `snapping` | `DecoratedAppSceneViewController` (move, resize, frames, insets, menus) |
| `scale` | `DecoratedAppSceneViewController` (initial scale) |
| `dock` | dock view and window bars (depends on `snapping`) |
| `audio` | guest audio session setup in `LCBootstrap`, extension launch info |
| `appearance` | app list, banners, Settings, Sources, Tweaks pages |

## Compatibility strategy

- Alternatives for versions that differ (for example the SwiftUI banner of older releases and the UIKit banner of newer
  ones) are tried in order.
- Optional anchors, such as the background on sub-pages, are skipped individually and reported.
- `tools/selftest.sh` runs the whole set against the latest stable tag and the default branch.

## Adding a patch

Add the new source to `payload/`, then add the anchored edits to a group in `patcher/apply.py` using the `Workspace`
helpers (`literal`, `regex`, `insert_before`, `insert_after`, `add_file`). Run `tools/selftest.sh` before building.
