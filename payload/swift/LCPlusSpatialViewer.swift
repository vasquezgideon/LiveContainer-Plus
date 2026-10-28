// LiveContainer Plus: visible spatial viewer for the phone / mirrored XREAL display.
// This is a 3DoF 2D screen-plane experiment, not an OpenXR or native XREAL 3D driver.
// Importantly, this viewer starts without waiting for a multitask guest window.
import SwiftUI
import UIKit
import CoreMotion
import GameController
import Network
import Combine

@MainActor
private final class LCPlusViewerTracker: ObservableObject {
    @Published private(set) var yaw: Double = 0
    @Published private(set) var pitch: Double = 0
    @Published private(set) var status = "Starting sensor…"

    private let motion = CMMotionManager()
    private var timer: Timer?
    private var listener: NWListener?
    private var previousSource = -1
    private var previousController = -1
    private var lastRecenterNonce = -1
    private var yawBase: Double?
    private var pitchBase: Double?
    private var referenceQuaternion: GCQuaternion?
    private var lastPoll: TimeInterval = 0
    private var accumulatedYaw = 0.0
    private var accumulatedPitch = 0.0
    private var udpYaw = 0.0
    private var udpPitch = 0.0
    private var lastUDP = 0.0
    private var previouslyWorn: Bool?

    func start() {
        guard timer == nil else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
        sample()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        motion.stopDeviceMotionUpdates()
        listener?.cancel(); listener = nil
        previousSource = -1
        previousController = -1
    }

    func recenter() {
        yawBase = nil
        pitchBase = nil
        referenceQuaternion = nil
        accumulatedYaw = 0
        accumulatedPitch = 0
        lastPoll = 0
        yaw = 0
        pitch = 0
    }

    private func wrap(_ a: Double) -> Double { atan2(sin(a), cos(a)) }

    private func apply(_ y: Double, _ p: Double) {
        guard y.isFinite && p.isFinite else { return }
        if yawBase == nil { yawBase = y; pitchBase = p }
        let ny = wrap(y - (yawBase ?? y))
        let np = wrap(p - (pitchBase ?? p))
        if abs(yaw - ny) > 0.00002 || abs(pitch - np) > 0.00002 {
            yaw = ny
            pitch = np
        }
    }

