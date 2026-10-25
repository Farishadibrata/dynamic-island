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
            VisualizerBars(isPlaying: nowPlaying.track?.isPlaying ?? false, isActive: isActive)
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

/// Level bars beside the collapsed artwork.
///
/// macOS hands third-party apps no audio levels — `MediaRemote` is closed off, and capturing
/// the output device needs a kernel extension — so these are shaped by the clock instead of
/// by the sound. They move while something is playing and rest when it is paused.
struct VisualizerBars: View {
    let isPlaying: Bool
    let isActive: Bool
    var barCount = 4
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2
    var maxHeight: CGFloat = 14
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying || !isActive)) { context in
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: barWidth, height: height(at: context.date, index: index))
                }
            }
        }
    }

    private func height(at date: Date, index: Int) -> CGFloat {
        let rest = barWidth + 1
        guard isPlaying else { return rest }

        // Two out-of-step waves per bar keep the group from marching in unison.
        let time = date.timeIntervalSinceReferenceDate
        let phase = Double(index) * 1.9
        let wave = (sin(time * 6.1 + phase) + sin(time * 2.3 + phase * 1.4) + 2) / 4
        return rest + (maxHeight - rest) * CGFloat(wave)
    }
}
