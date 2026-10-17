#!/usr/bin/env python3
"""
LC Plus patcher.

Applies feature groups to a LiveContainer source tree by anchored edits (method names / unique
statements, never line numbers). Every group is transactional: if any anchor in the group is missing
(a LiveContainer version that changed that code) the whole group is rolled back and reported as
skipped, so the rest of the build still goes ahead.

usage: apply.py --lc <LiveContainer checkout> [--features a,b,c] [--strict] [--report report.md]
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PAYLOAD = os.path.normpath(os.path.join(HERE, "..", "payload"))

ALL_FEATURES = ["multi_instance", "snapping", "scale", "dock", "audio", "appearance"]
DEPENDS = {"dock": ["snapping"]}   # the dock's Tile button needs the snapping code

DEC_M = "MultitaskSupport/DecoratedAppSceneViewController.m"
DEC_H = "MultitaskSupport/DecoratedAppSceneViewController.h"
SCENE_M = "MultitaskSupport/AppSceneViewController.m"
MGR_SWIFT = "MultitaskSupport/MultitaskManager.swift"
DOCK_SWIFT = "MultitaskSupport/MultitaskDockView.swift"
BOOT_M = "LiveContainer/LCBootstrap.m"
LPMAIN_M = "LiveProcess/main.m"
MODEL_SWIFT = "LiveContainerSwiftUI/Models/LCAppModel.swift"
LIST_SWIFT = "LiveContainerSwiftUI/Views/AppList/LCAppListView.swift"
SETTINGS_SWIFT = "LiveContainerSwiftUI/Views/Settings/LCSettingsView.swift"
MT_SETTINGS_SWIFT = "LiveContainerSwiftUI/Views/Settings/LCMultitaskSettingView.swift"
NEW_DIR = "LiveContainerSwiftUI/LCPlus"

STOCK_NAME = "LiveContainer"
STOCK_BUNDLE_ID = "com.kdt.livecontainer"
DEFAULT_NAME = "LiveContainer Plus"
DEFAULT_BUNDLE_ID = "com.kdt.livecontainer.plus"


class PatchError(Exception):
    pass


def payload(name):
    with open(os.path.join(PAYLOAD, name), encoding="utf-8") as f:
        return f.read()


class Workspace:
    def __init__(self, root):
        self.root = root
        self.files = {}
        self.added = {}

    def snapshot(self):
        return dict(self.files), dict(self.added)

    def restore(self, snap):
        self.files, self.added = dict(snap[0]), dict(snap[1])

    def exists(self, rel):
        return rel in self.files or os.path.isfile(os.path.join(self.root, rel))

    def read(self, rel):
        if rel not in self.files:
            p = os.path.join(self.root, rel)
            if not os.path.isfile(p):
                raise PatchError("file not found: %s" % rel)
            with open(p, encoding="utf-8") as f:
                self.files[rel] = f.read()
        return self.files[rel]

    def literal(self, rel, old, new):
        text = self.read(rel)
        n = text.count(old)
        if n != 1:
            raise PatchError("%s: expected exactly 1 match of %r, found %d" % (rel, old[:70], n))
        self.files[rel] = text.replace(old, new, 1)

    def regex(self, rel, pattern, repl, flags=re.S):
        text = self.read(rel)
        ms = list(re.finditer(pattern, text, flags))
        if len(ms) != 1:
            raise PatchError("%s: expected exactly 1 match of /%s/, found %d" % (rel, pattern[:70], len(ms)))
        m = ms[0]
        out = repl(m) if callable(repl) else repl
        self.files[rel] = text[:m.start()] + out + text[m.end():]

    def regex_all(self, rel, pattern, repl, min_count=1, flags=re.S):
        text = self.read(rel)
        new, n = re.subn(pattern, repl, text, flags=flags)
        if n < min_count:
            raise PatchError("%s: expected at least %d match(es) of /%s/, found %d" % (rel, min_count, pattern[:70], n))
        self.files[rel] = new

    def has(self, rel, pattern, flags=re.S):
        return self.exists(rel) and re.search(pattern, self.read(rel), flags) is not None

    def replace_all(self, rel, old, new, min_count=1):
        text = self.read(rel)
        n = text.count(old)
        if n < min_count:
            raise PatchError("%s: expected at least %d match(es) of %r, found %d" % (rel, min_count, old[:70], n))
        self.files[rel] = text.replace(old, new)

    def insert_before(self, rel, anchor, text):
        self.literal(rel, anchor, text + anchor)

    def insert_after(self, rel, anchor, text):
        self.literal(rel, anchor, anchor + text)

    def add_file(self, rel, text):
        self.added[rel] = text

    def flush(self):
        for rel, text in list(self.files.items()) + list(self.added.items()):
            p = os.path.join(self.root, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                f.write(text)


def first_of(ws, *attempts):
    """Run alternatives (for different LiveContainer versions); the first that fully applies wins."""
    errors = []
    for fn in attempts:
        snap = ws.snapshot()
        try:
            fn()
            return
        except PatchError as e:
            ws.restore(snap)
            errors.append(str(e))
    raise PatchError(" | ".join(errors))


# --------------------------------------------------------------------------- shared ObjC pieces

def ensure_dec_helpers(ws):
    if "#pragma mark - LC Plus helpers" in ws.read(DEC_M):
        return
    ws.insert_before(DEC_M, "@implementation DecoratedAppSceneViewController\n", payload("dec_helpers.m") + "\n")


def add_dec_properties(ws, lines):
    anchor = "@property(nonatomic) NSString* dataUUID;"
    ws.insert_after(DEC_M, anchor, "\n" + "\n".join(lines))


def add_dec_methods(ws, text):
    ws.insert_before(DEC_M, "- (void)moveWindow:(UIPanGestureRecognizer*)sender {", text + "\n")


# --------------------------------------------------------------------------- groups

def g_core(ws):
    ws.add_file(NEW_DIR + "/LCPlusCore.swift", payload("LCPlusCore.swift"))


def g_settings_ui(ws):
    """Section at the bottom of Settings -> Multitask (multi-instance, scale, snap options)."""
    ws.regex(
        MT_SETTINGS_SWIFT,
        r'(Text\("lc\.settings\.hideCollapsedDock"\.loc\)\s*\}\s*\}\s*)(\}\s*(?:\.lcPlusPageBackground\(\)\s*)?\.navigationTitle\("lc\.appBanner\.multitask"\.loc\))',
        lambda m: m.group(1) + "\n            LCPlusMultitaskSection()\n        " + m.group(2),
    )
    ws.add_file(NEW_DIR + "/LCPlusMultitaskSettings.swift", payload("LCPlusMultitaskSettings.swift"))


def g_multi_instance(ws):
    # --- Swift: counting registry instead of a set
    ws.regex(
        MGR_SWIFT,
        r"usingMultitaskContainers\.removeAll\(where: \{ c in\s*return c == container\s*\}\)",
        "if let i = usingMultitaskContainers.firstIndex(of: container) {\n            usingMultitaskContainers.remove(at: i)\n        }",
    )
    ws.insert_before(
        MGR_SWIFT,
        "@objc class func isMultitasking() -> Bool {",
        "@objc(lcPlusInstanceCount:) class func instanceCount(container: String) -> Int {\n"
        "        return usingMultitaskContainers.filter { $0 == container }.count\n"
        "    }\n\n    ",
    )

    # --- host: tell the guest it may share a container that is already running
    ws.regex(
        SCENE_M,
        r"(NSMutableDictionary \*userInfo = @\{.*?\}\.mutableCopy;)",
        lambda m: m.group(1)
        + "\n    if ([MultitaskManager lcPlusInstanceCount:_dataUUID] > 0) {\n"
        "        userInfo[@\"allowDuplicate\"] = @YES; // same container already running in another window\n    }",
    )
    uniq = '[MultitaskManager lcPlusInstanceCount:self.dataUUID] > 1 ? [NSString stringWithFormat:@"%@-%@", self.dataUUID, self.identifier.UUIDString] : self.dataUUID'
    ws.literal(SCENE_M, "settings.persistenceIdentifier = self.dataUUID;",
               "settings.persistenceIdentifier = " + uniq + ";")
    # iOS < 18 scene id (optional: only present in some versions)
    if ws.has(SCENE_M, r'self\.sceneID = \[NSString stringWithFormat:@"sceneID:%@-%@", @"LiveProcess", self\.dataUUID\];'):
        ws.literal(SCENE_M,
                   'self.sceneID = [NSString stringWithFormat:@"sceneID:%@-%@", @"LiveProcess", self.dataUUID];',
                   'self.sceneID = [NSString stringWithFormat:@"sceneID:%@-%@", @"LiveProcess", ' + uniq + '];')

    # --- extension process: pass the flag on and skip the single-instance lock
    ws.insert_after(
        LPMAIN_M,
        '[lcUserDefaults setObject:appInfo[@"selectedContainer"] forKey:@"selectedContainer"];',
        '\n    if ([appInfo[@"allowDuplicate"] boolValue]) {\n'
        '        [lcUserDefaults setBool:YES forKey:@"LCAllowDuplicate"];\n'
        '    } else {\n'
        '        [lcUserDefaults removeObjectForKey:@"LCAllowDuplicate"];\n'
        '    }',
    )
    ws.regex(
        BOOT_M,
        r"\[LCSharedUtils setContainerUsingByLC:lcAppUrlScheme folderName:dataUUID auditToken:0\];",
        lambda m: 'if (![lcUserDefaults boolForKey:@"LCAllowDuplicate"]) {\n        ' + m.group(0) + "\n    }",
    )
    ws.literal(
        BOOT_M,
        "NSString* runningLC = [LCSharedUtils getContainerUsingLCSchemeWithFolderName:selectedContainer];",
        'NSString* runningLC = [lcUserDefaults boolForKey:@"LCAllowDuplicate"] ? nil : [LCSharedUtils getContainerUsingLCSchemeWithFolderName:selectedContainer];',
    )

    # --- window ids: every window gets its own dock/registry id
    add_dec_properties(ws, ["@property(nonatomic) NSString* windowID;"])
    ws.literal(
        DEC_M,
        "[MultitaskDockManager.shared addRunningApp:windowName appUUID:dataUUID view:self.view];",
        "self.windowID = [MultitaskDockManager.shared lcPlusAllocateWindowID:dataUUID];\n"
        "    [MultitaskDockManager.shared addRunningApp:windowName appUUID:self.windowID view:self.view];",
    )
    ws.literal(
        DEC_M,
        "[dock removeRunningApp:self.dataUUID];",
        "NSString *lcPlusWindowID = self.windowID ?: self.dataUUID;\n"
        "        [dock removeRunningApp:lcPlusWindowID];\n"
        "        [dock lcPlusReleaseWindowID:lcPlusWindowID];",
    )
    ws.literal(DOCK_SWIFT, "findAppInfo(appName: appName, dataUUID: appUUID)",
               "findAppInfo(appName: appName, dataUUID: LCPlus.baseUUID(appUUID))")
    ws.literal(DOCK_SWIFT, "findAppInfo(appName: self.app.appName, dataUUID: self.app.appUUID)",
               "findAppInfo(appName: self.app.appName, dataUUID: LCPlus.baseUUID(self.app.appUUID))")

    # --- Run on a running app opens another instance instead of focusing the existing window
    banner_files = [
        "LiveContainerSwiftUI/Views/AppList/LCAppBanner/LCAppBannerViewController.swift",  # newer
        "LiveContainerSwiftUI/Views/AppList/LCAppBanner.swift",                           # older
    ]
    banner = next((f for f in banner_files if ws.exists(f)), None)
    if not banner:
        raise PatchError("banner source file not found")
    ws.regex(
        banner,
        r"MultitaskManager\.isUsing\(container: currentDataFolder\)\s*\{",
        "MultitaskManager.isUsing(container: currentDataFolder),\n"
        "           !LCPlus.canLaunchDuplicate(container: currentDataFolder) {",
    )

    def multitask_new():
        ws.literal(
            MODEL_SWIFT,
            "let multitask = classicMode == 0 ? (multitask ?? shouldLaunchInMultitaskMode) : false",
            'let multitask = classicMode == 0 ? (multitask ?? (shouldLaunchInMultitaskMode || LCPlus.canLaunchDuplicate(container: currentDataFolder ?? ""))) : false',
        )

    def multitask_old():
        ws.regex(
            MODEL_SWIFT,
            r"let multitask = multitask \?\? shouldLaunchInMultitaskMode;?",
            'let multitask = multitask ?? (shouldLaunchInMultitaskMode || LCPlus.canLaunchDuplicate(container: currentDataFolder ?? ""))',
        )

    first_of(ws, multitask_new, multitask_old)

    ws.regex(
        MODEL_SWIFT,
        r"(var found = false\n)(\s*if #available\(iOS 16\.1, \*\) \{\s*found = MultitaskWindowManager\.openExistingAppWindow\(dataUUID: dataUUID\))",
        lambda m: m.group(1)
        + "            if urlScheme == nil, LCPlus.canLaunchDuplicate(container: dataUUID) {\n"
        "                return false\n            }\n"
        + m.group(2),
    )
    ws.regex(
        MODEL_SWIFT,
        r"(,\s*)(var runningLC = LCSharedUtils\.getContainerUsingLCScheme\(withFolderName: fn\))",
        lambda m: m.group(1) + "!(multitask && LCPlus.canLaunchDuplicate(container: fn)),\n            " + m.group(2),
    )

    ws.add_file(NEW_DIR + "/LCPlusMultiInstance.swift", payload("LCPlusMultiInstance.swift"))


def g_snapping(ws):
    ensure_dec_helpers(ws)
    add_dec_properties(ws, [
        "@property(nonatomic) CGPoint lcRawOrigin;",
        "@property(nonatomic) CGSize lcRawSize;",
        "@property(nonatomic) BOOL lcPlusTracking;",
        "@property(nonatomic) NSString* lcPlusInsetsKey;",
        "@property(nonatomic) NSInteger lcPlusSnapState;",
    ])
    add_dec_methods(ws, payload("dec_snap.m"))
    ws.literal(
        DEC_M,
        "- (void)moveWindow:(UIPanGestureRecognizer*)sender {",
        "- (void)moveWindow:(UIPanGestureRecognizer*)sender {\n    if ([self lcPlusHandleMove:sender]) return;",
    )
    ws.literal(
        DEC_M,
        "- (void)resizeWindow:(UIPanGestureRecognizer*)sender {",
        "- (void)resizeWindow:(UIPanGestureRecognizer*)sender {\n    if ([self lcPlusHandleResize:sender]) return;",
    )
    # work area: the whole screen while the dock is collapsed, the safe area otherwise (restore/normalize code included)
    ws.regex_all(
        DEC_M,
        r"UIEdgeInsetsInsetRect\(self\.view\.window\.frame, (?:self\.view\.window\.safeAreaInsets|safeAreaInsets)\)",
        "LCPlusWorkArea(self.view.window)",
        min_count=3,
    )
    # stock resets the scene insets to zero on every settings update; use the real ones when a window reaches the screen edge
    ws.regex(
        DEC_M,
        r"(- \(void\)updateWindowedFrameWithSettings:\(UIMutableApplicationSceneSettings \*\)settings \{.*?)settings\.peripheryInsets = UIEdgeInsetsZero;\s*settings\.safeAreaInsetsPortrait = UIEdgeInsetsZero;",
        lambda m: m.group(1) + "[self lcPlusApplyWindowedInsets:settings];",
    )
    ws.regex(
        DEC_M,
        r"(// it seems some apps don't honor these settings so we don't cover the top of the app\s*)settings\.peripheryInsets = UIEdgeInsetsZero;\s*settings\.safeAreaInsetsPortrait = UIEdgeInsetsZero;",
        lambda m: m.group(1) + "[weakSelf lcPlusApplyWindowedInsets:settings];",
    )
    ws.literal(DEC_M, "NSArray *menuItems = @[\n", "NSArray *menuItems = @[\n        [self lcPlusSnapMenu],\n")
    ws.insert_after(DEC_H, "- (void)updateVerticalConstraints;", "\n+ (void)lcPlusTileAll;\n+ (void)lcPlusDockCollapseChanged;")


def g_scale(ws):
    ensure_dec_helpers(ws)
    add_dec_methods(ws, payload("dec_scale.m"))
    ws.literal(
        DEC_M,
        "- (void)appSceneVCWillActivateScene:(AppSceneViewController *)vc {",
        "- (void)appSceneVCWillActivateScene:(AppSceneViewController *)vc {\n    [self lcPlusApplyInitialScale];",
    )


def g_dock(ws):
    """Window bars follow the dock (hidden while collapsed, back when expanded) + Tile / Show all / Close all."""
    ensure_dec_helpers(ws)
    add_dec_methods(ws, payload("dec_grip.m"))
    ws.regex(
        DEC_M,
        r"BOOL hideWindowBar = MultitaskDockManager\.shared\.isCollapsed && self\.isMaximized;",
        'BOOL hideWindowBar = MultitaskDockManager.shared.isCollapsed && (self.isMaximized || LCPlusBool(@"LCPlusAutoHideBars", YES));',
    )
    # stretch / shrink the windows with that area when the dock collapses or expands
    ws.regex(
        DOCK_SWIFT,
        r"(@objc public func notifyDockCollapseChanged\(\) \{\s*self\.updateDockFrame\(\))",
        lambda m: m.group(1) + "\n        DecoratedAppSceneViewController.lcPlusDockCollapseChanged()",
    )
    # collapsing/expanding the dock must refresh every window, not only maximized ones
    ws.regex(
        DOCK_SWIFT,
        r"(if let vc = app\.view\?\._viewDelegate\(\) as\? DecoratedAppSceneViewController), vc\.isMaximized \{",
        lambda m: m.group(1) + " {",
    )
    ws.regex(
        DOCK_SWIFT,
        r"(MinimizeAllButtonView\(\)\s*\.onTapGesture \{\s*dockManager\.minimizeAllWindows\(\)\s*\})",
        lambda m: m.group(1) + "\n                        LCPlusDockButtons()",
    )
    # the dock frame is computed from the number of buttons: make room for three more
    ws.literal(DOCK_SWIFT, "max(self.apps.count + 1, 0)", "max(self.apps.count + 4, 0)")
    ws.regex(DOCK_SWIFT, r"buttonSize \* 2 \+ totalSpacingHeight", "buttonSize * 5 + totalSpacingHeight")
    ws.add_file(NEW_DIR + "/LCPlusDock.swift", payload("LCPlusDock.swift"))


def g_audio(ws):
    """Apps in different windows (even two instances of one app) can play audio/video at the same time."""
    ws.regex(
        SCENE_M,
        r"(NSMutableDictionary \*userInfo = @\{.*?\}\.mutableCopy;)",
        lambda m: m.group(1)
        + "\n    {\n        id lcPlusMix = [NSUserDefaults.lcSharedDefaults objectForKey:@\"LCPlusMixAudio\"];\n"
        "        userInfo[@\"mixAudio\"] = @(lcPlusMix ? [lcPlusMix boolValue] : YES);\n    }",
    )
    ws.insert_after(
        LPMAIN_M,
        '[lcUserDefaults setObject:appInfo[@"selectedContainer"] forKey:@"selectedContainer"];',
        '\n    if ([appInfo[@"mixAudio"] boolValue]) {\n'
        '        [lcUserDefaults setBool:YES forKey:@"LCPlusMixAudio"];\n'
        '    } else {\n'
        '        [lcUserDefaults removeObjectForKey:@"LCPlusMixAudio"];\n'
        '    }',
    )
    ws.insert_after(BOOT_M, "NSUserDefaults *lcUserDefaults;\n", payload("audio_boot.m"))
    ws.regex(
        BOOT_M,
        r"(\n[ \t]*)(NUDGuestHooksInit\(\);)",
        lambda m: m.group(1) + 'if (isLiveProcess && [lcUserDefaults boolForKey:@"LCPlusMixAudio"]) {'
        + m.group(1) + "    LCPlusMixAudioInstall();"
        + m.group(1) + "}" + m.group(1) + m.group(2),
    )


def g_appearance(ws):
    # --- home list: list/grid layout, background, theme
    pat = (r"LazyVStack \{\s*ForEach\(filteredApps, id: \\\.self\) \{ app in\s*(LCAppBanner\(appModel: app[^\n]*\))\s*\}"
           r"\s*\.transition\(\.scale\)\s*\}")
    text = ws.read(LIST_SWIFT)
    m = re.search(pat, text, re.S)
    if not m:
        raise PatchError("%s: main app list block not found" % LIST_SWIFT)
    banner_call = m.group(1)
    bind = re.search(r"appDataFolders: (\$\w+), tweakFolders: (\$\w+)", banner_call)
    if bind:
        settings_call = "LCAppSettingsView(model: app, appDataFolders: %s, tweakFolders: %s)" % bind.groups()
    else:
        settings_call = "LCAppSettingsView(model: app)"
    ws.regex(
        LIST_SWIFT,
        pat,
        "LCPlusAppsLayout(apps: filteredApps, openSettings: { app in\n"
        "                    openNavigationView(view: AnyView(%s))\n"
        "                }, banner: { app in\n"
        "                    %s\n"
        "                })" % (settings_call, banner_call),
    )
    ws.literal(
        LIST_SWIFT,
        '.coordinateSpace(name: "scroll")',
        '.coordinateSpace(name: "scroll")\n            .background(LCPlusBackground())\n            .modifier(LCPlusThemeModifier())',
    )

    # --- Liquid Glass banners: UIKit banner (newer) or SwiftUI banner (older releases)
    uikit = "LiveContainerSwiftUI/Views/AppList/LCAppBanner/LCAppBannerView.swift"
    swiftui = "LiveContainerSwiftUI/Views/AppList/LCAppBanner.swift"
    if ws.exists(uikit):
        ws.literal(uikit, "addSubview(visualBackgroundView)",
                   "addSubview(visualBackgroundView)\n        lcPlusInstallGlass(below: visualBackgroundView)")
        ws.regex(
            uikit,
            r'visualBackgroundView\.backgroundColor = dynamicColors\s*\?\s*mainColor\.withAlphaComponent\(0\.5\)\s*:\s*\(UIColor\(named: "AppBannerBG"\) \?\? \.secondarySystemBackground\)',
            lambda m: m.group(0) + "\n        lcPlusApplyGlass(on: visualBackgroundView, tint: dynamicColors ? mainColor : .systemGray)",
        )
        wrapper = "LiveContainerSwiftUI/Views/AppList/LCAppBanner/LCAppBanner.swift"
        if ws.exists(wrapper):  # makes the banners refresh when the glass settings change
            ws.regex(
                wrapper,
                r'(@AppStorage\("darkModeIcon", store: LCUtils\.appGroupUserDefault\) private var darkModeIcon = false)',
                lambda m: m.group(1)
                + '\n    @AppStorage("LCPlusGlassEnabled", store: LCUtils.appGroupUserDefault) private var lcPlusGlassEnabled = true'
                + '\n    @AppStorage("LCPlusGlassStrength", store: LCUtils.appGroupUserDefault) private var lcPlusGlassStrength = 0.15',
            )
    elif ws.exists(swiftui):
        ws.regex(
            swiftui,
            r'RoundedRectangle\(cornerSize: CGSize\(width:\s*22, height:\s*22\)\)\.fill\(dynamicColors \? mainColor\.opacity\(0\.5\) : Color\("AppBannerBG"\)\)',
            'LCPlusBannerBackground(fallback: dynamicColors ? mainColor.opacity(0.5) : Color("AppBannerBG"), tint: dynamicColors ? mainColor : .gray)',
        )
    else:
        raise PatchError("banner source file not found")

    # --- the background follows through Settings, Sources (repos), Tweaks and their sub-pages
    skipped = []

    def page_bg(rel, title, required):
        try:
            ws.regex(rel, r"(\n[ \t]*)(\.navigation(?:Bar)?Title\(" + title + ")",
                     lambda m: m.group(1) + ".lcPlusPageBackground()" + m.group(1) + m.group(2))
        except PatchError:
            if required:
                raise
            skipped.append(os.path.basename(rel))

    v = "LiveContainerSwiftUI/Views/"
    page_bg(v + "LCAltStoreSourcesView.swift", r'"lc\.tabView\.sources"\.loc\)', True)
    page_bg(v + "LCTweaksView.swift", r'isRoot \? "lc\.tabView\.tweaks"\.loc', True)
    page_bg(v + "Settings/LCSettingsView.swift", r'"lc\.tabView\.settings"\.loc\)', True)
    page_bg(MT_SETTINGS_SWIFT, r'"lc\.appBanner\.multitask"\.loc\)', False)
    page_bg(v + "Settings/LCMultiLCManagementView.swift", r'"lc\.settings\.multiLC"\.loc\)', False)
    page_bg(v + "Settings/LCJITLessDiagnoseView.swift", r'"lc\.settings\.jitlessDiagnose"\.loc\)', False)
    page_bg(v + "Settings/DataManagement/LCDataManagementView.swift", r'"lc\.settings\.dataManagement"\.loc\)', False)
    page_bg(v + "Settings/DataManagement/LCStorageManagementView.swift", r'"lc\.settings\.storageManagement"\.loc\)', False)
    page_bg(v + "AppList/AppSettings/LCAppSettingsView.swift", r"appInfo\.displayName\(\)\)", False)

    # --- Settings -> Appearance (LC Plus)
    ws.regex(
        SETTINGS_SWIFT,
        r'(NavigationLink \{\s*LCMultitaskSettingView\(\)\s*\} label: \{\s*Text\("lc\.appBanner\.multitask"\.loc\)\s*\})',
        lambda m: m.group(1)
        + "\n                    NavigationLink {\n                        LCPlusAppearanceSettingsView()\n"
        '                    } label: {\n                        Text("Appearance (LC Plus)")\n                    }',
    )
    ws.add_file(NEW_DIR + "/LCPlusAppearance.swift", payload("LCPlusAppearance.swift"))
    return ("background not applied on: " + ", ".join(skipped)) if skipped else ""


def g_branding(ws, app_name, bundle_id):
    """LiveContainer Plus: display name + a consistent bundle id for the app, its extensions and the SideStore variant."""
    from xml.sax.saxutils import escape

    # display name lives in the main target's Info.plist (path differs between releases)
    plist = None
    for cand in ("LiveContainer/Info.plist", "Resources/Info.plist"):
        if ws.has(cand, r"<key>CFBundleDisplayName</key>\s*<string>LiveContainer</string>"):
            plist = cand
            break
    if not plist:
        raise PatchError("main Info.plist with CFBundleDisplayName not found")
    ws.regex(plist, r"(<key>CFBundleDisplayName</key>\s*<string>)LiveContainer(</string>)",
             lambda m: m.group(1) + escape(app_name) + m.group(2))

    if bundle_id == STOCK_BUNDLE_ID:
        return
    # one switch: app, LiveProcess, ShareExtension and LaunchAppExtension ids all derive from it
    ws.literal("xcconfigs/Global.xcconfig",
               "LIVECONTAINER_BUNDLE_IDENTIFIER = %s$(DEVELOPMENT_TEAM_SUFFIX)" % STOCK_BUNDLE_ID,
               "LIVECONTAINER_BUNDLE_IDENTIFIER = %s$(DEVELOPMENT_TEAM_SUFFIX)" % bundle_id)
    # frameworks / libraries (SideStoreSupport, LiveContainerShared, LiveContainerSwiftUI) carry hard-coded ids too
    pbx = "LiveContainer.xcodeproj/project.pbxproj"
    text = ws.read(pbx)
    text, n_libs = re.subn(
        r'(PRODUCT_BUNDLE_IDENTIFIER = "?)%s\.(\w+)' % re.escape(STOCK_BUNDLE_ID),
        lambda m: m.group(1) + bundle_id + "." + m.group(2), text)
    text, n_swiftui = re.subn(
        r'(PRODUCT_BUNDLE_IDENTIFIER = "?)com\.kdtLiveContainerSwiftUI',
        lambda m: m.group(1) + bundle_id + ".LiveContainerSwiftUI", text)
    ws.files[pbx] = text
    # places that spell out the app's own id (keychain group names like ...livecontainer.shared stay as they are)
    hooks = "SideStoreSupport/SideStoreHooks.m"
    if ws.exists(hooks):
        ws.replace_all(hooks, '@"%s";' % STOCK_BUNDLE_ID, '@"%s";' % bundle_id, min_count=1)
    utils = "LiveContainerSwiftUI/Utilities/LCUtils.m"
    if ws.exists(utils):
        if "Apps/%s/App.app" % STOCK_BUNDLE_ID in ws.read(utils):
            ws.replace_all(utils, "Apps/%s/App.app" % STOCK_BUNDLE_ID, "Apps/%s/App.app" % bundle_id)
        if '@"%s.%%@.LiveProcess"' % STOCK_BUNDLE_ID in ws.read(utils):
            ws.replace_all(utils, '@"%s.%%@.LiveProcess"' % STOCK_BUNDLE_ID, '@"%s.%%@.LiveProcess"' % bundle_id)
    for rel in (".github/build_github.sh", ".github/sidelc/LiveWidgetExtension_adhoc.xml"):
        if ws.exists(rel) and STOCK_BUNDLE_ID in ws.read(rel):
            ws.replace_all(rel, STOCK_BUNDLE_ID, bundle_id)


GROUPS = {
    "multi_instance": g_multi_instance,
    "snapping": g_snapping,
    "scale": g_scale,
    "dock": g_dock,
    "audio": g_audio,
    "appearance": g_appearance,
}

LABELS = {
    "branding": "Branding (name + bundle id)",
    "multi_instance": "Multiple instances of the same app (up to 16, shared data)",
    "snapping": "Window snapping (edges, middle, other windows, grids, presets, tile all)",
    "scale": "Default multitask window scale (settings slider)",
    "dock": "Dock: whole-screen windows when collapsed, bars follow expand/collapse, Tile / Show all / Close all",
    "audio": "Audio/video can play in several windows at once (no interruptions between instances)",
    "appearance": "Custom background (all tabs), Liquid Glass banners, grid home screen",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lc", required=True, help="LiveContainer checkout")
    ap.add_argument("--features", default=",".join(ALL_FEATURES))
    ap.add_argument("--strict", action="store_true", help="fail if any selected feature can't be applied")
    ap.add_argument("--report", default=None)
    ap.add_argument("--app-name", default=DEFAULT_NAME)
    ap.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    args = ap.parse_args()

    if not re.match(r"^[A-Za-z0-9 +._-]{1,30}$", args.app_name):
        sys.exit("invalid --app-name (letters, digits, space, + . _ - ; max 30)")
    if not re.match(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$", args.bundle_id):
        sys.exit("invalid --bundle-id (reverse-DNS style, e.g. com.kdt.livecontainer.plus)")

    wanted = [f.strip() for f in args.features.split(",") if f.strip()]
    for f in wanted:
        if f not in GROUPS:
            sys.exit("unknown feature: %s" % f)
    for f in list(wanted):
        for dep in DEPENDS.get(f, []):
            if dep not in wanted:
                print("note: %s needs %s, enabling it" % (f, dep))
                wanted.append(dep)

    ws = Workspace(args.lc)
    results = []   # (feature, ok, detail)

    # core (always)
    try:
        g_core(ws)
    except PatchError as e:
        sys.exit("core failed: %s" % e)

    # branding first (so a failure there can't leave other groups half-renamed)
    if args.app_name != STOCK_NAME or args.bundle_id != STOCK_BUNDLE_ID:
        snap = ws.snapshot()
        try:
            g_branding(ws, args.app_name, args.bundle_id)
            results.append(("branding", True, ""))
        except PatchError as e:
            ws.restore(snap)
            results.append(("branding", False, str(e)))

    ordered = [f for f in ALL_FEATURES if f in wanted]
    for feat in ordered:
        snap = ws.snapshot()
        try:
            note = GROUPS[feat](ws) or ""
            results.append((feat, True, note))
        except PatchError as e:
            ws.restore(snap)
            results.append((feat, False, str(e)))
    # the settings screen needs at least one feature; a missing anchor only costs the extra section
    if any(ok for feat, ok, detail in results if feat in ("multi_instance", "snapping", "scale", "audio")):
        snap = ws.snapshot()
        try:
            g_settings_ui(ws)
            results.append(("settings", True, ""))
        except PatchError as e:
            ws.restore(snap)
            results.append(("settings", False, str(e)))

    ws.flush()

    lines = ["| Feature | Result |", "|---|---|"]
    failed = False
    for feat, ok, detail in results:
        label = LABELS.get(feat, "Multitask settings section (LC Plus)")
        if ok:
            lines.append("| %s | applied%s |" % (label, (" (" + detail + ")") if detail else ""))
        else:
            failed = True
            lines.append("| %s | **skipped** — %s |" % (label, detail.replace("|", "/")[:300]))
    report = "\n".join(lines)
    print(report)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.write(report + "\n")
    if failed and args.strict:
        sys.exit(1)


if __name__ == "__main__":
    main()
