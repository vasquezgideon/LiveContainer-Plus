> **Spatial v2.1:** Settings → Spatial Display → Gyro input → **Reset View (Look Straight Ahead)** recenters the currently selected tracker. A Joy-Con can only provide tracking when iOS exposes its `GCMotion` data. See [Spatial Display](docs/SPATIAL_DISPLAY.md).

# LiveContainer Plus

Multitasking and home screen enhancements for [LiveContainer](https://github.com/LiveContainer/LiveContainer), applied to
LiveContainer's own source and built with a single GitHub Actions workflow. When LiveContainer updates, run the workflow
again.

**Status:** beta. The patches are verified against the current stable release and nightly source; builds are produced by
CI. See [Troubleshooting](docs/TROUBLESHOOTING.md) if a build or a feature misbehaves.

## Features

**Multitasking**

- Run the same app in up to 16 windows at once, sharing the app's data
- Audio and video play concurrently across windows
- Window snapping to screen edges, the screen center, other windows, and halves, thirds and quarters
- Snap grids from halves to sixteenths, or a custom grid, plus layout presets and **Tile all**
- Full-screen windows when the dock is collapsed, matching a full-screen launch
- Dock controls: tile, show all, close all; window bars follow the dock state
- Default window scale

**Spatial Display (experimental)**

- New **Settings → Spatial Display** opt-in toggle (default off)
- Moves LiveContainer's hosted multitasking windows as a single panning workspace, also for apps hosted by **LiveProcess**
- Uses iPhone motion as a **demo**, or a networked external 3DoF tracker via UDP; supports recenter, motion sensitivity and an optional connected-display requirement
- Recenter on a display reconnection, or on a wear-on event **if** a bridge provides `worn` status

**IMPORTANT:** This is monoscopic window panning, **not** true stereo VR. iOS does not provide a documented, publicly available interface to read the original XREAL Air's USB gyro or wear sensor. Phone motion follows the **phone**, not the glasses. The glasses' on/off wear sensor cannot be detected without a compatible external tracker/bridge. See [Spatial Display](docs/SPATIAL_DISPLAY.md) for protocol, scope and limitations.

**Home screen**

- Custom background: black (default), any image, or the system default, on every tab
- Liquid Glass banners over the background, following the system Clear/Tinted setting
- Grid layout in the style of the iOS Home Screen: Normal, Large, XL or custom columns, with optional names

Feature details and where to find each setting: [docs/FEATURES.md](docs/FEATURES.md).

## Getting started

1. Create a repository from this folder. A public repository is recommended; GitHub-hosted macOS runners are free for
   public repositories.
2. Open **Actions → Build LiveContainer Plus → Run workflow**, choose the options and start the build (about 15–25 minutes).
3. Download the IPA from **Releases** and install it with SideStore.

The default build is named **LiveContainer Plus** with bundle identifier `com.kdt.livecontainer.plus`, so it installs
next to stock LiveContainer as a separate app. To update stock LiveContainer in place, set `bundle_id` to
`com.kdt.livecontainer`.

## Build options

| Option | Values |
|---|---|
| `source` | `official`, `mirror`, `fork`, `release`, `url` |
| `channel` | `nightly` (latest commit) or `stable` (latest release); applies to `official`, `mirror` and `fork` |
| `package` | `both`, `LiveContainer`, `LiveContainer+SideStore` |
| `fork_repo` | `owner/name`, for `source = fork` |
| `release_tag` | release that holds your `.zip`, for `source = release` (empty = newest release with a `.zip`) |
| `source_url` | https link to a source `.zip`, for `source = url` |
| `ref` | optional branch, tag or commit; overrides `channel` |
| `app_name`, `bundle_id` | branding; extensions and libraries follow the bundle identifier |
| `f_*` | switch individual features off (including `f_spatial`) |
| `strict` | fail instead of skipping a feature that does not fit the chosen LiveContainer version |
| `dry_run` | apply the patches and publish the patched source without building |

### Using your own source

1. In your repository open **Releases → Draft a new release**, pick any tag (for example `source`), attach your
   LiveContainer or LiveContainer + SideStore source as **`source.zip`**, and publish (a pre-release or draft works too).
2. Run **Build LiveContainer Plus** with `source = release`.

The zip can be a plain GitHub "Download ZIP". Whatever it lacks is added automatically: missing submodules and the build
scripts are fetched at the versions pinned by the official LiveContainer repository. Folders that are present in your zip
are never replaced, so modified submodules are kept. Choose `package = LiveContainer+SideStore` (or `both`) to build the
SideStore variant.

Other ways to supply a source: `source = fork` with `fork_repo = owner/name` (your own GitHub repository), or
`source = url` with a link to a hosted `.zip`. More detail: [docs/BUILDING.md](docs/BUILDING.md).

## Compatibility

- Multitasking features use LiveContainer's virtual windows (the default on iPhone). Native iPad windows are unchanged.
- Spatial Display requires a compatible source for head motion; iPhone gyro mode alone is **not** head tracking. The implementation does not install its own external-display compositor or intercept arbitrary iOS apps.
- Liquid Glass uses the system material on iOS 26 and a blurred material on earlier versions.
- A feature whose patch no longer fits a given LiveContainer version is skipped and listed in the release notes; the rest of
  the build proceeds.

## Documentation

- [Features](docs/FEATURES.md)
- [Building and sources](docs/BUILDING.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Changelog](CHANGELOG.md)

## License

Released under the GNU Affero General Public License v3.0, the same license as LiveContainer. See [LICENSE](LICENSE) and
[NOTICE](NOTICE).

## Experimental on-device XREAL Spatial Display

This variant includes **Settings → Spatial Display**, selectable iPhone/controller/UDP/experimental-XREAL tracking and an opt-in **side-by-side flat-screen compositor** that runs on the phone, with no Raspberry Pi required. It can move or duplicate LiveContainer-hosted multitask windows, not arbitrary iOS apps. Joy-Con gyro is only supported if iOS actually exposes `GCMotion` for that controller, and the original XREAL Air's 3840×1080 SBS output is **not guaranteed** through iPhone mirroring. The source patch is not a tested IPA. See [Spatial Display limitations and tests](docs/SPATIAL_DISPLAY.md).

## Spatial Display v2.5 (experimental)

Spatial Display now uses a **separate external scene** rather than a full-screen viewer on the iPhone. The iPhone remains interactive, including during guest app launches. The workflow uses the `xcode-27` GitHub Actions runner for iOS 27 scene-accessory support. Rendering is currently a low-frame-rate snapshot-based floating monitor, not VR, and iOS can omit some guest surfaces. See [docs/SPATIAL_DISPLAY.md](docs/SPATIAL_DISPLAY.md).
