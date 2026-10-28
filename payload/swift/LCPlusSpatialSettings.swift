// LiveContainer Plus — experimental spatial output controls.
// Only controllers that actually publish motion to GameController can be used.
import SwiftUI
import UIKit
import GameController
import CoreMotion

struct LCPlusSpatialSettingsView: View {
    @AppStorage("LCPlusSpatialEnabled", store: LCUtils.appGroupUserDefault)
    private var enabled = false
    @AppStorage("LCPlusSpatialRequireDisplay", store: LCUtils.appGroupUserDefault)
    private var requireDisplay = true
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
    @AppStorage("LCPlusSpatialPort", store: LCUtils.appGroupUserDefault)
    private var port = 38271
    @AppStorage("LCPlusSpatialRecenter", store: LCUtils.appGroupUserDefault)
    private var recenterNonce = 0
    @State private var controllers: [GCController] = []
    @State private var externalDisplays = 0
    @State private var motionAvailable = CMMotionManager().isDeviceMotionAvailable

    private func refresh() {
        // Do not invent an XREAL HID motion device: this list contains only
        // controllers that the public GameController framework actually sees.
        controllers = GCController.controllers()
        externalDisplays = max(0, UIScreen.screens.count - 1)
        motionAvailable = CMMotionManager().isDeviceMotionAvailable
    }

    private func capability(_ controller: GCController) -> String {
        guard let m = controller.motion else { return "Connected • no motion profile" }
        if m.hasAttitude { return "Orientation available" }
        if m.hasRotationRate { return "Gyro rates only • relative tracking (drifts)" }
        return "Motion profile has no usable orientation"
    }

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Enable spatial output", isOn: $enabled)
                Picker("Picture mode", selection: $renderMode) {
                    Text("Normal spatial desktop (2D)").tag(0)
                    Text("Side-by-side stereo test").tag(1)
                }
                HStack {
                    Label("Connected external screens", systemImage: "display")
                    Spacer()
                    Text("\(externalDisplays)").foregroundStyle(.secondary)
                }
                Toggle("Only run with an external screen", isOn: $requireDisplay)
                if renderMode == 1 {
                    Text("Stereo test mirrors the iPhone picture as two eye views. The original XREAL Air normally requires a 3840×1080 Full-SBS signal and manual 3D-mode switching; iPhone mirroring may not negotiate this. If both eyes show two pictures, turn the mode off. Guest window snapshots may be incomplete.")
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
                    Label(motionAvailable ? "iPhone motion available" : "Phone motion unavailable", systemImage: motionAvailable ? "checkmark.circle" : "xmark.circle")
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
                        ForEach(controllers.indices, id: \.self) { idx in
                            let c = controllers[idx]
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(c.vendorName ?? "Controller") #\(idx + 1)")
                                Text(capability(c)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("A paired Joy-Con might show as a controller but offer no accessible gyro in iOS. Tracking only starts if its GCMotion profile provides orientation. The list is a diagnostic, not a raw Bluetooth HID reader.")
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
                Text("Processes LiveContainer multitask windows locally. Does not capture arbitrary iOS apps outside LiveContainer. Side-by-side is an experimental snapshot compositor, not full SteamVR, 6DoF or full-resolution 3D. The current output path uses iPhone display mirroring and cannot force an XREAL 3D display mode.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Spatial Display")
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: GCControllerDidConnect)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: GCControllerDidDisconnect)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.didConnectNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.didDisconnectNotification)) { _ in refresh() }
    }
}
