# Spatial Display — external-only experimental v2.6

This replaces the full-screen on-phone viewer in v2.3/v2.4. The phone remains the primary interactive screen. When enabled in Settings and an external monitor is connected, LiveContainer registers a separate **external noninteractive window scene** for the XREAL view. The external display contains a head-tracked 2D screen-plane rendering of phone app content, NOT an interactive second app instance. Phone taps and gestures continue to operate the *live phone UI*.

## iOS 27+ display registration

iOS 27 requires `UISceneAccessory.externalNonInteractive(sceneConfiguration:)` registered from a visible main-display UIViewController. The `LCPlusSpatialCoordinator` keeps a registration associated with the current primary window root controller and enables/disables it with the Spatial Display toggle. iOS 16–26 use the noninteractive external scene role and a delegate configuration. The workflow now runs on GitHub's `xcode-27` hosted runner because Xcode 26 cannot compile the scene-accessory APIs.

## What launches work?

The renderer captures visible application windows for the *current process's phone scenes* rather than the old multitask-only `MultitaskDockManager.windowHostingView`. This allows an ordinary guest app and hosted LiveProcess content **when the app remains in the hosting process and its UIKit window is available**. A best-effort `LCBootstrap.m` UIKit-activation hook restarts the spatial coordinator when a normal guest app takes over the phone screen. A separate app/extension process without the host Swift module cannot use this hook. Universal compatibility is not proven. Apps in separate instances of LiveContainer cannot be captured. UIKit can omit Metal, protected video, secure entry fields, and remotely hosted LiveProcess surfaces. Capturing is capped to roughly **12 fps**, and on-device latency/comfort are not established.

## Operation

1. Connect the original XREAL Air directly to the iPhone over a video-compatible USB-C cable. Open Settings → Spatial Display and turn **Enable spatial output** on. **No fullscreen viewer should cover the phone.**
2. On the external screen, a spatial screen plane is presented (if iOS creates the separate scene). Continue operating LiveContainer and launching apps on the phone as usual.
3. Select iPhone, supported GameController motion device, or UDP sensor bridge. **Reset View (Look Straight Ahead)** recalibrates on the next motion sample. Joy-Con Bluetooth pairing does not guarantee `GCMotion` sensor access.
4. Start with **Normal spatial desktop (2D)**. The stereo test draws two shifted copies of a flat screen and does not force XREAL's 3840×1080 full SBS mode or create 3D geometry.

## Diagnostics / limits

The app may mirror the phone instead if iOS never connects the external noninteractive scene. Check Settings → Spatial Display → **Spatial display scene** for Connected/Not connected. `LCPlusSpatialExternalConnected` is updated when the delegate attaches or detaches its window. The original glasses' gyro and wear sensor remain unavailable over public iOS USB HID APIs. This is a best-effort proof of concept, not a fully functional VR runtime.

Source checks are available with `python3 tools/test_spatial_patch.py`; a real GitHub/Xcode 27 build and device test are necessary to confirm compatibility.

## v2.6: full-canvas and separate sensor capabilities

The output uses the entire external-scene canvas rather than a floating rounded picture-in-picture card. Choose **Fill external view** to crop an app to the glasses' aspect ratio or **Fit whole phone screen** to retain every pixel. This is not reconstructed spatial geometry; a flat app remains flat.

GameController gyroscope (`hasRotationRate`) and accelerometer/gravity (`hasGravityAndUserAcceleration`) are now reported separately. If the controller provides rate and gravity but no attitude, a complementary filter reduces pitch drift. Accelerometer-only tracking provides relative tilt, **not absolute heading**. If a Joy-Con reports no `GCMotion` through iOS, the sensors cannot be read through the public GameController interface; native Bluetooth pairing does not imply raw HID access.

The Settings page now includes **selected controller live gyro (rad/s) and acceleration (g) readings**. Sensor support and real values can be inspected even when the external-display scene has not connected.
