import AppKit
import SwiftUI

/// A row that records the next key combination typed while it is listening.
struct ShortcutRecorderRow: View {
    @Binding var shortcut: KeyShortcut?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            if shortcut != nil {
                Button("Clear") { shortcut = nil }
                    .controlSize(.small)
            }

            Button(isRecording ? "Press keys…" : (shortcut?.label ?? "Record shortcut")) {
                isRecording ? stop() : start()
            }
            .controlSize(.small)
            .help("The key combination bound to Toggle Mute in Discord's keybind settings")
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels rather than being recorded.
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            shortcut = KeyShortcut(keyCode: event.keyCode,
                                   flags: UInt64(cgFlags(modifiers).rawValue),
                                   label: label(for: event, modifiers: modifiers))
            stop()
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func cgFlags(_ modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    private func label(for event: NSEvent, modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return text + (key.trimmingCharacters(in: .whitespaces).isEmpty ? "Key \(event.keyCode)" : key)
    }
}
