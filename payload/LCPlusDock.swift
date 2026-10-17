//
//  LCPlusDock.swift — added by LC Plus (dock group; needs the snapping group for Tile)
//  Extra dock buttons: tile all, show all, close all.
//
import SwiftUI
import UIKit

@available(iOS 16.0, *)
extension MultitaskDockManager {
    @objc(lcPlusShowAll)
    func lcPlusShowAllWindows() {
        DispatchQueue.main.async {
            for app in self.apps {
                _ = self.bringMultitaskViewToFront(uuid: app.appUUID)
            }
        }
    }

    @objc(lcPlusCloseAll)
    func lcPlusCloseAllWindows() {
        DispatchQueue.main.async {
            let current = self.apps
            for app in current {
                if let vc = app.view?._viewDelegate() as? DecoratedAppSceneViewController {
                    _ = vc.perform(NSSelectorFromString("closeWindow"))
                }
            }
        }
    }
}

@available(iOS 16.0, *)
struct LCPlusDockButton: View {
    @EnvironmentObject var dockManager: MultitaskDockManager
    let symbol: String
    let action: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.8))
                .frame(width: dockManager.adaptiveIconSize, height: dockManager.adaptiveIconSize)
            Image(systemName: symbol)
                .foregroundColor(.white)
                .font(.system(size: dockManager.adaptiveIconSize * 0.4, weight: .semibold))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

@available(iOS 16.0, *)
struct LCPlusDockButtons: View {
    @EnvironmentObject var dockManager: MultitaskDockManager

    var body: some View {
        VStack(spacing: 8) {
            LCPlusDockButton(symbol: "square.grid.2x2") {
                DecoratedAppSceneViewController.lcPlusTileAll()
            }
            LCPlusDockButton(symbol: "rectangle.stack.badge.plus") {
                dockManager.lcPlusShowAllWindows()
            }
            LCPlusDockButton(symbol: "xmark.circle") {
                dockManager.lcPlusCloseAllWindows()
            }
        }
    }
}
