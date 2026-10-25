import AppKit

enum NotchLocator {
    /// The screen the pointer is on, falling back to the main display.
    static func activeScreen() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    /// The physical notch in screen coordinates (bottom-left origin), or a
    /// notch-sized stand-in at the top centre when the display has no notch.
    static func notchRect(on screen: NSScreen) -> CGRect {
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            return CGRect(x: left.maxX,
                          y: screen.frame.maxY - left.height,
                          width: right.minX - left.maxX,
                          height: left.height)
        }

        let width: CGFloat = 190
        let height: CGFloat = 30
        return CGRect(x: screen.frame.midX - width / 2,
                      y: screen.frame.maxY - height,
                      width: width,
                      height: height)
    }
}
