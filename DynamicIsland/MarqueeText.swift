import SwiftUI

/// Single-line text that runs sideways when it is wider than its container.
///
/// The offset is sampled from the wall clock rather than driven by `withAnimation`, the
/// same way the glow is, so a redrawn frame never restarts or jitters the scroll. The
/// caller gives the view a new `id` when the song changes, which starts the run again
/// from the left edge.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12, weight: .semibold)
    var color: Color = .white
    /// Points travelled per second.
    var speed: Double = 28
    /// Space between the end of the text and its repeat, so the loop reads as two copies.
    var gap: CGFloat = 26
    /// How long the title sits still before it starts running.
    var hold: TimeInterval = 1.2
    /// Collapsed, the label is invisible — no point burning frames on it.
    var isActive: Bool = true

    @State private var textWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        GeometryReader { proxy in
            let overflow = textWidth > proxy.size.width + 1
            let travel = textWidth + gap

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || !overflow)) { context in
                HStack(spacing: gap) {
                    label
                    if overflow { label }
                }
                .fixedSize()
                .offset(x: overflow
                        ? Self.offset(at: context.date, start: start, travel: travel,
                                      speed: speed, hold: hold)
                        : 0)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
            .clipped()
        }
        .background(alignment: .leading) { measurement }
        .onPreferenceChange(TextWidthKey.self) { width in
            guard abs(width - textWidth) > 0.5 else { return }
            textWidth = width
            start = Date()
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    /// Laid out behind the visible copy and hidden, purely to learn the text width.
    private var measurement: some View {
        label
            .hidden()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: TextWidthKey.self, value: proxy.size.width)
                }
            }
    }

    /// Offset at `date`, looping seamlessly: the second copy sits exactly `travel` to the
    /// right of the first, so jumping back to zero when the run completes is invisible.
    private static func offset(at date: Date,
                               start: Date,
                               travel: CGFloat,
                               speed: Double,
                               hold: TimeInterval) -> CGFloat {
        let elapsed = date.timeIntervalSince(start) - hold
        guard elapsed > 0, travel > 1, speed > 0 else { return 0 }
        let period = Double(travel) / speed
        return -CGFloat(elapsed.truncatingRemainder(dividingBy: period) * speed)
    }
}

private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
