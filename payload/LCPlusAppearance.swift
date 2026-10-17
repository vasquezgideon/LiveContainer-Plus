//
//  LCPlusAppearance.swift — added by LC Plus (appearance group)
//  Custom background image, Liquid Glass banners (list layout) and the home-screen grid layout.
//
import SwiftUI
import UIKit
import PhotosUI

// MARK: - Background image storage

enum LCPlusBackgroundStore {
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LCPlusBackground.jpg")
    }

    private static var cache: (version: Int, image: UIImage?)?

    static func image(version: Int) -> UIImage? {
        if let c = cache, c.version == version { return c.image }
        let img = UIImage(contentsOfFile: fileURL.path)
        cache = (version, img)
        return img
    }

    static func save(_ data: Data) -> Bool {
        guard let original = UIImage(data: data) else { return false }
        let maxDim: CGFloat = 2400
        let longest = max(original.size.width, original.size.height)
        var image = original
        if longest > maxDim {
            let scale = maxDim / longest
            let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                original.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let jpg = image.jpegData(compressionQuality: 0.9) else { return false }
        do {
            try jpg.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Background view + theme

struct LCPlusBackground: View {
    @AppStorage("LCPlusBackgroundMode", store: LCUtils.appGroupUserDefault) private var mode = 0 // 0 black, 1 image, 2 system
    @AppStorage("LCPlusBackgroundVersion", store: LCUtils.appGroupUserDefault) private var version = 0

    var body: some View {
        ZStack {
            if mode == 2 {
                Color(UIColor.systemGroupedBackground)
            } else {
                Color.black
                if mode == 1, let img = LCPlusBackgroundStore.image(version: version) {
                    GeometryReader { geo in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct LCPlusThemeModifier: ViewModifier {
    @AppStorage("LCPlusBackgroundMode", store: LCUtils.appGroupUserDefault) private var mode = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if mode == 2 {
            content
        } else if #available(iOS 16.0, *) {
            content
                .environment(\.colorScheme, .dark)
                .toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            content.environment(\.colorScheme, .dark)
        }
    }
}

/// Lets the custom background show through List / Form / ScrollView pages (Settings, Sources, Tweaks, sub-pages)
struct LCPlusPageBackground: ViewModifier {
    @AppStorage("LCPlusBackgroundMode", store: LCUtils.appGroupUserDefault) private var mode = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if mode == 2 {
            content
        } else if #available(iOS 16.0, *) {
            content
                .scrollContentBackground(.hidden)
                .background(LCPlusBackground())
                .modifier(LCPlusThemeModifier())
        } else {
            content
                .background(LCPlusBackground())
                .modifier(LCPlusThemeModifier())
        }
    }
}

extension View {
    func lcPlusPageBackground() -> some View {
        modifier(LCPlusPageBackground())
    }
}

// MARK: - Home layout (list = stock banners with glass, grid = home-screen style)

struct LCPlusAppsLayout<Banner: View>: View {
    let apps: [LCAppModel]
    let openSettings: (LCAppModel) -> Void
    let banner: (LCAppModel) -> Banner

    @AppStorage("LCPlusLayout", store: LCUtils.appGroupUserDefault) private var layout = 0          // 0 list, 1 grid
    @AppStorage("LCPlusGridSize", store: LCUtils.appGroupUserDefault) private var gridSize = 0       // 0 normal, 1 large, 2 xl, 3 custom
    @AppStorage("LCPlusGridColumns", store: LCUtils.appGroupUserDefault) private var customColumns = 4
    @AppStorage("LCPlusGridShowNames", store: LCUtils.appGroupUserDefault) private var showNames = true

    init(apps: [LCAppModel],
         openSettings: @escaping (LCAppModel) -> Void,
         @ViewBuilder banner: @escaping (LCAppModel) -> Banner) {
        self.apps = apps
        self.openSettings = openSettings
        self.banner = banner
    }

    private var columnCount: Int {
        switch gridSize {
        case 0: return 4
        case 1: return 3
        case 2: return 2
        default: return max(1, min(8, customColumns))
        }
    }

    private var iconSize: CGFloat {
        let spacing: CGFloat = 16
        let totalWidth = UIScreen.main.bounds.width - 32
        let cell = (totalWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        return min(max(cell * 0.86, 36), 180)
    }

    var body: some View {
        if layout == 1 {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columnCount),
                spacing: 22
            ) {
                ForEach(apps, id: \.self) { app in
                    LCPlusGridCell(model: app, openSettings: openSettings, showName: showNames, iconSize: iconSize)
                }
            }
        } else {
            LazyVStack {
                ForEach(apps, id: \.self) { app in
                    banner(app)
                }
                .transition(.scale)
            }
        }
    }
}

struct LCPlusGridCell: View {
    @ObservedObject var model: LCAppModel
    let openSettings: (LCAppModel) -> Void
    let showName: Bool
    let iconSize: CGFloat

    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false
    @State private var errorMessage: String? = nil

    var body: some View {
        Button(action: launch) {
            VStack(spacing: 6) {
                Image(uiImage: model.appInfo.iconIsDarkIcon(darkModeIcon) ?? UIImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                if showName {
                    Text(model.displayName)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: iconSize + 12)
                }
            }
            .opacity(model.isSigningInProgress ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                openSettings(model)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                run(multitask: true)
            } label: {
                Label("Run in window", systemImage: "rectangle.on.rectangle")
            }
            Button {
                run(multitask: false)
            } label: {
                Label("Run full screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }
        .alert("Couldn't launch", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func launch() {
        run(multitask: nil)
    }

    private func run(multitask: Bool?) {
        Task {
            do {
                if model.appInfo.isLocked && !DataManager.shared.model.isHiddenAppUnlocked {
                    if !(try await LCUtils.authenticateUser()) {
                        return
                    }
                }
                try await model.runApp(multitask: multitask)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Liquid Glass for stock banners (list layout only)

extension LCAppBannerRootView {
    private static var lcPlusGlassTag: Int { 0x4C5001 }

    /// Adds an (initially empty) effect view underneath the banner's colour layer.
    func lcPlusInstallGlass(below background: UIView) {
        guard viewWithTag(Self.lcPlusGlassTag) == nil else { return }
        let glass = UIVisualEffectView(effect: nil)
        glass.tag = Self.lcPlusGlassTag
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.isUserInteractionEnabled = false
        glass.layer.cornerRadius = 22
        glass.layer.cornerCurve = .continuous
        glass.clipsToBounds = true
        insertSubview(glass, belowSubview: background)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Called after the stock code sets the banner colour. With glass on we replace that opaque colour
    /// by real Liquid Glass (iOS 26+) or a thin material (older iOS), tinted by the slider.
    func lcPlusApplyGlass(on background: UIView, tint: UIColor) {
        guard let glassView = viewWithTag(Self.lcPlusGlassTag) as? UIVisualEffectView else { return }
        guard LCPlus.bool("LCPlusGlassEnabled", true) else {
            glassView.effect = nil
            glassView.isHidden = true
            return
        }
        glassView.isHidden = false
        let strength = CGFloat(LCPlus.double("LCPlusGlassStrength", 0.15))
        if #available(iOS 26.0, *), SharedModel.isLiquidGlassEnabled {
            let glass = UIGlassEffect()
            glass.isInteractive = false
            glass.tintColor = strength > 0.001 ? tint.withAlphaComponent(strength) : nil
            glassView.effect = glass
            background.backgroundColor = .clear
        } else {
            glassView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            background.backgroundColor = tint.withAlphaComponent(strength)
        }
    }
}

// SwiftUI banner background, used by LiveContainer releases whose banner is still a SwiftUI view
struct LCPlusBannerBackground: View {
    let fallback: Color
    let tint: Color

    @AppStorage("LCPlusGlassEnabled", store: LCUtils.appGroupUserDefault) private var enabled = true
    @AppStorage("LCPlusGlassStrength", store: LCUtils.appGroupUserDefault) private var strength = 0.15

    var body: some View {
        if !enabled {
            RoundedRectangle(cornerSize: CGSize(width: 22, height: 22)).fill(fallback)
        } else if #available(iOS 26.0, *), SharedModel.isLiquidGlassEnabled {
            Color.clear
                .glassEffect(strength > 0.001 ? .regular.tint(tint.opacity(strength)) : .regular,
                             in: .rect(cornerRadius: 22))
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.opacity(strength)))
        }
    }
}

// MARK: - Settings → Appearance (LC Plus)

struct LCPlusAppearanceSettingsView: View {
    @AppStorage("LCPlusBackgroundMode", store: LCUtils.appGroupUserDefault) private var mode = 0
    @AppStorage("LCPlusBackgroundVersion", store: LCUtils.appGroupUserDefault) private var version = 0
    @AppStorage("LCPlusLayout", store: LCUtils.appGroupUserDefault) private var layout = 0
    @AppStorage("LCPlusGridSize", store: LCUtils.appGroupUserDefault) private var gridSize = 0
    @AppStorage("LCPlusGridColumns", store: LCUtils.appGroupUserDefault) private var customColumns = 4
    @AppStorage("LCPlusGridShowNames", store: LCUtils.appGroupUserDefault) private var showNames = true
    @AppStorage("LCPlusGlassEnabled", store: LCUtils.appGroupUserDefault) private var glassEnabled = true
    @AppStorage("LCPlusGlassStrength", store: LCUtils.appGroupUserDefault) private var glassStrength = 0.15

    var body: some View {
        List {
            Section {
                Picker("Background", selection: $mode) {
                    Text("Black").tag(0)
                    Text("Image").tag(1)
                    Text("System default").tag(2)
                }
                if mode == 1 {
                    if #available(iOS 16.0, *) {
                        LCPlusPhotoPickerRow(version: $version)
                    } else {
                        Text("Picking an image needs iOS 16 or later.").foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Background")
            } footer: {
                Text("Black is the default. The background shows on the app list, Sources, Tweaks and Settings pages. With an image, the app list and its Liquid Glass bars sit on top of it.")
            }

            Section {
                Picker("Layout", selection: $layout) {
                    Text("List").tag(0)
                    Text("Grid").tag(1)
                }
                .pickerStyle(.segmented)
                if layout == 1 {
                    Picker("Grid size", selection: $gridSize) {
                        Text("Normal (4 wide)").tag(0)
                        Text("Large (3 wide)").tag(1)
                        Text("XL (2 wide)").tag(2)
                        Text("Custom").tag(3)
                    }
                    if gridSize == 3 {
                        Stepper("Columns: \(customColumns)", value: $customColumns, in: 1...8)
                    }
                    Toggle("Show app names", isOn: $showNames)
                }
            } header: {
                Text("Home layout")
            } footer: {
                Text("Grid works like the Home Screen: tap an icon to launch, long-press for settings. XL without names is a 2-wide grid of big icons.")
            }

            Section {
                Toggle("Liquid Glass banners", isOn: $glassEnabled)
                if glassEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tint")
                            Spacer()
                            Text("\(Int(glassStrength * 100))%").foregroundColor(.secondary).font(.caption)
                        }
                        Slider(value: $glassStrength, in: 0...0.6)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Liquid Glass (list layout)")
            } footer: {
                Text("On iOS 26 the glass follows your system setting (Settings → Display & Brightness → Liquid Glass: Clear or Tinted). The slider adds extra colour on top; set it to 0 for pure system glass. Older iOS versions get a blurred material.")
            }
        }
        .lcPlusPageBackground()
        .navigationTitle("Appearance (LC Plus)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@available(iOS 16.0, *)
struct LCPlusPhotoPickerRow: View {
    @Binding var version: Int
    @State private var item: PhotosPickerItem? = nil
    @State private var message = ""

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label("Choose image…", systemImage: "photo")
        }
        .onChange(of: item) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), LCPlusBackgroundStore.save(data) {
                    await MainActor.run {
                        version += 1
                        message = ""
                    }
                } else {
                    await MainActor.run { message = "Couldn't load that image." }
                }
            }
        }
        if !message.isEmpty {
            Text(message).foregroundColor(.red).font(.caption)
        }
        Button(role: .destructive) {
            LCPlusBackgroundStore.remove()
            version += 1
        } label: {
            Label("Remove image", systemImage: "trash")
        }
    }
}
