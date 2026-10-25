import AppKit

/// Assigns windows to individual desktops of one display.
///
/// `.canJoinAllSpaces`, or membership in every space, makes the window server composite a
/// window once, pinned to the screen, while a three-finger swipe slides the desktops
/// underneath it. A window that belongs to a single desktop travels with it, so the island
/// keeps one panel per desktop.
///
/// This leans on the private CoreGraphics space calls; if they ever go missing the
/// result is an empty list and the window simply stays on the space it was opened on.
@MainActor
enum SpaceMembership {
    private typealias ConnectionID = Int32

    @_silgen_name("CGSMainConnectionID")
    private static func CGSMainConnectionID() -> ConnectionID

    @_silgen_name("CGSCopyManagedDisplaySpaces")
    private static func CGSCopyManagedDisplaySpaces(_ cid: ConnectionID) -> Unmanaged<CFArray>?

    @_silgen_name("CGSAddWindowsToSpaces")
    private static func CGSAddWindowsToSpaces(_ cid: ConnectionID, _ windows: CFArray, _ spaces: CFArray)

    @_silgen_name("CGSRemoveWindowsFromSpaces")
    private static func CGSRemoveWindowsFromSpaces(_ cid: ConnectionID, _ windows: CFArray, _ spaces: CFArray)

    /// Leaves `window` on exactly one desktop, out of `allSpaces`.
    static func pin(_ window: NSWindow, toSpace space: Int, among allSpaces: [Int]) {
        guard window.windowNumber > 0 else { return }
        let cid = CGSMainConnectionID()
        let windows = [window.windowNumber] as CFArray
        CGSAddWindowsToSpaces(cid, windows, [space] as CFArray)
        CGSRemoveWindowsFromSpaces(cid, windows, allSpaces.filter { $0 != space } as CFArray)
    }

    @_silgen_name("CGSGetActiveSpace")
    private static func CGSGetActiveSpace(_ cid: ConnectionID) -> Int

    @_silgen_name("CGSManagedDisplaySetCurrentSpace")
    private static func CGSManagedDisplaySetCurrentSpace(_ cid: ConnectionID, _ display: CFString, _ space: Int)

    /// A panel only starts being drawn on a desktop once that desktop has been shown, so
    /// the first swipe into a desktop would have no island sliding in with it. Flipping
    /// through the others, instantly and without the swipe animation, gets it drawn up front.
    static func warmUp(_ spaces: [Int], on screen: NSScreen?, visit: (Int) -> Void) async {
        let cid = CGSMainConnectionID()
        guard let display = displayIdentifier(for: screen) as CFString? else { return }
        let current = CGSGetActiveSpace(cid)
        for space in spaces where space != current {
            CGSManagedDisplaySetCurrentSpace(cid, display, space)
            try? await Task.sleep(for: .milliseconds(120))
            visit(space)
            try? await Task.sleep(for: .milliseconds(120))
        }
        CGSManagedDisplaySetCurrentSpace(cid, display, current)
    }

    /// Regular desktops on the display showing `screen`, in Mission Control order.
    static func userSpaceIDs(on screen: NSScreen?) -> [Int] {
        guard let match = managedDisplay(for: screen),
              let spaces = match["Spaces"] as? [[String: Any]] else { return [] }

        // Type 0 is a regular desktop; full-screen apps and the like are other types.
        return spaces.compactMap { space in
            guard (space["type"] as? Int) == 0 else { return nil }
            return space["id64"] as? Int
        }
    }

    private static func managedDisplay(for screen: NSScreen?) -> [String: Any]? {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        let uuid = screen.flatMap(displayUUID)
        return displays.first { ($0["Display Identifier"] as? String) == uuid }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? displays.first
    }

    private static func displayIdentifier(for screen: NSScreen?) -> String? {
        managedDisplay(for: screen)?["Display Identifier"] as? String
    }

    private static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
