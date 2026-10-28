# Spatial Display — on-device experimental XREAL viewer

## Actual implementation (v2.3)

This patch adds **Settings → Spatial Display** in the full source-built LiveContainer Plus variant. It is not part of the Lite IPA injection workflow.

**The iPhone performs all spatial rendering and input processing. No Raspberry Pi or HDMI capture hardware is needed.** Connect an original XREAL Air directly to the phone using a compatible USB-C cable; the iPhone's normal video mirroring supplies the picture. The phone must support USB-C DisplayPort video output.

### How to enter the viewer (v2.3 fix)

1. Open **Settings → Spatial Display** (the Settings row now has no icon).
2. Choose the motion source and picture mode. **Enabling spatial output now automatically opens a visible full-screen viewer**, or tap **Enter Spatial Mode** to enter manually.
3. The viewer renders on the iPhone and **mirrors to the connected glasses** using the existing iOS video path. There is no separate external-display scene or XREAL DisplayPort mode selection in this build; iOS 27 requires separate scene-accessory registration for independent external display output.
4. The viewer always displays a visible test scene even if no multitask app is running. If supported guest apps are launched in Multitask, it tries to show snapshots of their shared window host at approximately **12 fps**. Some guest/remote surfaces may render blank because of iOS snapshot restrictions. Tap **Reset View** to use the sensor's current orientation as forward, or **Exit** to turn the mode off.
5. If controller motion is not exposed by iOS, the viewer reports this explicitly. A paired Joy-Con is not proof its gyro can be read by GameController.

This repairs the earlier silent toggle issue: the old patch only attached the spatial renderer after a multitasking app window was created and could be gated by a required external display.

**Still experimental**: this is not a low-latency fully functional AR desktop or native stereo VR renderer. The fullscreen viewer primarily demonstrates sensor-driven panning and may be limited by UIKit capture/HDMI mirroring. Using the real XREAL Air SBS mode is not guaranteed.

### Picture modes

- **Normal spatial desktop (2D)**: Translates the LiveContainer shared virtual-window host in response to head/source orientation; same head-pannable mono mode as v1.
- **Side-by-side stereo test**: Renders two offset views of a *flat captured virtual-screen plane* using an overlay above LiveContainer's multitask workspace. Both eyes get a separate image derived from the same window-host snapshot. Reprojection/eye positions update at display-link rate (target 60 Hz), while the source image is recaptured at **no more than 15 fps** to limit capture work. The mode does **not** magically reconstruct 3D objects from a normal 2D app.

**XREAL limitation:** The original Air's stereo mode normally expects **3840×1080 Full-SBS** and must be manually switched on using the glasses' controls (subject to firmware). iPhone screen mirroring may negotiate only 1920×1080 or may not permit 3840×1080. This build **does not** negotiate or force that display mode, and **does not** create an iOS 27 external scene accessory. Therefore the SBS test can look squeezed, duplicated, or wrong on actual Air glasses, despite working as an on-phone image preview. An independent external display compositor is future work. Try 2D mode first; switch back immediately if uncomfortable.

**Guest app capture limitation:** LiveContainer owns the shared multitask host, but system-managed/remote LiveProcess surfaces may be blank in `drawViewHierarchy(in:afterScreenUpdates:)`. Snapshot timing, smoothness, content visibility, orientation and touch alignment have not been tested on physical iOS hardware. This is a source-level prototype, not a validated VR runtime.

### Motion source selection

The Settings panel lists and selects:

| Source | What is actually read |
|---|---|
| iPhone gyroscope | CoreMotion's processed device-motion orientation; the iPhone must move to move the screen |
| Sensor bridge (UDP) | Absolute yaw/pitch degrees reported by an external head tracker |
| Bluetooth game controller | `GameController.GCController.controllers()`; checks `GCMotion.hasAttitude` and `hasRotationRate` before using a device. Some Joy-Cons pair for gameplay but **don't expose gyro data through iOS GameController**. If attitude exists, use its quaternion; if only rate exists, integrate angular velocity (drifts). No raw Joy-Con Bluetooth HID integration. |
| XREAL Air (experimental discovery) | Scans public GameController device names for XREAL/Nreal and reads `GCMotion` **only if** the glasses really appear with a usable motion profile. Ordinary XREAL Air USB HID isn't exposed by a documented public iOS API, so this is likely to report none. No fake gyro. |

