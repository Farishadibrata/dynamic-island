import AppKit

@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    private var actionBoxes: [ActionBox] = []

    func install(onOpenSettings: @escaping @MainActor () -> Void) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")
            ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Dynamic Island")

        let menu = NSMenu()
        menu.addItem(actionItem(title: "Settings…", key: ",", handler: onOpenSettings))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit Dynamic Island", key: "q") { NSApp.terminate(nil) })
        item.menu = menu

        statusItem = item
    }

    private func actionItem(title: String,
                            key: String = "",
                            handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let box = ActionBox(handler: handler)
        actionBoxes.append(box)

        let item = NSMenuItem(title: title, action: #selector(ActionBox.fire), keyEquivalent: key)
        item.target = box
        return item
    }
}

/// NSMenuItem needs an ObjC target, so each item gets a box that owns its closure.
final class ActionBox: NSObject {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func fire() {
        MainActor.assumeIsolated { handler() }
    }
}
