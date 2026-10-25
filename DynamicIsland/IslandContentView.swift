import SwiftUI

/// Geometry shared by the island body and the controller that sizes the panel.
enum IslandMetrics {
    static let horizontalPadding: CGFloat = 14
    /// Space between the notch and the first row of content.
    static let contentTopPadding: CGFloat = 8
    static let contentBottomPadding: CGFloat = 10
    static let widgetHeight: CGFloat = 54
    static let widgetSpacing: CGFloat = 8
    static let statusHeight: CGFloat = 44
    static let usageRowHeight: CGFloat = 16
    static let usageRowSpacing: CGFloat = 7
    static let blockSpacing: CGFloat = 8

    static let artworkSide: CGFloat = 44
    static let progressHeight: CGFloat = 3
    /// Artwork row plus the gap and the progress bar under it.
    /// Time labels beside the progress bar are taller than the bar alone.
    static let timeRowHeight: CGFloat = 12

    static func mediaBlockHeight(showsTimes: Bool) -> CGFloat {
        artworkSide + 6 + (showsTimes ? timeRowHeight : progressHeight)
    }

    /// Body height below the notch for the expanded island: the media block when a track
    /// is playing, the widget row, and the system readings, each separated by a gap.
    static func expandedBodyHeight(hasMedia: Bool, hasWidgets: Bool, hasStatus: Bool,
                                   usageRows: Int, showsTimes: Bool) -> CGFloat {
        var blocks: [CGFloat] = []
        if hasMedia { blocks.append(mediaBlockHeight(showsTimes: showsTimes)) }
        if hasWidgets { blocks.append(widgetHeight) }
        if hasStatus { blocks.append(statusHeight) }
        if usageRows > 0 {
            blocks.append(CGFloat(usageRows) * usageRowHeight
                + CGFloat(usageRows - 1) * usageRowSpacing)
        }

        let gaps = CGFloat(max(blocks.count - 1, 0)) * blockSpacing
        // Nothing to show still leaves a body that reads as an opened island.
        return max(contentTopPadding + contentBottomPadding + blocks.reduce(0, +) + gaps, 48)
    }

    /// Body height for a song change, which shows the media block with no tray row.
    static func announcementBodyHeight(showsTimes: Bool) -> CGFloat {
        contentTopPadding + mediaBlockHeight(showsTimes: showsTimes) + contentBottomPadding
    }
}

