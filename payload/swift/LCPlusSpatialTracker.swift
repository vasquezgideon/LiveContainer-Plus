// LiveContainer Plus: motion tracking for the independent external-display scene.
// This is a 3DoF 2D screen-plane experiment, not an OpenXR or native XREAL 3D driver.
// Sensor state is shared by the external renderer; the phone remains interactive.
import SwiftUI
import UIKit
import CoreMotion
import GameController
import Network
import Combine

@MainActor
final class LCPlusViewerTracker: ObservableObject {
    @Published private(set) var yaw: Double = 0
    @Published private(set) var pitch: Double = 0
    @Published private(set) var status = "Starting sensor…"
    @Published private(set) var gyroDetected = false
    @Published private(set) var accelerometerDetected = false

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
    private var gravityPitchBase: Double?
    private var lastGyroPitch = 0.0
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
        gravityPitchBase = nil
        lastGyroPitch = 0
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
        guard let m = c.motion else {
            gyroDetected = false
            accelerometerDetected = false
            return false
        }
        gyroDetected = m.hasRotationRate
        accelerometerDetected = m.hasGravityAndUserAcceleration
        if m.sensorsRequireManualActivation { m.sensorsActive = true }
        guard m.hasAttitude || m.hasRotationRate || m.hasGravityAndUserAcceleration else { return false }
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
            if m.hasRotationRate {
                let rate = m.rotationRate
                guard rate.x.isFinite && rate.z.isFinite else { return false }
                accumulatedYaw = wrap(accumulatedYaw + rate.z * dt)
                accumulatedPitch = wrap(accumulatedPitch + rate.x * dt)
                lastGyroPitch = accumulatedPitch
            }
            if m.hasGravityAndUserAcceleration {
                let g = m.gravity
                // Gravity provides a stable tilt reference, but NEVER an absolute yaw.
                // This is a relative tilt estimate; mount orientation affects axes.
                let norm = sqrt(g.x*g.x + g.y*g.y + g.z*g.z)
                if norm.isFinite && norm > 0.1 {
                    let tilt = atan2(-g.x, sqrt(g.y*g.y + g.z*g.z))
                    if gravityPitchBase == nil { gravityPitchBase = tilt }
                    let tiltDelta = wrap(tilt - (gravityPitchBase ?? tilt))
                    if m.hasRotationRate {
                        // Complementary fusion: gyro makes movement responsive,
                        // gravity slowly compensates pitch drift, not yaw drift.
                        accumulatedPitch = wrap(accumulatedPitch +
                            0.018 * wrap(tiltDelta - accumulatedPitch))
                    } else {
                        accumulatedPitch = tiltDelta
                    }
                }
            }
            yawBase = 0
            pitchBase = 0
            apply(accumulatedYaw, accumulatedPitch)
        }
        status = m.hasAttitude ? "Controller attitude active" :
            (m.hasRotationRate ? "Controller gyro + \(m.hasGravityAndUserAcceleration ? "accel" : "drift")" :
             "Controller accelerometer-only: tilt, no yaw")
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
            gyroDetected = motion.isGyroAvailable
            accelerometerDetected = motion.isAccelerometerAvailable
            guard let sample = motion.deviceMotion else { status = "Waiting for phone motion"; return }
            apply(sample.attitude.yaw, sample.attitude.pitch)
            status = "iPhone fused gyro + accelerometer active (phone only)"
        case 1:
            if lastUDP > 0 && ProcessInfo.processInfo.systemUptime - lastUDP < 2.0 {
                apply(udpYaw, udpPitch)
                status = "UDP tracker active"
            } else if !status.contains("failed") { status = "Waiting for UDP sensor packets" }
        case 2:
            let controllers = GCController.controllers()
            guard index >= 0 && index < controllers.count else {
                gyroDetected = false; accelerometerDetected = false
                status = "No selected controller"; return
            }
            if !controllerSample(controllers[index]) {
                status = "Controller connected, no accessible gyro/accelerometer in iOS"
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

