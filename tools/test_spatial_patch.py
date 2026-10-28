#!/usr/bin/env python3
"""No-internet anchored patch smoke test for the Spatial Display group."""
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'patcher'))
from apply import Workspace, g_spatial

with TemporaryDirectory() as td:
    root = Path(td)
    dec = root / 'MultitaskSupport/DecoratedAppSceneViewController.m'
    settings = root / 'LiveContainerSwiftUI/Views/Settings/LCSettingsView.swift'
    plist = root / 'LiveContainer/Info.plist'
    for p in (dec, settings, plist):
        p.parent.mkdir(parents=True, exist_ok=True)
    dec.write_text('''#import "utils.h"
@interface DecoratedAppSceneViewController()
@end
@implementation DecoratedAppSceneViewController
[MultitaskDockManager.shared.windowHostingView addSubview:self.view];
@end
''')
    settings.write_text('''NavigationLink {
    LCMultitaskSettingView()
} label: {
    Text("lc.appBanner.multitask".loc)
}
''')
    plist.write_text('<?xml version="1.0"?><plist><dict></dict></plist>')
    ws = Workspace(td)
    g_spatial(ws)
    ws.flush()
    assert 'LCPlusSpatialRig shared' in dec.read_text()
    assert 'CoreMotion' in dec.read_text()
    assert 'LCPlusSpatialSettingsView()' in settings.read_text()
    assert 'Text("Spatial Display")' in settings.read_text()
    assert 'Label("Spatial Display",' not in settings.read_text()
    assert 'NSLocalNetworkUsageDescription' in plist.read_text()
    spatial_swift = (root / 'LiveContainerSwiftUI/LCPlus/LCPlusSpatialSettings.swift').read_text()
    spatial_objc = dec.read_text()
    assert 'Reset View (Look Straight Ahead)' in spatial_swift
    assert 'publisher(for: .GCControllerDidConnect)' in spatial_swift
    assert 'publisher(for: .GCControllerDidDisconnect)' in spatial_swift
    assert 'publisher(for: GCControllerDidConnect)' not in spatial_swift
    assert 'publisher(for: GCControllerDidDisconnect)' not in spatial_swift
    assert spatial_swift.index('Picker("Motion source"') < spatial_swift.index('Reset View (Look Straight Ahead)')
    assert spatial_swift.count('recenterNonce = recenterNonce == Int.max') == 1
    assert 'LCPlusSpatialMultiplyQuaternion(current, conjugate)' in spatial_objc
    assert 'self.hasControllerReference = NO;' in spatial_objc
    assert 'LCPlusSpatialViewerPresented' in spatial_objc
    assert 'Enter Spatial Mode' in spatial_swift
    assert '.fullScreenCover(isPresented: $showViewer' in spatial_swift
    assert 'LCPlusSpatialViewer(dismiss:' in spatial_swift
    assert 'if #available(iOS 16.0, *)' in spatial_swift
    viewer = (root / 'LiveContainerSwiftUI/LCPlus/LCPlusSpatialViewer.swift').read_text()
    assert '@available(iOS 16.0, *)\nstruct LCPlusSpatialViewer: View' in viewer
    assert 'private func captureWorkspace()' in viewer
    assert 'MultitaskDockManager.shared.windowHostingView' in viewer
    assert 'controllerSample(' in viewer
    assert 'hud(compact: true)' in viewer
    print('Spatial patch smoke test PASS')
