// LiveContainer Plus — experimental spatial output controls.
// Only controllers that actually publish motion to GameController can be used.
import SwiftUI
import UIKit
import GameController
import CoreMotion

struct LCPlusSpatialSettingsView: View {
    @AppStorage("LCPlusSpatialEnabled", store: LCUtils.appGroupUserDefault)
    private var enabled = false
    @AppStorage("LCPlusSpatialTrackingSource", store: LCUtils.appGroupUserDefault)
    private var source = 0
    @AppStorage("LCPlusSpatialControllerIndex", store: LCUtils.appGroupUserDefault)
    private var controllerIndex = 0
    @AppStorage("LCPlusSpatialRenderMode", store: LCUtils.appGroupUserDefault)
    private var renderMode = 0
    @AppStorage("LCPlusSpatialSensitivity", store: LCUtils.appGroupUserDefault)
    private var sensitivity = 1.0
    @AppStorage("LCPlusSpatialEyeSeparation", store: LCUtils.appGroupUserDefault)
    private var eyeSeparation = 0.028
    @AppStorage("LCPlusSpatialFraming", store: LCUtils.appGroupUserDefault)
    private var framing = 0
    @AppStorage("LCPlusSpatialZoom", store: LCUtils.appGroupUserDefault)
    private var zoom = 1.25
    @AppStorage("LCPlusSpatialPort", store: LCUtils.appGroupUserDefault)
    private var port = 38271
    @AppStorage("LCPlusSpatialRecenter", store: LCUtils.appGroupUserDefault)
    private var recenterNonce = 0
    @State private var controllers: [GCController] = []
    @State private var controllerGyroReadout = "No gyro samples"
    @State private var controllerAccelReadout = "No accelerometer samples"
    @State private var externalDisplays = 0
    @State private var spatialSceneConnected = false
    private let statusTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State private var motionAvailable = CMMotionManager().isDeviceMotionAvailable
    @State private var phoneGyroAvailable = CMMotionManager().isGyroAvailable
    @State private var phoneAccelAvailable = CMMotionManager().isAccelerometerAvailable

    private func refresh() {
        // Do not invent an XREAL HID motion device: this list contains only
        // controllers that the public GameController framework actually sees.
        controllers = GCController.controllers()
        updateControllerSamples()
        externalDisplays = max(0, UIScreen.screens.count - 1)
        spatialSceneConnected = LCUtils.appGroupUserDefault.bool(forKey: "LCPlusSpatialExternalConnected")
        let phone = CMMotionManager()
        motionAvailable = phone.isDeviceMotionAvailable
        phoneGyroAvailable = phone.isGyroAvailable
        phoneAccelAvailable = phone.isAccelerometerAvailable
    }


    private func updateControllerSamples() {
        guard source == 2, controllers.indices.contains(controllerIndex),
              let m = controllers[controllerIndex].motion else {
            controllerGyroReadout = "Unavailable (no GameController motion profile)"
            controllerAccelReadout = "Unavailable (no GameController motion profile)"
            return
        }
        if m.sensorsRequireManualActivation && !m.sensorsActive { m.sensorsActive = true }
        if m.hasRotationRate {
            let r = m.rotationRate
            controllerGyroReadout = String(format: "x %.3f · y %.3f · z %.3f rad/s", r.x, r.y, r.z)
        } else {
            controllerGyroReadout = "Gyroscope not exposed to iOS"
        }
        if m.hasGravityAndUserAcceleration {
            let a = m.acceleration
            controllerAccelReadout = String(format: "x %.3f · y %.3f · z %.3f g", a.x, a.y, a.z)
        } else {
            controllerAccelReadout = "Accelerometer not exposed to iOS"
        }
    }

