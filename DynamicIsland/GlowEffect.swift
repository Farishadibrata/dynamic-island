import SwiftUI

/// How the palette is laid across the glow.
enum GlowStyle: String, CaseIterable, Identifiable {
    case angular
    case linear
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .angular: "Angular"
        case .linear: "Linear"
        case .progress: "Song"
        }
    }
}

enum GlowEffect: String, CaseIterable, Identifiable {
    case off
    case aurora
    case sunset
    case midnight
    case rainbow
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .midnight: "Midnight"
        case .rainbow: "Rainbow"
        case .custom: "Custom"
        }
    }

    /// Built-in palettes. `custom` is supplied by the user, and `off` draws nothing.
    var colors: [Color] {
        switch self {
        case .off:
            [.clear, .clear]
        case .aurora:
            [Color(red: 0.30, green: 0.95, blue: 0.85),
             Color(red: 0.35, green: 0.55, blue: 1.00),
             Color(red: 0.70, green: 0.40, blue: 1.00),
             Color(red: 0.30, green: 0.95, blue: 0.85)]
        case .sunset:
            [Color(red: 1.00, green: 0.55, blue: 0.20),
             Color(red: 1.00, green: 0.30, blue: 0.45),
             Color(red: 0.75, green: 0.20, blue: 0.65),
             Color(red: 1.00, green: 0.55, blue: 0.20)]
        case .midnight:
            [Color(red: 0.25, green: 0.55, blue: 1.00),
             Color(red: 0.40, green: 0.35, blue: 0.95),
             Color(red: 0.25, green: 0.85, blue: 0.80),
             Color(red: 0.25, green: 0.55, blue: 1.00)]
        case .rainbow:
            [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]
        case .custom:
            []
        }
    }

    var animates: Bool { self != .off }

    /// Seconds for the comet to make one lap of the island.
    var rotationPeriod: Double {
        switch self {
        case .aurora: 5
        case .sunset: 6.5
        case .rainbow: 4
        case .midnight: 7
        case .custom: 5
        case .off: 0
        }
    }
}