    private func configureUDP() {
        listener?.cancel(); listener = nil
        let value = LCPlus.int("LCPlusSpatialPort", 38271)
        guard value >= 1024 && value <= 65535,
              let port = NWEndpoint.Port(rawValue: UInt16(value)) else {
            status = "Invalid UDP port"
            return
        }
        do {
            let newListener = try NWListener(using: .udp, on: port)
            newListener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: DispatchQueue.global(qos: .userInitiated))
                self?.receive(on: connection)
            }
            newListener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in self?.status = "UDP listener failed" }
                }
            }
            newListener.start(queue: DispatchQueue.global(qos: .userInitiated))
            listener = newListener
        } catch { status = "UDP port cannot open" }
    }

    nonisolated private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data, data.count <= 512,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let y = object["yaw"] as? Double,
               let p = object["pitch"] as? Double,
               y.isFinite, p.isFinite, abs(y) < 360_000, abs(p) < 360_000 {
                let worn = object["worn"] as? Bool
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let worn, let previous = self.previouslyWorn, worn && !previous { self.recenter() }
                    if let worn { self.previouslyWorn = worn }
                    self.udpYaw = y * .pi / 180
                    self.udpPitch = p * .pi / 180
                    self.lastUDP = ProcessInfo.processInfo.systemUptime
                }
            }
            if error == nil { self?.receive(on: connection) }
            else { connection.cancel() }
        }
    }

    private func controllerSample(_ c: GCController) -> Bool {
        guard let m = c.motion, m.hasAttitude || m.hasRotationRate else { return false }
        if m.sensorsRequireManualActivation { m.sensorsActive = true }
        if m.hasAttitude {
            let q = m.attitude
            let length = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w)
            guard length.isFinite, length > 0.5 else { return false }
            let current = GCQuaternion(x: q.x / length, y: q.y / length,
                                       z: q.z / length, w: q.w / length)
            if referenceQuaternion == nil { referenceQuaternion = current }
            guard let base = referenceQuaternion else { return false }
            // Relative quaternion. A side-mounted controller needs reference
            // calibration; full axis alignment depends on physical placement.
            let x = current.w * -base.x + current.x * base.w + current.y * -base.z - current.z * -base.y
            let y = current.w * -base.y - current.x * -base.z + current.y * base.w + current.z * -base.x
            let z = current.w * -base.z + current.x * -base.y - current.y * -base.x + current.z * base.w
            let w = current.w * base.w - current.x * -base.x - current.y * -base.y - current.z * -base.z
            let newYaw = atan2(2 * (w*z + x*y), 1 - 2 * (y*y + z*z))
            let newPitch = asin(max(-1.0, min(1.0, 2 * (w*y - z*x))))
            // Delta is already referenced to straight ahead; do not re-center
            // it again using a separate Euler baseline.
            yawBase = 0
            pitchBase = 0
            apply(newYaw, newPitch)
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            let dt = lastPoll > 0 ? min(0.1, max(0, now - lastPoll)) : 0
            lastPoll = now
            let rate = m.rotationRate
            guard rate.x.isFinite && rate.z.isFinite else { return false }
            accumulatedYaw += rate.z * dt
            accumulatedPitch += rate.x * dt
            // Gyro-only modes drift and may need axis remapping.
            yawBase = 0
            pitchBase = 0
            apply(accumulatedYaw, accumulatedPitch)
        }
        status = "Controller motion active"
        return true
    }

    private func sample() {
        let source = LCPlus.int("LCPlusSpatialTrackingSource", 0)
        let index = LCPlus.int("LCPlusSpatialControllerIndex", 0)
        let nonce = LCPlus.int("LCPlusSpatialRecenter", 0)
        if nonce != lastRecenterNonce { lastRecenterNonce = nonce; recenter() }
        if source != previousSource || (source == 2 && index != previousController) {
            previousSource = source
            previousController = index
            recenter()
            if source == 1 { configureUDP() } else { listener?.cancel(); listener = nil }
            if source != 0 { motion.stopDeviceMotionUpdates() }
        }
        switch source {
        case 0:
            guard motion.isDeviceMotionAvailable else { status = "iPhone motion unavailable"; return }
            if !motion.isDeviceMotionActive { motion.startDeviceMotionUpdates() }
            guard let sample = motion.deviceMotion else { status = "Waiting for phone motion"; return }
            apply(sample.attitude.yaw, sample.attitude.pitch)
            status = "iPhone motion active (tracks phone, not glasses)"
        case 1:
            if lastUDP > 0 && ProcessInfo.processInfo.systemUptime - lastUDP < 2.0 {
                apply(udpYaw, udpPitch)
                status = "UDP tracker active"
            } else if !status.contains("failed") { status = "Waiting for UDP sensor packets" }
        case 2:
            let controllers = GCController.controllers()
            guard index >= 0 && index < controllers.count else {
                status = "No selected controller"; return
            }
            if !controllerSample(controllers[index]) {
                status = "Controller connected, but gyro unavailable to iOS"
            }
        case 3:
            guard let xreal = GCController.controllers().first(where: {
                let name = ($0.vendorName ?? "").lowercased()
                return name.contains("xreal") || name.contains("nreal")
            }) else { status = "XREAL gyro not exposed by GameController"; return }
            if !controllerSample(xreal) { status = "XREAL detected, no motion profile" }
        default: status = "Unknown motion source"
        }
    }
}

// A visible full-screen rendering path independent of the multitasking-app hook.
// Capturing third-party LiveProcess surfaces remains limited by iOS UIKit snapshots.
// The multitasking host and persistentSystemOverlays are iOS 16+ APIs;
// annotate this entire viewer so deployment targets below iOS 16 still compile.
@available(iOS 16.0, *)
struct LCPlusSpatialViewer: View {
    let dismiss: () -> Void
    @StateObject private var tracker = LCPlusViewerTracker()
    @AppStorage("LCPlusSpatialRenderMode", store: LCUtils.appGroupUserDefault)
    private var renderMode = 0
    @AppStorage("LCPlusSpatialSensitivity", store: LCUtils.appGroupUserDefault)
    private var sensitivity = 1.0
    @AppStorage("LCPlusSpatialRecenter", store: LCUtils.appGroupUserDefault)
    private var recenterNonce = 0
    @State private var workspaceImage: UIImage?
    @State private var connectedDisplays = max(0, UIScreen.screens.count - 1)
    private let refreshClock = Timer.publish(every: 1.0 / 12.0, on: .main, in: .common).autoconnect()

