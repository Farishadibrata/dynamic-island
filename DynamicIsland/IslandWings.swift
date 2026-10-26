import SwiftUI

/// One side slot of the collapsed pill.
struct IslandWing: View {
    let item: IslandWingItem
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var stats: SystemStats
    @ObservedObject var battery: BatteryMonitor
    /// False while the island is open and the slot is hidden, so the bars stop costing frames.
    let isActive: Bool

    var body: some View {
        Group {
            switch item {
            case .none:
                Color.clear
            case .nowPlaying:
                nowPlayingWing
            case .cpu:
                reading(symbol: "cpu", text: percent(stats.cpu))
            case .memory:
                reading(symbol: "memorychip", text: gigabytes(stats.memoryUsed))
            case .disk:
                reading(symbol: "internaldrive", text: percent(stats.diskUsed))
            case .battery:
                batteryReading
            }
        }
        .frame(height: 20)
    }

    private var nowPlayingWing: some View {
        HStack(spacing: 9) {
            artwork
            if let track = nowPlaying.track {
                SourceIcon(track: track, side: 16)
            }
        }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.white.opacity(0.12))
            .frame(width: 20, height: 20)
            .overlay {
                if let image = nowPlaying.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    /// Charge with a symbol that follows it; green while charging, red when nearly empty.
    private var batteryReading: some View {
        let level = battery.level
        let tint: Color = battery.isCharging ? .green : ((level ?? 100) <= 10 ? .red : .white.opacity(0.8))
        return HStack(spacing: 3) {
            Image(systemName: level.map { BatteryGlyph.symbol(level: $0, charging: battery.isCharging) }
                  ?? "powerplug")
                .font(.system(size: 10, weight: .medium))
            Text(level.map { "\($0)%" } ?? "AC")
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .lineLimit(1)
    }

    private func reading(symbol: String, text: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .medium))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.8))
        .lineLimit(1)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1fG", bytes / 1_073_741_824)
    }
}

/// The icon of the app the music is coming from, beside the cover. It dims while paused.
struct SourceIcon: View {
    let track: NowPlayingTrack
    var side: CGFloat = 16

    var body: some View {
        if let image = Self.icon(for: track.sourceID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .opacity(track.isPlaying ? 1 : 0.45)
                .animation(.easeOut(duration: 0.2), value: track.isPlaying)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: side * 0.7, weight: .semibold))
                .foregroundStyle(.white.opacity(track.isPlaying ? 0.8 : 0.4))
        }
    }

    private static var cache: [String: NSImage] = [:]

    private static func icon(for sourceID: String) -> NSImage? {
        if let cached = cache[sourceID] { return cached }
        guard let source = NowPlayingSource(rawValue: sourceID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[sourceID] = image
        return image
    }
}
