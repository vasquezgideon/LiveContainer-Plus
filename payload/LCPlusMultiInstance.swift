//
//  LCPlusMultiInstance.swift — added by LC Plus (multi_instance group)
//  Lets the same app/container run in several multitask windows at once (up to 16).
//
import SwiftUI
import UIKit

extension LCPlus {
    static let maxInstances = 16

    static var multiInstanceEnabled: Bool { bool("LCPlusMultiInstance", true) }

    /// True when the container already has a multitask window and one more instance is allowed.
    static func canLaunchDuplicate(container: String) -> Bool {
        guard multiInstanceEnabled else { return false }
        // virtual windows only (native iPad windows are keyed by container in SwiftUI's openWindow)
        guard defaults.integer(forKey: "LCMultitaskMode") == 0 else { return false }
        let n = MultitaskManager.instanceCount(container: container)
        return n > 0 && n < maxInstances
    }

    // Each window gets its own id: "<dataUUID>" for the first, "<dataUUID>#2", "#3", ... for extra instances.
    private static var usedWindowIDs = Set<String>()

    static func allocateWindowID(for dataUUID: String) -> String {
        var candidate = dataUUID
        var n = 1
        while usedWindowIDs.contains(candidate) {
            n += 1
            candidate = "\(dataUUID)#\(n)"
        }
        usedWindowIDs.insert(candidate)
        return candidate
    }

    static func releaseWindowID(_ id: String) {
        usedWindowIDs.remove(id)
    }

    static func baseUUID(_ windowID: String) -> String {
        windowID.components(separatedBy: "#").first ?? windowID
    }
}

@available(iOS 16.0, *)
extension MultitaskDockManager {
    @objc(lcPlusAllocateWindowID:)
    func lcPlusAllocateWindowID(_ dataUUID: String) -> String {
        LCPlus.allocateWindowID(for: dataUUID)
    }

    @objc(lcPlusReleaseWindowID:)
    func lcPlusReleaseWindowID(_ windowID: String) {
        LCPlus.releaseWindowID(windowID)
    }
}
