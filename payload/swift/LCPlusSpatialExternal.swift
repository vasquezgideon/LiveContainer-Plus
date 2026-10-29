// LiveContainer+ Spatial Display v2.8: external-only, full-canvas spatial renderer.
// The iPhone retains its native interactive view hierarchy. Touches never go to this window.
// In iOS 27+ UIKit requires a UIViewController scene accessory for external displays.
// Requires Xcode 27 SDK to compile its scene-accessory references.
import SwiftUI
import UIKit
import Combine

// Loaded through the guest boot path as well, when the SwiftUI module is present.
// A typed selector prevents the guest bootstrap from depending on Swift symbols.
@objc(LCPlusSpatialBootstrap)
final class LCPlusSpatialBootstrap: NSObject {
    @objc static func activate() {
        Task { @MainActor in
            if #available(iOS 16.0, *) { LCPlusSpatialCoordinator.shared.start() }
        }
    }
}

@available(iOS 16.0, *)
@MainActor
final class LCPlusSpatialCoordinator {
    static let shared = LCPlusSpatialCoordinator()
    private var pulse: Timer?
    private weak var registeredController: UIViewController?
    private var accessoryRegistration: Any?

    private var active: Bool {
        LCUtils.appGroupUserDefault.bool(forKey: "LCPlusSpatialEnabled")
    }

    func start() {
        guard pulse == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        pulse = t
        RunLoop.main.add(t, forMode: .common)
        refresh()
    }

    func refresh() {
        if #available(iOS 27.0, *) {
            updateSceneAccessory()
        }
    }

    // When a hosted guest presents its own controller, a registration on the
    // hidden launcher controller may no longer be eligible for presentation.
    // Keep the accessory bound to the currently visible phone controller.
    private func visibleController(_ root: UIViewController) -> UIViewController {
        var current = root
        for _ in 0..<12 {
            if let presented = current.presentedViewController, !presented.isBeingDismissed {
                current = presented
            } else if let nav = current as? UINavigationController,
                      let visible = nav.visibleViewController, visible !== current {
                current = visible
            } else if let tabs = current as? UITabBarController,
                      let selected = tabs.selectedViewController, selected !== current {
                current = selected
            } else {
                break
            }
        }
        return current
    }

    @available(iOS 27.0, *)
    private func updateSceneAccessory() {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow && !$0.isHidden })?.rootViewController
        let owner = root.map { visibleController($0) }

        // Follow the live phone controller through normal guest launches and
        // presented LiveProcess content. External windows are never targeted.
        if owner !== registeredController {
            if let previous = registeredController,
               let registration = accessoryRegistration as? UISceneAccessoryRegistration {
                previous.unregisterSceneAccessory(registration)
            }
            accessoryRegistration = nil
            registeredController = owner
        }
        guard let owner else { return }
        if accessoryRegistration == nil {
            let configuration = UISceneConfiguration()
            configuration.delegateClass = LCPlusExternalSceneDelegate.self
            let accessory = UISceneAccessory.externalNonInteractive(sceneConfiguration: configuration)
            accessoryRegistration = owner.registerSceneAccessory(accessory)
        }
        if let registration = accessoryRegistration as? UISceneAccessoryRegistration {
            registration.isEnabled = active
        }
    }
}

@available(iOS 16.0, *)
@MainActor
final class LCPlusExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var visibilityTimer: Timer?

    private func updateVisibility() {
        guard let window else { return }
        window.isHidden = !LCUtils.appGroupUserDefault.bool(forKey: "LCPlusSpatialEnabled")
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let displayScene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: displayScene)
        w.backgroundColor = .black
        w.rootViewController = UIHostingController(rootView: LCPlusSpatialExternalView())
        window = w
        updateVisibility() // The iPhone window remains the key window.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateVisibility()
        }
        visibilityTimer = t
        RunLoop.main.add(t, forMode: .common)
        LCUtils.appGroupUserDefault.set(true, forKey: "LCPlusSpatialExternalConnected")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        window?.isHidden = true
        window = nil
        LCUtils.appGroupUserDefault.set(false, forKey: "LCPlusSpatialExternalConnected")
    }
}

@available(iOS 16.0, *)
struct LCPlusSpatialExternalView: View {
    @StateObject private var tracker = LCPlusViewerTracker()
    @AppStorage("LCPlusSpatialEnabled", store: LCUtils.appGroupUserDefault)
    private var enabled = false
    @AppStorage("LCPlusSpatialRenderMode", store: LCUtils.appGroupUserDefault)
    private var renderMode = 0
    @AppStorage("LCPlusSpatialSensitivity", store: LCUtils.appGroupUserDefault)
    private var sensitivity = 1.0
    @AppStorage("LCPlusSpatialRecenter", store: LCUtils.appGroupUserDefault)
    private var recenterNonce = 0
    @AppStorage("LCPlusSpatialEyeSeparation", store: LCUtils.appGroupUserDefault)
    private var eyeSeparation = 0.028
    @AppStorage("LCPlusSpatialFraming", store: LCUtils.appGroupUserDefault)
    private var framing = 0 // 0 = fill external display, 1 = preserve the full phone frame
    @AppStorage("LCPlusSpatialZoom", store: LCUtils.appGroupUserDefault)
    private var zoom = 1.25
    @State private var snapshot: UIImage?
    private let captureTimer = Timer.publish(every: 1.0 / 12.0, on: .main, in: .common).autoconnect()