For Joy-Con: Pair in **iOS Settings → Bluetooth**, then **Refresh connected devices** in LiveContainer Plus settings; select your controller and check if it reports orientation/gyro. If it says "no motion profile", this build cannot use its gyro by attaching it to the glasses. A separate microcontroller or Pi bridge that actually reads Joy-Con IMU could send UDP instead. Attach hardware safely; avoid obstructing vision or damaging the glasses.

### Other settings

- **Reset View (Look Straight Ahead)**: directly below **Motion source** in Settings → Spatial Display → Gyro input. Look in the desired forward direction and tap once; the next valid motion sample becomes the new forward-facing orientation. This resets yaw/pitch for iPhone, UDP, and supported controllers. For a controller that supplies a full attitude quaternion, the calibration is relative to the starting pose, compensating for a fixed mounting angle (for example a Joy-Con taped to the side of the glasses). Gyro-rates-only controllers can still drift and might require axis remapping if mounted sideways. If no compatible motion stream is exposed by iOS, the button cannot create one. External-display connection changes also recenter.
- **Only run with an external screen**: enabled by default; disable to test the effect on the iPhone.
- **Stereo plane separation**: small illustrative binocular offset, not calibrated physical IPD.
- **Movement sensitivity**: scales head pan, from 0.2× to 3×.
- **Automatic wear recenter**: only works when a UDP sensor bridge sends a true wear transition. Joy-Con has no glasses wear sensor.

### UDP protocol

Default port is **38271**, e.g. `{"yaw":27.5,"pitch":-4.2,"worn":true}` over UDP to the iPhone's private LAN IP. Angles are in degrees in a stable absolute frame; `worn` is optional. The receiver drops stale samples after 2 seconds, caps packet size at 512 bytes and drains up to 8 per frame. Turn the feature off/on after changing the port. Do not expose this port to public Wi-Fi because packets are unauthenticated. A test generator is provided at `tools/spatial_test_sender.py`.

### Scope

- Processes only LiveContainer multitask-hosted content. Cannot render arbitrary apps in SpringBoard or other separate iOS processes.
- Not 6DoF, full SteamVR, real depth reconstruction, or an XREAL USB driver.
- New Swift Settings and Objective-C host patch run in source-build pipeline only. Full IPA build **requires macOS/Xcode**; this ZIP provides buildable source patches but no verified compiled IPA.
- Previous multitasking, UI features, and existing v1 UDP motion path are retained.

### Test procedure

1. In Actions → **Build LiveContainer Plus**, select package and enable `f_spatial`; first use `dry_run` to inspect patch report.
2. Install a signed IPA from a successful **macOS build**. Spatial Viewer can start without an external screen; the “Only run with an external screen” switch affects only the legacy multitask-host effect.
3. Select **iPhone gyroscope** and **Normal spatial desktop (2D)**, then toggle on Spatial Display to enter the full-screen viewer. Move the phone to confirm the test screen moves. For a guest app screenshot, first launch a Shared App in Multitask. Use Recenter if needed.
4. Turn on **Side-by-side stereo test**, and verify two image regions are displayed. If windows are blank or freeze, turn the mode off and report iOS version / app / observed behavior.
5. Pair a Joy-Con to iOS and Refresh devices. Check the motion capability. Only then select Bluetooth game controller. If motion is absent, the solution needs a hardware sensor bridge. If motion is available, strap the Joy-Con firmly without blocking the glasses, look forward, and press **Reset View (Look Straight Ahead)** beneath the source picker. Turn your head to confirm relative movement. Try again if the controller shifts on its mount.
6. For XREAL, connect the glasses by a direct display-compatible cable. Try 2D first. For stereo, only test if the display actually enters the correct SBS mode; if the image is doubled or distorted, turn off SBS.

## iOS compatibility (v2.4)

The full-screen `LCPlusSpatialViewer` uses the multitasking host and `persistentSystemOverlays`, which require iOS 16 or later. These APIs are isolated under `@available(iOS 16.0, *)` and the Settings entry has a runtime availability guard. This allows source builds whose deployment target is older than iOS 16.