    private func captureWorkspace() {
        guard let host = MultitaskDockManager.shared.windowHostingView as UIView? else {
            workspaceImage = nil
            return
        }
        let size = host.bounds.size
        let active = !MultitaskDockManager.shared.apps.isEmpty
        guard active, size.width >= 1, size.height >= 1 else {
            workspaceImage = nil
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        workspaceImage = renderer.image { _ in
            _ = host.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false)
        }
    }

    @ViewBuilder
    private func screenContent() -> some View {
        if let frame = workspaceImage {
            Image(uiImage: frame)
                .resizable()
                .scaledToFit()
                .background(Color(white: 0.06))
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 35))
                Text("Spatial Display")
                    .font(.title2.bold())
                Text("Viewer active — launch a Shared App using LiveContainer Multitask to test a hosted window.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.11))
        }
    }

    private func plane(width: CGFloat, height: CGFloat, eye: Int) -> some View {
        let fov = 46.0 * Double.pi / 180
        let x = CGFloat(max(-0.95, min(0.95, -tracker.yaw / fov * sensitivity))) * width
        let y = CGFloat(max(-0.95, min(0.95, tracker.pitch / fov * sensitivity))) * height
        let disparity: CGFloat = eye == 0 ? -5 : (eye == 1 ? 5 : 0)
        return screenContent()
            .frame(width: width * 0.78, height: height * 0.69)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.28)))
            .shadow(color: .black.opacity(0.45), radius: 16)
            .offset(x: x + disparity, y: y)
    }

    @ViewBuilder
    private func hud(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(renderMode == 1 ? "STEREO TEST" : "SPATIAL 2D")
                    .font(compact ? .caption.bold() : .subheadline.bold())
                Spacer(minLength: 4)
                Button("Exit") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Text(tracker.status)
                .lineLimit(2)
                .font(.caption2)
                .foregroundStyle(.white)
            Text(String(format: "Yaw %+.1f° · Pitch %+.1f°", tracker.yaw * 180 / .pi, tracker.pitch * 180 / .pi))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            if connectedDisplays == 0 {
                Text("No external screen — phone preview")
                    .font(.caption2).foregroundStyle(.yellow)
            }
            Spacer()
            HStack {
                Button {
                    recenterNonce = recenterNonce == Int.max ? 0 : recenterNonce + 1
                    tracker.recenter()
                } label: { Label("Reset View", systemImage: "scope") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? 8 : 18)
        .foregroundStyle(.white)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if renderMode == 1 {
                    HStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { eye in
                            ZStack {
                                Color.black
                                plane(width: geo.size.width / 2, height: geo.size.height, eye: eye)
                                hud(compact: true)
                            }
                            .frame(width: geo.size.width / 2, height: geo.size.height)
                            .clipped()
                        }
                    }
                } else {
                    ZStack {
                        plane(width: geo.size.width, height: geo.size.height, eye: -1)
                        hud(compact: false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            LCPlus.defaults.set(true, forKey: "LCPlusSpatialViewerPresented")
            tracker.start()
            captureWorkspace()
            connectedDisplays = max(0, UIScreen.screens.count - 1)
        }
        .onDisappear {
            LCPlus.defaults.set(false, forKey: "LCPlusSpatialViewerPresented")
            tracker.stop()
        }
        .onReceive(refreshClock) { _ in captureWorkspace() }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.didConnectNotification)) { _ in
            connectedDisplays = max(0, UIScreen.screens.count - 1)
            tracker.recenter()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.didDisconnectNotification)) { _ in
            connectedDisplays = max(0, UIScreen.screens.count - 1)
            tracker.recenter()
        }
    }
}