    // Capture only the iPhone's own window scenes. Never recursively capture the
    // output display window. UIKit doesn't guarantee snapshots of remotely hosted,
    // DRM, secure or Metal surfaces, and this path is NOT high-FPS VR rendering.
    private func capturePhone() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
            .flatMap { $0.windows }
            .filter { !$0.isHidden && $0.alpha > 0.01 && $0.bounds.width > 10 && $0.bounds.height > 10 }
            .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        guard let base = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            snapshot = nil
            return
        }
        let size = base.bounds.size
        guard size.width >= 40, size.height >= 40 else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(1.0, 950 / max(size.width, size.height))
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            for w in windows {
                let offset = base.convert(.zero, from: w)
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: offset.x, y: offset.y)
                if !w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) {
                    w.layer.render(in: ctx.cgContext)
                }
                ctx.cgContext.restoreGState()
            }
        }
        snapshot = image
    }

    // The external display is itself the spatial canvas; never show a second
    // rounded-card/window with a miniature copy of the phone on it.
    // "Fill" intentionally crops portrait phone content on a landscape display.
    // Use the "Fit" option when access to the entire mirrored UI is preferable.
    private func sourceCanvas(_ dimensions: CGSize) -> some View {
        ZStack {
            Color.black
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: framing == 0 ? .fill : .fit)
                    .frame(width: dimensions.width, height: dimensions.height)
                    .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "display").font(.title)
                    Text("Waiting for phone app frames")
                    Text("Keep using the app on the iPhone")
                        .font(.caption)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(width: dimensions.width, height: dimensions.height)
        .clipped()
    }

    private func spatialCanvas(_ available: CGSize, eye: Int) -> some View {
        // A large source canvas and perspective projection provide a continuous
        // head-look effect instead of a floating picture-in-picture card.
        // This is still projected 2D, NOT reconstructed stereoscopic geometry.
        let fovRadians: Double = Double.pi * 46.0 / 180.0
        let horizontalRotation: Double = max(-0.85, min(0.85, -tracker.yaw / fovRadians * sensitivity))
        let verticalRotation: Double = max(-0.85, min(0.85, tracker.pitch / fovRadians * sensitivity))
        let eyeOffset: Double = eye < 0 ? 0.0 : (eye == 0 ? -eyeSeparation / 2.0 : eyeSeparation / 2.0)
        let scale: CGFloat = CGFloat(max(1.0, min(2.5, zoom)))
        let sourceSize = CGSize(width: available.width * scale, height: available.height * scale)
        let xOffset: CGFloat = CGFloat(horizontalRotation + eyeOffset) * available.width * 0.35
        let yOffset: CGFloat = CGFloat(verticalRotation) * available.height * 0.35
        let yawAngle = Angle.radians(horizontalRotation * 0.2)
        let pitchAngle = Angle.radians(verticalRotation * 0.15)
        return sourceCanvas(sourceSize)
            .rotation3DEffect(yawAngle, axis: (x: 0, y: 1, z: 0), perspective: 0.3)
            .rotation3DEffect(pitchAngle, axis: (x: 1, y: 0, z: 0), perspective: 0.3)
            .offset(x: xOffset, y: yOffset)
    }

    var body: some View {
        GeometryReader { area in
            ZStack {
                Color.black.ignoresSafeArea()
                if enabled {
                    if renderMode == 1 {
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { i in
                                ZStack {
                                    Color.black
                                    spatialCanvas(CGSize(width: area.size.width / 2, height: area.size.height), eye: i)
                                }
                                .frame(width: area.size.width / 2, height: area.size.height)
                                .clipped()
                            }
                        }
                    } else {
                        spatialCanvas(area.size, eye: -1)
                    }
                } else {
                    Text("Enable Spatial Display on your iPhone")
                        .foregroundStyle(.white)
                }
            }
            .frame(width: area.size.width, height: area.size.height)
            .clipped()
            .ignoresSafeArea()
        }
        .onAppear {
            if enabled { tracker.start() }
            capturePhone()
        }
        .onDisappear { tracker.stop() }
        .onChange(of: enabled) { value in
            if value { tracker.start() } else { tracker.stop() }
        }
        .onReceive(captureTimer) { _ in
            if enabled { capturePhone() }
        }
    }
}
