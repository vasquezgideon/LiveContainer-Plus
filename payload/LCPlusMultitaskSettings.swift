//
//  LCPlusMultitaskSettings.swift — added by LC Plus
//  Section shown at the bottom of Settings → Multitask.
//
import SwiftUI

struct LCPlusMultitaskSection: View {
    @AppStorage("LCPlusMultiInstance", store: LCUtils.appGroupUserDefault) private var multiInstance = true
    @AppStorage("LCPlusDefaultScale", store: LCUtils.appGroupUserDefault) private var scale = 1.0
    @AppStorage("LCPlusAutoHideBars", store: LCUtils.appGroupUserDefault) private var autoHideBars = true
    @AppStorage("LCPlusSnapGrid", store: LCUtils.appGroupUserDefault) private var grid = 0
    @AppStorage("LCPlusSnapCols", store: LCUtils.appGroupUserDefault) private var cols = 3
    @AppStorage("LCPlusSnapRows", store: LCUtils.appGroupUserDefault) private var rows = 2
    @AppStorage("LCPlusSnapThreshold", store: LCUtils.appGroupUserDefault) private var threshold = 14.0
    @AppStorage("LCPlusSnapMid", store: LCUtils.appGroupUserDefault) private var snapMid = true
    @AppStorage("LCPlusEdgeDrop", store: LCUtils.appGroupUserDefault) private var edgeDrop = true

    var body: some View {
        Section {
            Toggle("Multiple instances of the same app (up to 16)", isOn: $multiInstance)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Default window scale")
                    Spacer()
                    Text(String(format: "%.2fx", scale)).foregroundColor(.secondary).font(.caption)
                }
                Slider(value: $scale, in: 0.5...2.0, step: 0.05)
            }
            .padding(.vertical, 4)

            Toggle("Hide window bars while dock is collapsed", isOn: $autoHideBars)

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
            Toggle("Snap to the screen middle", isOn: $snapMid)
            Toggle("Drop on left/right edge = 50/50 half", isOn: $edgeDrop)

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
            Text("LC Plus")
        } footer: {
            Text("Windows snap to screen edges, the middle and each other. With a snap grid on, a released window also locks to the grid cells. Use the Tile button in the dock to arrange every open window at once. The title-bar menu has presets for halves, thirds, fourths, quarters, ninths and sixteenths.")
        }
    }
}
