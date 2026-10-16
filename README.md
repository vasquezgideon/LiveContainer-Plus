# LCPlus — LiveContainer window extras, injected into the stock IPA

Adds to every LiveContainer multitask window (extra ▦ button in the title bar):
- **New instance** — launches the same app in the next free container, new window
- **Hide window bar** — chromeless at any size; drag the thin top strip to move, double-tap it to bring the bar back
- **Snap** — left/right half, thirds, two-thirds, full; optional "snap when dragged to edge"

## Use (all doable from a phone)
1. Make a **public** repo (macOS runners are free for public repos) and upload everything in this folder.
2. Actions → *Patch LiveContainer* → *Run workflow* → pick a source (stable / nightly, with or without SideStore) → Run.
   Or drop any LiveContainer IPA into `input/` and commit; it patches that one instead.
3. When it finishes (~3 min), Releases → download the `.ipa` → install over your current LiveContainer with SideStore.
   (Install with "Keep App Extensions", same as stock, or multitask won't work.)

## Notes
- New instance needs a **spare container** for that app already created (long-press app → Containers).
  It picks the next one that isn't running, then launches it via LiveContainer's own URL scheme.
  For the new window to open as a window, multitask should be your launch mode (LiveContainer settings).
- Hooks are by selector name and skip anything missing. Check `Documents/LCPlus.log` in LiveContainer to see what attached.
- Built against LiveContainer main as of Sept 2026 (`DecoratedAppSceneViewController`). Older view-based builds are skipped.
- **Untested** at time of writing: built by reading the source, not run on a device.
