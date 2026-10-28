//
//  LCPlusMultitaskSettings.swift — LiveContainer Plus
//  Section shown at the bottom of Settings → Multitask.
//
import SwiftUI

struct LCPlusMultitaskSection: View {
    @AppStorage("LCPlusMultiInstance", store: LCUtils.appGroupUserDefault) private var multiInstance = true
    @AppStorage("LCPlusMixAudio", store: LCUtils.appGroupUserDefault) private var mixAudio = true
    @AppStorage("LCPlusDefaultScale", store: LCUtils.appGroupUserDefault) private var scale = 1.0
    @AppStorage("LCPlusAutoHideBars", store: LCUtils.appGroupUserDefault) private var autoHideBars = true
    @AppStorage("LCPlusFullScreenCollapsed", store: LCUtils.appGroupUserDefault) private var fullScreenCollapsed = true
    @AppStorage("LCPlusSnapGrid", store: LCUtils.appGroupUserDefault) private var grid = 0
    @AppStorage("LCPlusSnapCols", store: LCUtils.appGroupUserDefault) private var cols = 3
    @AppStorage("LCPlusSnapRows", store: LCUtils.appGroupUserDefault) private var rows = 2
    @AppStorage("LCPlusSnapThreshold", store: LCUtils.appGroupUserDefault) private var threshold = 20.0
    @AppStorage("LCPlusSmartSnap", store: LCUtils.appGroupUserDefault) private var smartSnap = true
    @AppStorage("LCPlusSnapMid", store: LCUtils.appGroupUserDefault) private var snapMid = true
    @AppStorage("LCPlusEdgeDrop", store: LCUtils.appGroupUserDefault) private var edgeDrop = true

    var body: some View {
        Section {
            Toggle("Multiple instances per app", isOn: $multiInstance)
            Toggle("Audio in multiple windows", isOn: $mixAudio)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Window scale")
                    Spacer()
                    Text(String(format: "%.2fx", scale)).foregroundColor(.secondary).font(.caption)
                }
                Slider(value: $scale, in: 0.5...2.0, step: 0.05)
            }
            .padding(.vertical, 4)

            Toggle("Hide window bars when dock is collapsed", isOn: $autoHideBars)
            Toggle("Full-screen windows when dock is collapsed", isOn: $fullScreenCollapsed)

            Picker("Snap grid", selection: $grid) {
                Text("Off").tag(0)
                Text("Halves (2 × 1)").tag(1)
                Text("Thirds (3 × 1)").tag(2)
                Text("Fourths (4 × 1)").tag(3)
                Text("Quarters (2 × 2)").tag(4)
                Text("Ninths (3 × 3)").tag(5)
                Text("Sixteenths (4 × 4)").tag(6)
                Text("Custom").tag(7)
            }
            if grid == 7 {
                Stepper("Columns: \(cols)", value: $cols, in: 1...8)
                Stepper("Rows: \(rows)", value: $rows, in: 1...8)
            }
            Toggle("Smart snap", isOn: $smartSnap)
            Toggle("Snap to screen center", isOn: $snapMid)
            Toggle("Snap to half at screen edges", isOn: $edgeDrop)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Snap strength")
                    Spacer()
                    Text(threshold == 0 ? "Off" : "\(Int(threshold)) pt").foregroundColor(.secondary).font(.caption)
                }
                Slider(value: $threshold, in: 0...40, step: 1)
            }
            .padding(.vertical, 4)
        } header: {
            Text("LiveContainer Plus")
        }
    }
}
