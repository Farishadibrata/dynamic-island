import AppKit
import SwiftUI

enum IslandLevel {
    static let panel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    static let dialog = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
}

/// Non-activating, borderless panel that never steals focus from the frontmost app.
///
/// The panel is deliberately larger than the visible island so the glow has room to
/// bloom. `ignoresMouseEvents` is toggled against the cursor position each poll, so the
/// transparent margin neither blocks clicks nor counts as hovering the island.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
