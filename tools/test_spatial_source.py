#!/usr/bin/env python3
"""Check known spatial-source regressions before an expensive Xcode archive.
This is NOT an iOS SDK typecheck; only xcodebuild can provide that.
"""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
s = (root / 'payload/swift/LCPlusSpatialSettings.swift').read_text()
e = (root / 'payload/swift/LCPlusSpatialExternal.swift').read_text()
t = (root / 'payload/swift/LCPlusSpatialTracker.swift').read_text()
y = (root / '.github/workflows/build.yml').read_text()
assert all(f'private var {section}: some View' in s for section in
           ('displaySection', 'gyroSection', 'calibrationSection', 'compatibilitySection'))
assert 'LCPlusSpatialCoordinator.shared.refresh()' in s
assert '.GCControllerDidConnect' in s and '.GCControllerDidDisconnect' in s
assert 'GCControllerDidConnect))' not in s.replace('.GCControllerDidConnect))', '')
assert 'UIScreen.didConnectNotification' in s
assert '@available(iOS 16.0, *)\n@MainActor\nfinal class LCPlusExternalSceneDelegate' in e
assert '@available(iOS 27.0, *)\n    private func updateSceneAccessory()' in e
assert 'UISceneAccessory.externalNonInteractive' in e
assert 'MultitaskDockManager' not in e
assert '.persistentSystemOverlays' not in e
assert '.foregroundStyle(.white)\n                        .foregroundStyle(.white)' not in e
assert 'rotation3DEffect(yawAngle' in e
assert 'motion.isDeviceMotionAvailable' in t
assert 'm.hasRotationRate' in t and 'm.hasGravityAndUserAcceleration' in t
assert 'xcodebuild archive' in y and 'print_build_diagnostics.py' in y
print('Spatial structural regression tests: PASS (not an iOS SDK compile)')
