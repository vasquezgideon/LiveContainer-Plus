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
| `source` | `official`, `mirror`, `fork`, `uploaded`, `url` |
| `channel` | `nightly` (latest commit) or `stable` (latest release); applies to `official`, `mirror` and `fork` |
| `package` | `both`, `LiveContainer`, `LiveContainer+SideStore` |
| `fork_repo` | `owner/name`, for `source = fork` |
| `source_url` | https link to a source `.zip`, for `source = url` |
| `ref` | optional branch, tag or commit; overrides `channel` |
| `app_name`, `bundle_id` | branding; extensions and libraries follow the bundle identifier |
| `f_*` | switch individual features off |
| `strict` | fail instead of skipping a feature that does not fit the chosen LiveContainer version |
| `dry_run` | apply the patches and publish the patched source without building |

### Using your own source

| Goal | Setting |
|---|---|
| Your own fork (including a LiveContainer + SideStore fork) | `source = fork`, `fork_repo = owner/name` |
| A source archive stored in this repository | commit it as `input/source.zip`, then `source = uploaded` |
| A source archive hosted elsewhere | `source = url`, `source_url = https://…/source.zip` |

Choose `package = LiveContainer+SideStore` (or `both`) to build the SideStore variant from your source. Archives must
contain the submodule folders, so zip a `git clone --recursive` checkout rather than using GitHub's "Download ZIP".
More detail: [docs/BUILDING.md](docs/BUILDING.md).

## Compatibility

- Multitasking features use LiveContainer's virtual windows (the default on iPhone). Native iPad windows are unchanged.
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
