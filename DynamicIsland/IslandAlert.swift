import SwiftUI

/// The kinds of event the island can announce, each switchable in Settings.
enum AlertKind: String, CaseIterable, Identifiable {
    case battery
    case volume
    case brightness
    case bluetooth
    case timer

    var id: String { rawValue }

    /// Volume and brightness fire constantly and often as a side effect of something else,
    /// such as macOS brightening the screen when the charger goes in. They never replace an
    /// alert that is already showing.
    var isMinor: Bool { self == .volume || self == .brightness }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .bluetooth: "Bluetooth"
        case .timer: "Timer"
        }
    }
}

/// A short message the island opens to show, then folds away from.
struct IslandAlert: Equatable {
    var id = UUID()
    let kind: AlertKind
    let symbol: String
    let title: String
    var subtitle: String?
    /// 0...1, drawn as a bar; the volume alert uses it.
    var level: Double?
    var tint: Color = .white
    /// Seconds on screen. A later alert of the same kind restarts it.
    var duration: TimeInterval = 3
}

/// An alert laid out in the notch's own band: the icon to the left of the notch and the
/// message to the right, so the island only widens and never grows taller.
struct IslandAlertView: View {
    let alert: IslandAlert
    let notchWidth: CGFloat
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().fill(alert.tint.opacity(0.22))
                Image(systemName: alert.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(alert.tint)
            }
            .frame(width: 22, height: 22)
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            // Centred in the whole stretch between the island's edge and the notch.
            .frame(width: IslandMetrics.alertWingWidth + IslandMetrics.alertNotchGap, alignment: .center)

            Color.clear.frame(width: notchWidth)

            message
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : -6)
                .frame(width: IslandMetrics.alertWingWidth, alignment: .leading)
                .padding(.leading, IslandMetrics.alertNotchGap)
        }
        .onAppear(perform: pop)
        // A new alert while one is showing replays the pop; the volume one updates in place.
        .onChange(of: alert.kind) { _, _ in pop() }
        .animation(.spring(response: 0.4, dampingFraction: 0.66), value: appeared)
        .animation(.easeOut(duration: 0.12), value: alert.level)
    }

    /// The message is kept short: a title, and under it a line of detail, with a small level
    /// bar in front when there is a level. Anything longer is cut off rather than widening
    /// the island.
    private var message: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(alert.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let level = alert.level {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: 28, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(alert.tint)
                                .frame(width: 28 * min(max(level, 0), 1))
                        }
                }
                if let subtitle = alert.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }

    private func pop() {
        appeared = false
        DispatchQueue.main.async { appeared = true }
    }
}
