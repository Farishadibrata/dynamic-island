import AppKit
import SwiftUI

/// `Color` isn't persistable, so custom glow colours round-trip through sRGB components.
struct GlowColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(srgb.redComponent)
        green = Double(srgb.greenComponent)
        blue = Double(srgb.blueComponent)
        alpha = Double(srgb.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