    private func capability(_ controller: GCController) -> String {
        guard let m = controller.motion else { return "Connected • no motion profile" }
        let gyro = m.hasRotationRate ? "Gyro available" : "No gyro exposed"
        let accel = m.hasGravityAndUserAcceleration ? "Accelerometer/gravity available" : "No accelerometer exposed"
        let orientation = m.hasAttitude ? "Attitude available" : "No absolute attitude"
        return "\(gyro) • \(accel) • \(orientation)"
    }

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Enable spatial output", isOn: $enabled)
                    .onChange(of: enabled) { _ in
                        if #available(iOS 16.0, *) { LCPlusSpatialCoordinator.shared.refresh() }
                    }
                Text("Leave LiveContainer and apps interactive on your iPhone. When an external display connects, the spatial screen appears there automatically—no full-screen phone viewer.")
                    .font(.footnote).foregroundStyle(.secondary)
                if enabled && externalDisplays == 0 {
                    Text("Connect your XREAL glasses to begin external spatial output.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Picker("Picture mode", selection: $renderMode) {
                    Text("Normal spatial desktop (2D)").tag(0)
                    Text("Side-by-side stereo test").tag(1)
                }
                HStack {
                    Label("Connected external screens", systemImage: "display")
                    Spacer()
                    Text("\(externalDisplays)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Spatial display scene")
                    Spacer()
                    Text(spatialSceneConnected ? "Connected" : "Not connected")
                        .foregroundColor(spatialSceneConnected ? .green : .secondary)
                }
                Text("External-only output attempts to show the currently active LiveContainer app, whether launched normally or in multitasking. If the scene is not connected, the glasses may simply mirror the phone.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Screen framing", selection: $framing) {
                    Text("Fill external view (crops edges)").tag(0)
                    Text("Fit whole phone screen").tag(1)
                }
                HStack {
                    Text("Spatial zoom")
                    Spacer()
                    Text(String(format: "%.2fx", zoom)).foregroundStyle(.secondary)
                }
                Slider(value: $zoom, in: 1.0...2.5, step: 0.05)
                Text("The external scene is a full-canvas view with head-following perspective, not a floating phone window. Fit preserves all content; Fill crops to the glasses' widescreen aspect ratio. You still interact using the live iPhone screen.")
                    .font(.footnote).foregroundStyle(.secondary)
                if renderMode == 1 {
                    Text("Stereo test renders two shifted copies of the flat phone view on the external screen. It requires a supported full-SBS display mode for correct separation and does not turn a 2D app into real 3D. If your XREAL displays two tiny images, select 2D instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text("Stereo plane separation")
                        Spacer()
                        Text(String(format: "%.3f", eyeSeparation)).foregroundStyle(.secondary)
                    }
                    Slider(value: $eyeSeparation, in: 0...0.08, step: 0.002)
                }
            }
            Section("Gyro input") {
                Picker("Motion source", selection: $source) {
                    Text("iPhone gyroscope").tag(0)
                    Text("Sensor bridge (UDP)").tag(1)
                    Text("Bluetooth game controller").tag(2)
                    Text("XREAL Air (experimental discovery)").tag(3)
                }
                Button {
                    // The host renderer sees this shared-default nonce on its next
                    // display tick, and takes the next valid sensor orientation as
                    // the new forward-facing reference for the current source.
                    recenterNonce = recenterNonce == Int.max ? 0 : recenterNonce + 1
                } label: {
                    Label("Reset View (Look Straight Ahead)", systemImage: "scope")
                }
                .disabled(!enabled)
                Text("Look straight ahead and tap Reset View. The current tracker position becomes forward, even if the Joy-Con is mounted on the side of the glasses. Requires motion data from the selected device.")
                    .font(.footnote).foregroundStyle(.secondary)
                if source == 0 {
                    Text("Gyroscope: \(phoneGyroAvailable ? "Available" : "Unavailable")")
                    Text("Accelerometer: \(phoneAccelAvailable ? "Available" : "Unavailable")")
                    Text("Fused orientation: \(motionAvailable ? "Available" : "Unavailable")")
                        .foregroundStyle(.secondary)
                    Text("For headset tracking, the phone would need to be attached to your head. This setting tracks the phone, not the glasses.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if source == 1 {
                    Stepper("UDP port \(port)", value: $port, in: 1024...65535)
                    Text("Send absolute angles as JSON to the phone's local IP: {\"yaw\":10,\"pitch\":0}. Refresh by turning Spatial Output off and on after a port change. Trusted networks only.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if source == 2 {
                    if controllers.isEmpty {
                        Text("No controllers detected. Pair a Joy-Con in iOS Bluetooth settings, then Refresh devices.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Picker("Controller", selection: $controllerIndex) {
                            ForEach(controllers.indices, id: \.self) { idx in
                                Text("\(controllers[idx].vendorName ?? "Controller") #\(idx + 1)").tag(idx)
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Selected controller live motion").font(.subheadline).bold()
                            Text("Gyro: \(controllerGyroReadout)")
                            Text("Accel: \(controllerAccelReadout)")
                            Text("At rest, gyroscope values should be close to zero. Tilt the controller: an exposed accelerometer should change. If it says 'not exposed', Bluetooth pairing alone won't unlock it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        ForEach(controllers.indices, id: \.self) { idx in
                            let c = controllers[idx]
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(c.vendorName ?? "Controller") #\(idx + 1)")
                                Text(capability(c)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Gyro + accelerometer support is checked separately. If iOS exposes rotation rates and gravity, the tracker uses both to stabilize tilt. With accelerometer only, left/right yaw cannot be tracked. A paired Joy-Con often exposes neither through GameController; this cannot be fixed by a Swift setting or by reading the iPhone's sensors.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    let found = controllers.indices.filter { idx in
                        let name = (controllers[idx].vendorName ?? "").lowercased()
                        return name.contains("xreal") || name.contains("nreal")
                    }
                    if found.isEmpty {
                        Text("No XREAL motion device discovered through GameController.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(found, id: \.self) { idx in
                            let c = controllers[idx]
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Detected: \(c.vendorName ?? "XREAL") #\(idx + 1)")
                                Text(capability(c)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("This checks whether iOS unexpectedly exposes the glasses as a GameController motion device. It cannot read raw USB HID sensor reports. With current public APIs, XREAL tracking is expected to be unavailable; use a bridge if none appears.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Refresh connected devices") { refresh() }
                HStack {
                    Text("Movement sensitivity")
                    Spacer()
                    Text(String(format: "%.1fx", sensitivity)).foregroundStyle(.secondary)
                }
                Slider(value: $sensitivity, in: 0.2...3, step: 0.1)
            }
            Section("Calibration notes") {
                Text("Reconnecting a display also resets forward. Automatic wear recentering requires a UDP bridge reporting worn:false then worn:true; attaching a Joy-Con cannot detect removal of the glasses.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Compatibility") {
                Text("The external mode attempts to capture the current LiveContainer/guest phone window at up to 12 fps. Screen framing is full-canvas but not a true 3D environment. Use the phone to interact. Secure, Metal, and some LiveProcess surfaces may be black or stale. This is NOT 60 fps VR, and stereo mode cannot force the XREAL's 3840×1080 3D mode.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spatial Display")
        .onAppear {
            refresh()
            if #available(iOS 16.0, *) { LCPlusSpatialCoordinator.shared.start() }
        }
        .onReceive(statusTimer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.didConnectNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.didDisconnectNotification)) { _ in refresh() }
    }
}
