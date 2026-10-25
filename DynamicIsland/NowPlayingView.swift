import SwiftUI

/// Artwork, running title and progress for the track that is playing.
///
/// A new song arrives with a short reveal: the cover springs in with a ring rippling out
/// from it, the title and artist rise in one after the other, and level bars run beside
/// them. `track.id` restarts the whole sequence when the song changes while open.
struct NowPlayingView: View {
    let track: NowPlayingTrack
    let artwork: NSImage?
    let accent: Color?
    let showsTimes: Bool
    let isActive: Bool

    @State private var revealed = false
    @State private var rippling = false

    private var tint: Color { accent ?? .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                artworkView

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(text: track.title, isActive: isActive)
                        .id(track.id)
                        .frame(height: 15)
                        .reveal(revealed, delay: 0.10)

                    Text(track.artist.isEmpty ? track.album : track.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .reveal(revealed, delay: 0.18)
                }

                Spacer(minLength: 0)

                VisualizerBars(isPlaying: track.isPlaying,
                               isActive: isActive,
                               barCount: 5,
                               barWidth: 3,
                               spacing: 2.5,
                               maxHeight: 22,
                               color: tint)
                    .frame(height: 24)
                    .reveal(revealed, delay: 0.26)
            }

            progressBar
                .reveal(revealed, delay: 0.22)
        }
        .frame(height: IslandMetrics.mediaBlockHeight(showsTimes: showsTimes), alignment: .top)
        .onAppear(perform: play)
        .onChange(of: track.id) { _, _ in play() }
    }

    /// Resets to the hidden state without animation, then lets the reveal run.
    private func play() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            revealed = false
            rippling = false
        }
        DispatchQueue.main.async {
            revealed = true
            withAnimation(.easeOut(duration: 0.9)) { rippling = true }
        }
    }

    private var artworkView: some View {
        let side = IslandMetrics.artworkSide
        return ZStack {
            // Ripple leaving the cover once, in the cover's own colour.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.7), lineWidth: 1.5)
                .frame(width: side, height: side)
                .scaleEffect(rippling ? 1.7 : 1)
                .opacity(rippling ? 0 : (revealed ? 0.8 : 0))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.1))
                .frame(width: side, height: side)
                .overlay {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: tint.opacity(revealed ? 0.45 : 0), radius: 8)
                .scaleEffect(revealed ? 1 : 0.55)
                .rotationEffect(.degrees(revealed ? 0 : -9))
                .opacity(revealed ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.58), value: revealed)
        }
        .frame(width: side, height: side)
    }

    /// The bar alone in Compact; with elapsed and total time either side of it otherwise.
    private var progressBar: some View {
        HStack(spacing: 6) {
            if showsTimes {
                timeLabel(track.position, alignment: .leading)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: proxy.size.width * (revealed ? fraction : 0))
                }
            }
            .frame(height: 3)

            if showsTimes {
                timeLabel(track.duration > 1 ? track.duration : nil, alignment: .trailing)
            }
        }
        .frame(height: showsTimes ? IslandMetrics.timeRowHeight : IslandMetrics.progressHeight)
    }

    /// Fixed width, so the bar does not shift as the digits change. A stream with no known
    /// length shows a dash for the total.
    private func timeLabel(_ seconds: TimeInterval?, alignment: Alignment) -> some View {
        Text(seconds.map(format) ?? "–:––")
            .font(.system(size: 9, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .frame(width: 36, alignment: alignment)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    private var fraction: CGFloat {
        guard track.duration > 1 else { return 0 }
        return CGFloat(min(max(track.position / track.duration, 0), 1))
    }
}

private extension View {
    /// Fades and lifts into place after `delay`, so a row of elements arrives in sequence.
    func reveal(_ revealed: Bool, delay: Double) -> some View {
        self
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 7)
            .blur(radius: revealed ? 0 : 3)
            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(revealed ? delay : 0),
                       value: revealed)
    }
}
