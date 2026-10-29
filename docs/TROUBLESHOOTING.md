# Troubleshooting

## The build fails

Version 2.8 introduces smaller SwiftUI view builders and an iOS-version API
preflight; those changes address code structures that have previously produced
compile errors. This **does not establish** that the older exit-code-65 run was
caused by one of those structures. There is no reliable diagnosis without the
unfiltered Xcode log.


Open the run summary: the Build step prints unfiltered compiler errors with context. The entire raw Xcode output is in the `build-log` artifact. Exit code 65 alone cannot identify the cause. A feature that does
not compile on a given LiveContainer version can be switched off with its `f_*` option while the rest still builds.
Include the log when reporting an issue.

## A feature is missing from the build

The release notes list every feature as *Applied* or *Skipped*. A skipped feature means LiveContainer changed the code the
patch relies on. Build another version (`channel`, `ref`) or open an issue with the notes.

## SideStore reports `VerificationError`

The cause is not confirmed. A changed bundle identifier is the first thing to rule out: build with
`bundle_id = com.kdt.livecontainer` and install again. When reporting it, include the build options, whether the error
appeared while installing or refreshing, and the variant (`LiveContainer` or `LiveContainer+SideStore`).

## Windows pause each other's audio

Check Settings → Multitask → *Audio in multiple windows*. The log `Documents/LCPlusAudio.log` in each app's data folder
records the audio category the app requested and any interruption sent by iOS. Apps that use their own exclusive audio
route or detect other running copies can still conflict.

## Instances of one app disturb each other

Instances share the app's data. Close the extra windows or disable *Multiple instances per app*.

## Window frames look wrong after a settings change

Collapse and expand the dock once to re-lay out the windows. If a window keeps an incorrect size, use **Tile** or a preset
from the window's title-bar menu.

## The lite IPA workflow fails

The workflow prints the Xcode version and the full compiler command. If the compile step fails, the error lines in that
step show the cause. If the injection step fails with "not enough free space", the app's binary has no room for another
load command and cannot be patched this way; use the source build instead.
