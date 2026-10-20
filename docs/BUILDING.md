# Building

The workflow **Build LiveContainer Plus** fetches a LiveContainer source tree, applies the patches, builds the IPA on a
`macos-latest` runner and publishes it as a release of your repository. Releases are marked as pre-releases.

## Choosing the source

| `source` | What is built |
|---|---|
| `official` | `LiveContainer/LiveContainer` |
| `mirror` | `LiveContainerMirror/LiveContainer` (archived; may be behind) |
| `fork` | the repository in `fork_repo` |
| `release` | the `.zip` attached to a release of your repository (`release_tag`, or the newest release that has one) |
| `url` | the archive at `source_url` |

For `official`, `mirror` and `fork`, `channel` selects the version: `nightly` builds the latest commit of the default
branch and `stable` builds the latest GitHub release (falling back to the default branch if the repository has none).
`ref` builds a specific branch, tag or commit instead.

### Your own source as a release asset

Create a release in your repository, attach the source as `source.zip` (if a release has several `.zip` files, the one
named `source*.zip` is used) and run the workflow with `source = release`. Release assets can be up to 2 GB, so the size of the
archive is not a concern.

The archive may be incomplete. The workflow:

- unwraps a single top-level folder (as in GitHub's "Download ZIP");
- initializes submodules if the archive contains a `.git` directory;
- fetches every submodule folder that is empty, at the commit pinned by the official LiveContainer repository for the
  selected `channel` (nightly pins for `nightly`, the latest release's pins for `stable`);
- fetches the `.github` build scripts if they are missing.

Folders that are already present are left untouched, so your own submodule changes are kept. The workflow stops if the
archive does not contain a LiveContainer project (`LiveContainer.xcodeproj`).

## Packages

`package` selects the IPA: `LiveContainer`, `LiveContainer+SideStore` or `both`. The SideStore variant is produced by the
source's own `.github/build_github.sh`, so the source must contain it.

## Identity

`app_name` sets the name shown on the home screen. `bundle_id` sets the bundle identifier of the app; the LiveProcess,
Share, Launch and Widget extensions and the embedded libraries are placed under it, and SideStore's references to the
app's identifier are updated to match. Keychain group names are left unchanged.

A new bundle identifier installs as a separate app with its own data. To update stock LiveContainer in place and keep its
library, set `bundle_id` to `com.kdt.livecontainer`.

## Outputs

- A release named `<app> build <n> (<ref>)` with the IPA file(s) and a table of the applied and skipped features
- On failure: the `build-log` artifact and a summary of the first compiler errors in the run summary
- `dry_run`: the `patched-source` artifact, useful to inspect the changes

## Local verification

`tools/selftest.sh` clones the latest stable tag and the default branch of LiveContainer, applies every feature in strict
mode and parses all changed Swift and Objective-C files. It needs `git`, `python3` and
`pip install tree-sitter tree-sitter-swift tree-sitter-objc`. It checks syntax only; compiling requires Xcode, which the
workflow provides.
