import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: controller)
        window.title = "Dynamic Island Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Float above the island so the dialog can never be buried by it.
        window.level = IslandLevel.dialog

        window.setContentSize(SettingsView.size)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                          y: visible.midY - size.height / 2))
        }
        return window
    }
}
