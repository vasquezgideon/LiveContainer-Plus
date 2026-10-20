# Features

Settings live in **Settings → Multitask** (section *LiveContainer Plus*) and **Settings → Appearance**.

## Multitasking

### Multiple instances per app

Pressing Run on an app that is already open starts another window instead of focusing the existing one, up to 16 per
app. Instances share the app's data folder (Documents, Library, Caches, preferences). Apps that keep SQLite databases or
lock files open can interfere with each other; use this with apps where that is acceptable.

Applies to virtual windows. Native iPad windows are unchanged.

### Audio in multiple windows

Each window is a separate process, and iOS normally pauses one process's audio when another starts playing. Windows
request "mix with others", so audio and video play concurrently. Requested audio categories and interruptions are
logged to `Documents/LCPlusAudio.log` in the app's data folder.

### Window snapping

While moving or resizing, window edges snap to the screen edges, the screen center, other windows, and halves, thirds
and quarters. A blue guide line and a light haptic confirm a snap. On release, a window whose size is close to a half,
third or quarter is set to exactly that size.

| Setting | Effect |
|---|---|
| Snap grid | Off, halves, thirds, fourths, quarters, ninths, sixteenths or a custom columns × rows grid. Released windows align to the grid cells. |
| Smart snap | Halves, thirds and quarters as snap targets, independent of the grid setting |
| Snap to screen center | Adds the vertical and horizontal center lines |
| Snap to half at screen edges | Dropping a window on the left or right edge makes it an exact half |
| Snap strength | Distance in points at which snapping engages (0 turns live snapping off) |

The title-bar menu of a window (tap the app name) contains **Snap** presets: full screen, halves, thirds, two-thirds,
fourths, quarters, ninths, sixteenths, and the custom grid.

### Full-screen windows with the dock collapsed

With the dock expanded, windows stay inside the safe area as in stock LiveContainer. With the dock collapsed, windows use
the entire screen. Open windows resize with the change, snapping and Tile use the full screen, and a window that
reaches the screen edges receives the device insets and square corners, matching a full-screen launch.

### Dock controls

The dock's arrow expands and collapses it. Expanded, every window shows its bar. Collapsed, the bars are hidden; a thin
strip at the top of each window moves it, and double-tapping the strip expands the dock. New dock buttons: **Tile**
arranges all windows (2 side by side, 3 in thirds, 4 as 2 × 2, up to 16), **Show all** and **Close all**.

### Default window scale

Sets the initial scale of new windows (0.5× to 2×).

## Home screen

### Background

Settings → Appearance → Background: black (default), an image from the photo library, or the system default. The
background appears on the app list, Sources, Tweaks and Settings pages.

### Liquid Glass

In the list layout the app banners are Liquid Glass over the background. On iOS 26 this is the system material and
follows the Clear/Tinted preference in Settings → Display & Brightness. The *Tint* slider adds color; 0 is plain system
glass. Earlier iOS versions use a blurred material.

### Grid layout

Settings → Appearance → Layout → Grid. Sizes: Normal (4 wide), Large (3), XL (2) or a custom column count, with optional
app names. Tap launches the app; long-press opens its settings and run options. Glass banners apply to the list layout
only.
