//
//  LCPlusCore.swift — added by LC Plus (always applied)
//
import SwiftUI
import UIKit

enum LCPlus {
    static var defaults: UserDefaults { LCUtils.appGroupUserDefault }

    static func bool(_ key: String, _ def: Bool) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? def
    }

    static func double(_ key: String, _ def: Double) -> Double {
        (defaults.object(forKey: key) as? Double) ?? def
    }

    static func int(_ key: String, _ def: Int) -> Int {
        (defaults.object(forKey: key) as? Int) ?? def
    }
}