struct IslandContentView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var stats: SystemStats
    let widgets: WidgetHub
    @State private var palette: [Color] = []
    var onOpenSettings: () -> Void
    var onTapIsland: () -> Void

    private var size: CGSize {
        state.isOpen ? state.expandedSize : state.collapsedSize
    }

    private var cornerRadius: CGFloat {
        state.isOpen ? 26 : state.collapsedCornerRadius
    }

    /// The top corners are always square: the island is flush with the screen edge, so it
    /// reads as growing out of it, collapsed or expanded.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0,
                               bottomLeadingRadius: cornerRadius,
                               bottomTrailingRadius: cornerRadius,
                               topTrailingRadius: 0,
                               style: .continuous)
    }

    private var glowProgress: GlowProgress? {
        guard let track = nowPlaying.track, track.duration > 1 else { return nil }
        return GlowProgress(position: track.position, duration: track.duration,
                            isPlaying: track.isPlaying)
    }

    /// While music plays the glow takes the colours of the cover, collapsed or open; with
    /// nothing playing, or the option off, it is the user's palette.
    private var glowColors: [Color] {
        guard settings.glowFollowsMedia,
              nowPlaying.track?.isPlaying == true,
              let first = palette.first else { return settings.glowColors }
        // One vivid colour on its own gets a neighbour on the wheel, so the comet has a
        // gradient to travel through.
        let colors = palette.count > 1 ? palette : [first, ArtworkAccent.companion(of: first)]
        return colors + [first]
    }

    var body: some View {
        // The ZStack fills the panel, which never changes size. Each shape is centred in
        // that constant container, so it grows outward from the notch rather than being
        // pushed sideways by a container that is resizing at the same time.
        ZStack(alignment: .top) {
            IslandGlowView(effect: settings.glowEffect,
                           colors: glowColors,
                           style: settings.glowStyle,
                           intensity: settings.glowIntensity,
                           speed: settings.glowSpeed,
                           shape: shape,
                           progress: glowProgress)
                .frame(width: size.width, height: size.height)

            island
                .frame(width: size.width, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { palette = nowPlaying.artwork.flatMap(ArtworkAccent.palette) ?? [] }
        .onChange(of: nowPlaying.artwork) { _, artwork in
            palette = artwork.flatMap(ArtworkAccent.palette) ?? []
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.isOpen)
        // A track starting or ending changes the expanded height while the island is
        // already open, so that growth needs to animate too.
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.expandedSize)
    }

    private var island: some View {
        shape
            .fill(.black)
            .overlay(alignment: .top) { notchCollar }
            .overlay(alignment: .top) { content }
            .overlay(alignment: .top) { wings }
            .overlay { shape.strokeBorder(.white.opacity(0.09), lineWidth: 0.5) }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { onTapIsland() }
            .contextMenu {
                Button("Settings…") { onOpenSettings() }
                Divider()
                Button("Quit Dynamic Island") { NSApp.terminate(nil) }
            }
    }

    /// The two side slots of the collapsed pill, flanking the notch.
    private var wings: some View {
        HStack(spacing: 0) {
            wing(settings.leftWing)
            Spacer(minLength: 0)
            wing(settings.rightWing)
        }
        .frame(width: state.collapsedSize.width, height: state.collapsedSize.height)
        .opacity(state.isOpen ? 0 : 1)
    }

    private func wing(_ item: IslandWingItem) -> some View {
        IslandWing(item: item, nowPlaying: nowPlaying, stats: stats, isActive: !state.isOpen)
            .frame(width: item.collapsedWidth)
    }

    /// The running track, when there is one, with the widget row underneath it. A song
    /// change shows the media block on its own; the widgets belong to the island the user
    /// opened.
    private var content: some View {
        VStack(spacing: IslandMetrics.blockSpacing) {
            if let track = nowPlaying.track, state.isOpen {
                NowPlayingView(track: track,
                               artwork: nowPlaying.artwork,
                               accent: palette.first,
                               showsTimes: settings.sizePreset.showsTrackTimes,
                               isActive: state.isOpen)
            }

            if state.isExpanded, settings.widgetLeft != .none || settings.widgetRight != .none {
                IslandWidgetRow(settings: settings, hub: widgets)
            }

            if state.isExpanded, !settings.activeStatusIcons.isEmpty {
                StatusIconRow(icons: settings.activeStatusIcons,
                              battery: widgets.battery,
                              status: widgets.status)
            }

            if state.isExpanded, !settings.activeSystemMetrics.isEmpty {
                SystemUsageView(metrics: settings.activeSystemMetrics, stats: stats)
            }
        }
        .padding(.horizontal, IslandMetrics.horizontalPadding)
        // Keep the row clear of the physical notch, which overlaps the island's top.
        .padding(.top, state.hasNotch
                 ? state.notchSize.height + IslandMetrics.contentTopPadding
                 : IslandMetrics.contentTopPadding + 4)
        .padding(.bottom, IslandMetrics.contentBottomPadding)
        .opacity(state.isOpen ? 1 : 0)
    }

    /// Halo hugging the physical notch cutout, so the effect wraps the notch instead of
    /// sitting under it as a band. Reuses the glow view, so it shares palette and phase
    /// with the outer border glow. Only drawn when expanded — collapsed, the border glow
    /// already hugs the notch.
    private var notchCollar: some View {
        // The glow bleeds inward as well as out; the notch is repainted black on top so
        // only the outward halo survives and the cutout still reads as a notch.
        ZStack(alignment: .top) {
            IslandGlowView(effect: settings.glowEffect,
                           colors: glowColors,
                           style: settings.glowStyle,
                           intensity: settings.innerGlowIntensity,
                           speed: settings.glowSpeed,
                           shape: notchShape)
                .frame(width: state.notchSize.width, height: state.notchSize.height)

            notchShape
                .fill(.black)
                .frame(width: state.notchSize.width, height: state.notchSize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(showsInnerGlow ? 1 : 0)
    }

    private var showsInnerGlow: Bool {
        state.isOpen && settings.innerGlowEnabled && settings.glowEffect != .off
    }

    /// Square top corners: the notch is flush with the screen edge.
    private var notchShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0,
                               bottomLeadingRadius: state.collapsedCornerRadius,
                               bottomTrailingRadius: state.collapsedCornerRadius,
                               topTrailingRadius: 0,
                               style: .continuous)
    }
}
