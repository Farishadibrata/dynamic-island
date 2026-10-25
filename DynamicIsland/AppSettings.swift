import Combine
import CoreGraphics
import Foundation
import SwiftUI

enum IslandSizePreset: String, CaseIterable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    var expandedWidth: CGFloat {
        switch self {
        case .compact: 330
        case .regular: 390
        case .large: 450
        }
    }


    /// Compact has no room for elapsed and total time beside the progress bar.
    var showsTrackTimes: Bool { self != .compact }
}

/// What a side slot of the collapsed pill shows.
enum IslandWingItem: String, CaseIterable, Identifiable {
    case none
    case nowPlaying
    case cpu
    case memory
    case disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .nowPlaying: "Now playing"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        }
    }

    /// Width this slot adds to the collapsed pill. Nothing shown, nothing added, so the
    /// pill falls back to the bare notch.
    var collapsedWidth: CGFloat {
        switch self {
        case .none: 0
        case .nowPlaying: 56
        default: 44
        }
    }
}

/// A reading shown in the system section of the expanded island.
enum SystemMetric: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        }
    }
}

/// A live status icon in the expanded island. Tapping one opens its System Settings pane.
enum StatusIcon: String, CaseIterable, Identifiable {
    case battery
    case wifi
    case bluetooth
    case sound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .sound: "Sound"
        }
    }

    var settingsURL: URL {
        let pane = switch self {
        case .battery: "com.apple.Battery-Settings.extension"
        case .wifi: "com.apple.wifi-settings-extension"
        case .bluetooth: "com.apple.BluetoothSettings"
        case .sound: "com.apple.Sound-Settings.extension"
        }
        return URL(string: "x-apple.systempreferences:\(pane)")!
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let sizePreset = "islandSizePreset"
        static let expandOnHover = "expandOnHover"
        static let showOnAllSpaces = "showOnAllSpaces"
        static let widgetLeft = "islandWidgetLeft"
        static let widgetRight = "islandWidgetRight"
        static let focusMinutes = "focusMinutes"
        static let systemMetrics = "systemMetrics"
        static let statusIcons = "statusIcons"
        static let glowFollowsMedia = "glowFollowsMedia"
        static let discordShortcut = "discordMuteShortcut"
        static let glowEffect = "glowEffect"
        static let glowIntensity = "glowIntensity"
        static let glowSpeed = "glowSpeed"
        static let innerGlowEnabled = "innerGlowEnabled"
        static let innerGlowIntensity = "innerGlowIntensity"
        static let glowStyle = "glowStyle"
        static let customGlowColors = "customGlowColors"
        static let leftWing = "islandLeftWing"
        static let rightWing = "islandRightWing"
    }

    /// Called whenever a setting that affects island geometry or window behavior changes.
    var onChange: (@MainActor () -> Void)?

    private let defaults: UserDefaults

    @Published var sizePreset: IslandSizePreset {
        didSet {
            defaults.set(sizePreset.rawValue, forKey: Key.sizePreset)
            onChange?()
        }
    }

    @Published var expandOnHover: Bool {
        didSet {
            defaults.set(expandOnHover, forKey: Key.expandOnHover)
            onChange?()
        }
    }

    @Published var showOnAllSpaces: Bool {
        didSet {
            defaults.set(showOnAllSpaces, forKey: Key.showOnAllSpaces)
            onChange?()
        }
    }

    /// Cards shown in the expanded island. They change its height, so they relayout.
    @Published var widgetLeft: IslandWidget {
        didSet {
            defaults.set(widgetLeft.rawValue, forKey: Key.widgetLeft)
            onChange?()
        }
    }

    @Published var widgetRight: IslandWidget {
        didSet {
            defaults.set(widgetRight.rawValue, forKey: Key.widgetRight)
            onChange?()
        }
    }

    /// Readings listed under the widgets. They change its height, so they relayout.
    @Published var systemMetrics: Set<SystemMetric> {
        didSet {
            defaults.set(systemMetrics.map(\.rawValue), forKey: Key.systemMetrics)
            onChange?()
        }
    }

    /// In display order, whatever order the set happens to iterate in.
    var activeSystemMetrics: [SystemMetric] {
        SystemMetric.allCases.filter(systemMetrics.contains)
    }

    /// Tints the glow with the colours of the cover while music plays.
    @Published var glowFollowsMedia: Bool {
        didSet { defaults.set(glowFollowsMedia, forKey: Key.glowFollowsMedia) }
    }

    /// Status icons shown in the expanded island. They change its height, so they relayout.
    @Published var statusIcons: Set<StatusIcon> {
        didSet {
            defaults.set(statusIcons.map(\.rawValue), forKey: Key.statusIcons)
            onChange?()
        }
    }

    var activeStatusIcons: [StatusIcon] {
        StatusIcon.allCases.filter(statusIcons.contains)
    }

    /// What to press for Discord's "Toggle Mute" keybind.
    @Published var discordShortcut: KeyShortcut? {
        didSet {
            if let discordShortcut, let data = try? JSONEncoder().encode(discordShortcut) {
                defaults.set(data, forKey: Key.discordShortcut)
            } else {
                defaults.removeObject(forKey: Key.discordShortcut)
            }
        }
    }

    /// Length of a focus-timer session.
    @Published var focusMinutes: Int {
        didSet { defaults.set(focusMinutes, forKey: Key.focusMinutes) }
    }

    /// Slots either side of the notch in the collapsed pill. These change the pill's width,
    /// so they relayout too.
    @Published var leftWing: IslandWingItem {
        didSet {
            defaults.set(leftWing.rawValue, forKey: Key.leftWing)
            onChange?()
        }
    }

    @Published var rightWing: IslandWingItem {
        didSet {
            defaults.set(rightWing.rawValue, forKey: Key.rightWing)
            onChange?()
        }
    }

    @Published var glowEffect: GlowEffect {
        didSet {
            defaults.set(glowEffect.rawValue, forKey: Key.glowEffect)
            // The glow needs room around the shape, so it changes the panel geometry.
            onChange?()
        }
    }

    @Published var glowIntensity: Double {
        didSet { defaults.set(glowIntensity, forKey: Key.glowIntensity) }
    }

    /// Halo hugging the physical notch, drawn inside the expanded island.
    @Published var innerGlowEnabled: Bool {
        didSet { defaults.set(innerGlowEnabled, forKey: Key.innerGlowEnabled) }
    }

    @Published var innerGlowIntensity: Double {
        didSet { defaults.set(innerGlowIntensity, forKey: Key.innerGlowIntensity) }
    }

    @Published var glowStyle: GlowStyle {
        didSet {
            defaults.set(glowStyle.rawValue, forKey: Key.glowStyle)
            // The song style needs the playhead, which the controller hands to the player.
            onChange?()
        }
    }

    /// Palette used when the effect is `.custom`.
    @Published var customGlowColors: [GlowColor] {
        didSet {
            guard let data = try? JSONEncoder().encode(customGlowColors) else { return }
            defaults.set(data, forKey: Key.customGlowColors)
        }
    }

    /// Stops for the glow, resolving the user palette for the custom effect.
    var glowColors: [Color] {
        glowEffect == .custom ? customGlowColors.map(\.color) : glowEffect.colors
    }

    @Published var glowSpeed: Double {
        didSet { defaults.set(glowSpeed, forKey: Key.glowSpeed) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sizePreset = defaults.string(forKey: Key.sizePreset)
            .flatMap(IslandSizePreset.init(rawValue:)) ?? .regular
        expandOnHover = defaults.object(forKey: Key.expandOnHover) as? Bool ?? true
        showOnAllSpaces = defaults.object(forKey: Key.showOnAllSpaces) as? Bool ?? true
        widgetLeft = defaults.string(forKey: Key.widgetLeft)
            .flatMap(IslandWidget.init(rawValue:)) ?? .calendar
        widgetRight = defaults.string(forKey: Key.widgetRight)
            .flatMap(IslandWidget.init(rawValue:)) ?? .timer
        systemMetrics = Set((defaults.stringArray(forKey: Key.systemMetrics)
            ?? SystemMetric.allCases.map(\.rawValue)).compactMap(SystemMetric.init(rawValue:)))
        glowFollowsMedia = defaults.object(forKey: Key.glowFollowsMedia) as? Bool ?? true
        statusIcons = Set((defaults.stringArray(forKey: Key.statusIcons)
            ?? StatusIcon.allCases.map(\.rawValue)).compactMap(StatusIcon.init(rawValue:)))
        discordShortcut = defaults.data(forKey: Key.discordShortcut)
            .flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) }
        focusMinutes = defaults.object(forKey: Key.focusMinutes) as? Int ?? 25
        leftWing = defaults.string(forKey: Key.leftWing)
            .flatMap(IslandWingItem.init(rawValue:)) ?? .nowPlaying
        rightWing = defaults.string(forKey: Key.rightWing)
            .flatMap(IslandWingItem.init(rawValue:)) ?? .cpu
        glowEffect = defaults.string(forKey: Key.glowEffect)
            .flatMap(GlowEffect.init(rawValue:)) ?? .aurora
        glowIntensity = defaults.object(forKey: Key.glowIntensity) as? Double ?? 0.9
        glowSpeed = defaults.object(forKey: Key.glowSpeed) as? Double ?? 1.0
        innerGlowEnabled = defaults.object(forKey: Key.innerGlowEnabled) as? Bool ?? true
        innerGlowIntensity = defaults.object(forKey: Key.innerGlowIntensity) as? Double ?? 0.8
        glowStyle = defaults.string(forKey: Key.glowStyle)
            .flatMap(GlowStyle.init(rawValue:)) ?? .angular

        let storedColors = defaults.data(forKey: Key.customGlowColors)
            .flatMap { try? JSONDecoder().decode([GlowColor].self, from: $0) }
        customGlowColors = storedColors.flatMap { $0.count >= 2 ? $0 : nil } ?? Self.defaultCustomColors
    }

    static let defaultCustomColors: [GlowColor] = [
        GlowColor(red: 0.36, green: 0.95, blue: 0.85),
        GlowColor(red: 0.42, green: 0.58, blue: 1.00),
        GlowColor(red: 0.78, green: 0.45, blue: 1.00),
    ]
}
