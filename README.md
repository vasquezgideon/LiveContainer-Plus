# LiveContainer Plus

A patch kit that turns **LiveContainer** into **LiveContainer Plus**: better multitasking and a nicer home screen.
You don't download a fixed build: a GitHub Action fetches LiveContainer's own source (stable or nightly), applies
the patches, builds the IPA on a free macOS runner and puts it in a release. When LiveContainer updates, run it again.

## What you get

**Multitasking**
- **Several instances of the same app** (up to 16) in separate windows, all using the same Documents / Library / Caches.
  Tapping Run on an app that is already open starts another window instead of jumping to the old one. No second
  container and no LC2/LC3 copies needed.
- **Snapping**: windows snap to screen edges, the screen middle and *each other* while you drag or resize.
  Dropping a window on the left/right screen edge makes it an exact 50/50 half.
- **Snap grid** (Settings → Multitask → LC Plus): halves, thirds, fourths, quarters, ninths (3×3), sixteenths (4×4) or
  your own columns × rows. Released windows lock to the grid cells. Dragging stays free-form when the grid is off.
- **Presets in the window title menu** (tap the app name): full screen, halves, thirds, two-thirds, fourths, quarters,
  ninths, sixteenths, plus a menu for your custom grid.
- **Dock controls**: the dock's arrow expands/collapses it. Expanded = every window shows its bar; collapsed = bars hide
  so the apps are just apps (drag the thin strip at the top of a window to move it, double-tap it to bring the bars back).
  New dock buttons: **Tile** (auto-arranges all windows: 2 → side by side, 3 → thirds, 4 → 2×2 … up to 16),
  **Show all**, **Close all**. The existing "hide all" button stays.
- **Default window scale** slider in Multitask settings.

**Home screen**
- **Custom background**: black by default, or any image (Settings → Appearance (LC Plus)).
- **Liquid Glass banners** in the list layout, see-through over the background. On iOS 26 this is the real system glass,
  so it follows your *Clear / Tinted* choice (Settings → Display & Brightness → Liquid Glass). A tint slider adds extra
  colour; 0 = pure system glass. Older iOS gets a blurred material.
- **Grid layout** like the Home Screen: names on/off, Normal (4 wide) / Large (3) / XL (2) / custom columns.
  Tap launches, long-press opens settings. XL without names = a 2-wide grid of big icons. Glass is list-only, as asked.

## Install it (about 10 minutes the first time)

1. Create a **public** GitHub repo (macOS runners are free for public repos) and push this folder to it:
   ```
   git init && git add -A && git commit -m "LC Plus" && git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git && git push -u origin main
   ```
   (Phone only? In the GitHub web UI use *Add file → Create new file* and type the path `.github/workflows/build.yml`
   to paste each file; the web uploader can't create `.github` folders.)
2. Actions tab → **Build LiveContainer Plus** → **Run workflow**, pick options, run. ~15–25 min.
3. Releases → download the `.ipa` → sideload over LiveContainer with SideStore (**Keep app extensions** on).

## Run-form options

| Option | Choices |
|---|---|
| `channel` | **nightly** = newest code on the repo's default branch · **stable** = latest GitHub release |
| `package` | **both** · `LiveContainer` (no SideStore) · `LiveContainer+SideStore` |
| `source_repo` | `LiveContainer/LiveContainer` (official) · `LiveContainerMirror/LiveContainer` (archived mirror, stale) · `custom` |
| `custom_repo` | your fork, `owner/name`, when `source_repo` = custom |
| `custom_ref` | branch / tag / commit to build instead of the channel |
| `app_name` | name on the home screen (default **LiveContainer Plus**) |
| `bundle_id` | default `com.kdt.livecontainerplus`; the LiveProcess / Share / Launch / Widget extension IDs follow it automatically |
| `f_*` switches | turn individual feature groups off |
| `strict` | fail instead of skipping a feature whose patch no longer fits that LiveContainer version |
| `dry_run` | only apply the patches and download the patched source (no build) |

**Your own source code:** commit a zip of a LiveContainer checkout to `input/source.zip` and it is built with all features.
**Your own IPA:** the full feature set changes LiveContainer's code, so it can't be added to a finished IPA. The second
workflow **Patch IPA (lite)** (keeps the stock name and bundle ID) injects a small dylib into any IPA (commit it to `input/`, or pick stable/nightly): window
menu with snap presets, hide-bar mode and "new instance" in a *spare* container. It has none of the home-screen features.

## Name and bundle ID

The build is branded **LiveContainer Plus** with bundle ID `com.kdt.livecontainerplus` (extensions: `.LiveProcess`,
`.ShareExtension`, `.LaunchAppExtension`, `.LiveWidget`). The SideStore variant's own references to its app ID
(refresh hooks, `sidestore-<id>` backup URL scheme, widget ID) are updated to match. Keychain group names stay
`com.kdt.livecontainer.shared…`, so guest-app keychain items behave exactly as in stock LiveContainer.

- **A new bundle ID is a separate app**: it installs next to stock LiveContainer with an empty library. Apps and
  containers you added to stock LiveContainer, and a SideStore setup inside the LC+SideStore variant, don't carry over.
  To update **in place** and keep everything, run the build with `bundle_id = com.kdt.livecontainer` (the name still
  becomes LiveContainer Plus).
- Both apps register the `livecontainer://` URL scheme. If you keep both installed, links, shortcuts and widgets can
  open the wrong one; remove stock LiveContainer or treat it as a spare.

## How the patching works

`patcher/apply.py` edits LiveContainer's source by **anchors** (method names and unique statements, never line numbers).
Each feature is applied as a unit; if LiveContainer changed that code and an anchor is gone, that feature is skipped and
listed in the release notes while the rest still builds. New Swift files go into `LiveContainerSwiftUI/LCPlus/`, which
Xcode picks up automatically.

Checked against **stable 3.8.0** and **nightly (main, 2026-09-19)**: branding and all five feature groups apply, alone or
in any combination, and every changed file passes a Swift/Objective-C syntax parse. `tools/selftest.sh` repeats that check
on your machine against whatever is current (needs only git, python3 and the tree-sitter packages).

## Be aware

- **Not compiled and not run on a device.** I can't run Xcode or an iPhone here. If the first build fails, open the run summary
  (it lists the first compiler errors), download the `build-log` artifact, and switch off the feature that broke it
  with the `f_*` switches. Send me the log and I'll fix it.
- **Same app, same data:** instances share Documents/Library/Caches and preferences. Apps that keep SQLite databases or
  lock files can corrupt each other's data or crash. Use it where that's acceptable (emulators, viewers, tools).
- iOS may kill background processes when memory runs low; sixteen heavy apps won't survive. Light apps will.
- Multi-instance works in **virtual window mode** (the default on iPhone). Native iPad windows are unchanged.
- The grid launch uses LiveContainer's normal launch path, so locked apps still ask for authentication.
- The built IPA contains LiveContainer's AGPL-3.0 code; keep this repo public with the patch source.
