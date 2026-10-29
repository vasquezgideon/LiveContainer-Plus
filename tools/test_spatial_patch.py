#!/usr/bin/env python3
"""Offline verification of external-only spatial patch anchors."""
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
import plistlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "patcher"))
from apply import Workspace, g_spatial

with TemporaryDirectory() as td:
    root = Path(td)
    dec = root / 'MultitaskSupport/DecoratedAppSceneViewController.m'
    settings = root / 'LiveContainerSwiftUI/Views/Settings/LCSettingsView.swift'
    app = root / 'LiveContainerSwiftUI/App/AppDelegate.swift'
    plist = root / 'LiveContainer/Info.plist'
    model = root / 'LiveContainerSwiftUI/Models/LCAppModel.swift'
    bootstrap = root / 'LiveContainer/LCBootstrap.m'
    for p in (dec, settings, app, plist, model, bootstrap):
        p.parent.mkdir(parents=True, exist_ok=True)
    model.write_text('        try await signApp(force: false)\n')
    bootstrap.write_text('static BOOL checkJITEnabled() {\n')
    dec.write_text('@interface DecoratedAppSceneViewController()\n@end\n')
    settings.write_text('''NavigationLink {
    LCMultitaskSettingView()
} label: {
    Text("lc.appBanner.multitask".loc)
}
''')
    app.write_text('''        application.shortcutItems = nil
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        self.window = (scene as? UIWindowScene)?.keyWindow
''')
    plist.write_text('''<?xml version="1.0"?><plist><dict><key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><true/></dict></dict></plist>''')
    ws = Workspace(td)
    g_spatial(ws)
    ws.flush()
    assert dec.read_text() == '@interface DecoratedAppSceneViewController()\n@end\n'
    assert 'LCPlusSpatialSettingsView()' in settings.read_text()
    assert 'Text("Spatial Display")' in settings.read_text()
    assert 'LCPlusSpatialCoordinator.shared.start()' in app.read_text()
    assert 'LCPlusSpatialCoordinator.shared.start()' in model.read_text()
    assert 'LCPlusSpatialGuestDidActivate' in bootstrap.read_text()
    assert 'LCPlusExternalSceneDelegate.self' in app.read_text()
    manifest = plistlib.loads(plist.read_bytes())['UIApplicationSceneManifest']
    assert 'UIWindowSceneSessionRoleExternalDisplayNonInteractive' in manifest['UISceneConfigurations']
    external = (root / 'LiveContainerSwiftUI/LCPlus/LCPlusSpatialExternal.swift').read_text()
    tracker = (root / 'LiveContainerSwiftUI/LCPlus/LCPlusSpatialTracker.swift').read_text()
    spatial = (root / 'LiveContainerSwiftUI/LCPlus/LCPlusSpatialSettings.swift').read_text()
    assert 'UISceneAccessory.externalNonInteractive' in external
    assert 'UIWindow(windowScene:' in external
    assert 'LCPlusViewerTracker' in tracker
    assert 'Reset View (Look Straight Ahead)' in spatial
    assert 'Screen framing' in spatial and 'Spatial zoom' in spatial
    assert 'm.hasGravityAndUserAcceleration' in spatial
    assert 'controllerGyroReadout' in spatial
    assert 'sourceCanvas(' in external and 'spatialCanvas(' in external
    assert 'RoundedRectangle(cornerRadius: 12)' not in external
    assert 'm.hasGravityAndUserAcceleration' in tracker
    assert '@available(iOS 16.0, *)\n@MainActor\nfinal class LCPlusExternalSceneDelegate' in external
    assert '0.018 * wrap(tiltDelta - accumulatedPitch)' in tracker
    assert 'fullScreenCover' not in spatial
    assert 'Enter Spatial Mode' not in spatial
    assert 'MultitaskDockManager' not in external
    assert 'LCPlusSpatialViewer.swift' not in ws.added
    print('Spatial external-only patch smoke test PASS')
