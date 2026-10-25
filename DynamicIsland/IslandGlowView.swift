import SwiftUI

/// Where the playing song is, for the glow style that follows it.
struct GlowProgress: Equatable {
    var position: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
}

/// Glow drawn *behind* the opaque island body, so only the outward half is visible.
///
/// A dim, steady wash keeps the island lit, and a bright comet runs around its outline.
/// With the song style, a progress line under the island fills as the track plays instead.
/// Everything is shaped by filling or stroking the island outline and blurring afterwards.
/// It must stay this way round: masking a blurred silhouette clips the result to the mask
/// view's frame, which shows up as a visible box around the island.
struct IslandGlowView: View {
    let effect: GlowEffect
    let colors: [Color]
    let style: GlowStyle
    let intensity: Double
    let speed: Double
    let shape: UnevenRoundedRectangle
    /// Used by the `.progress` style; without it that style falls back to the comet.
    var progress: GlowProgress?

    /// The reported position only updates every so often, so the line runs ahead of it on
    /// the clock between updates and snaps to the next report.
    @State private var anchorPosition = 0.0
    @State private var anchorDate = Date()

    /// Where the comet's fade-in starts, as a fraction of a lap. The rest is tail.
    private let tailStart = 0.55

    var body: some View {
        if effect == .off || colors.isEmpty {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !effect.animates)) { context in
                GeometryReader { proxy in
                    if let fraction = songFraction(at: context.date) {
                        progressLine(fraction, size: proxy.size)
                    } else {
                        orbit(angle: GlowPalette.angle(at: context.date, effect: effect, speed: speed))
                    }
                }
            }
            .allowsHitTesting(false)
            .onAppear { anchor(to: progress?.position) }
            .onChange(of: progress?.position) { _, position in anchor(to: position) }
        }
    }

    // MARK: Orbiting comet

    private func orbit(angle: Double) -> some View {
        ZStack {
            // Steady wash, so the island always has a halo between passes.
            shape.fill(AnyShapeStyle(wash(angle: angle)))
                .blur(radius: 14)
                .opacity(0.3 * intensity)

            // Comet: a soft bloom plus a crisp rim, both fading into a long tail.
            shape.fill(AnyShapeStyle(comet(angle: angle)))
                .blur(radius: 10)
                .opacity(0.75 * intensity)

            shape.stroke(AnyShapeStyle(comet(angle: angle)), lineWidth: 3)
                .blur(radius: 1.5)
                .opacity(intensity)
        }
    }

    private func wash(angle: Double) -> AngularGradient {
        AngularGradient(gradient: Gradient(colors: closedStops),
                        center: .center,
                        startAngle: .degrees(angle),
                        endAngle: .degrees(angle + 360))
    }

    /// The angular style laps the outline; the linear one sweeps left to right. The song
    /// style laps like the angular one whenever there is no song to follow.
    private func comet(angle: Double) -> AnyShapeStyle {
        switch style {
        case .angular, .progress:
            return AnyShapeStyle(AngularGradient(stops: angularStops,
                                                 center: .center,
                                                 startAngle: .degrees(angle),
                                                 endAngle: .degrees(angle + 360)))
        case .linear:
            let progress = angle / 360
            let start = progress * 1.6 - 0.6
            return AnyShapeStyle(LinearGradient(stops: linearStops,
                                                startPoint: UnitPoint(x: start, y: 0.5),
                                                endPoint: UnitPoint(x: start + 0.6, y: 0.5)))
        }
    }

    // MARK: Song progress

    private func anchor(to position: TimeInterval?) {
        anchorPosition = position ?? 0
        anchorDate = Date()
    }

    /// How far through the song, 0...1, or nil when the style does not follow one.
    private func songFraction(at date: Date) -> Double? {
        guard style == .progress, let progress, progress.duration > 1 else { return nil }
        let elapsed = progress.isPlaying ? date.timeIntervalSince(anchorDate) : 0
        return min(max((anchorPosition + elapsed) / progress.duration, 0), 1)
    }

    /// A line hugging the island's visible edge: down the left side, round the bottom
    /// corner, along the bottom and up the right side, so it reads as part of the island
    /// rather than floating under it. A faint track shows the whole length, with the played
    /// part lit in the palette and a bright head where the song is.
    private func progressLine(_ fraction: Double, size: CGSize) -> some View {
        let thickness: CGFloat = 3
        // Outside the island by half the line, so it sits against the body instead of
        // being half hidden behind it.
        let outline = IslandEdge(radius: shape.cornerRadii.bottomLeading + thickness / 2)
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: -thickness / 2, dy: -thickness / 2)
        let path = outline.path(in: rect)
        let head = path.trimmedPath(from: 0, to: max(fraction, 0.004)).currentPoint ?? .zero

        let gradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        let lit = outline.trim(from: 0, to: max(fraction, 0.004))
        let style = StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)

        return ZStack {
            outline.stroke(.white.opacity(0.14), style: style)

            // Bloom under the played part.
            lit.stroke(gradient, style: style)
                .blur(radius: 6)
                .opacity(0.9 * intensity)

            lit.stroke(gradient, style: style)
                .opacity(intensity)

            Circle()
                .fill(.white)
                .frame(width: thickness + 2, height: thickness + 2)
                .shadow(color: colors.last ?? .white, radius: 5)
                .position(x: head.x, y: head.y)
                .opacity(intensity)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: Gradient stops

    /// Transparent for most of the lap, then the palette fading in towards a bright head.
    /// The first colour starts at zero alpha in its own hue, so the fade does not pass
    /// through grey.
    private var angularStops: [Gradient.Stop] {
        let faded = (colors.first ?? .clear).opacity(0)
        var stops = [Gradient.Stop(color: faded, location: 0),
                     Gradient.Stop(color: faded, location: tailStart)]
        for (index, color) in colors.enumerated() {
            let location = tailStart + (1 - tailStart) * Double(index + 1) / Double(colors.count)
            stops.append(Gradient.Stop(color: color, location: location))
        }
        return stops
    }

    private var linearStops: [Gradient.Stop] {
        let first = (colors.first ?? .clear).opacity(0)
        let last = (colors.last ?? .clear).opacity(0)
        var stops = [Gradient.Stop(color: first, location: 0)]
        for (index, color) in colors.enumerated() {
            let location = 0.15 + 0.7 * Double(index) / Double(max(colors.count - 1, 1))
            stops.append(Gradient.Stop(color: color, location: location))
        }
        stops.append(Gradient.Stop(color: last, location: 1))
        return stops
    }

    /// A conic gradient needs its last stop to match its first or the seam is visible.
    private var closedStops: [Color] {
        guard colors.count > 1,
              let first = colors.first,
              colors.last != first else { return colors }
        return colors + [first]
    }
}

/// The visible edge of the island as an open path: down the left side, round the corner,
/// along the bottom, round the other corner and up the right side. The top edge is left out
/// because it sits against the top of the screen.
private struct IslandEdge: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                    radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                    radius: r, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
