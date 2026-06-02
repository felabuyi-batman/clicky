//
//  LegacyWindowManager.swift
//  leanring-buddy
//
//  Presents the "Preserve a Voice" legacy experience in a standard resizable
//  window. The rest of the app lives in the menu bar, but the interview and
//  conversation need more room than the compact panel, so they get a real
//  window hosted via NSHostingView.
//

import AppKit
import SwiftUI

@MainActor
final class LegacyWindowManager: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let legacyManager: LegacyManager

    init(legacyManager: LegacyManager) {
        self.legacyManager = legacyManager
        super.init()
    }

    /// Shows the legacy window, creating it on first use and bringing it to the
    /// front on subsequent calls. The app is normally a menu-bar accessory, so
    /// we briefly activate it so the window can take focus and accept typing.
    func showWindow() {
        if let existingWindow = window {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: LegacyHomeView(legacyManager: legacyManager)
        )

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Preserve a Voice"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.setContentSize(NSSize(width: 520, height: 620))
        newWindow.center()
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Drop the reference so the window is rebuilt fresh next time it opens.
        window = nil
    }
}
