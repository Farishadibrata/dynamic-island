import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandController {
    /// `collapsedShape`/`expandedShape` are the visible island in screen coordinates.
    /// `panel` is the expanded shape grown by the glow margin, and is constant: the panel
    /// never resizes, so the shape can animate inside a stable container.
    private struct Layout {
        let hasNotch: Bool
        let notch: CGRect
        let collapsedShape: CGRect
        let expandedShape: CGRect
        let panel: CGRect
    }

    private let state = IslandState()
    private let settings: AppSettings
    private let nowPlaying: NowPlayingService
    private let stats: SystemStats
    private let widgets: WidgetHub
    private let openSettings: () -> Void

    /// One panel per desktop of the notch display (just one when not shown on all spaces).
    /// A window that is a member of every space is treated as sticky and stays pinned during
    /// a three-finger swipe, so each desktop gets a panel of its own that slides with it.
    private var panels: [IslandPanel] = []
    private var panel: IslandPanel? { panels.first }
    private var warmedSpaces: Set<Int> = []
    private var isWarmingUp = false
    private var layout: Layout?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var hoverTimer: Timer?
    private var nowPlayingObserver: AnyCancellable?
    private var announceTimer: Timer?
    private var alertTimer: Timer?
    private var lastTrackID: String?

    /// The first track seen after launch is not a change, so it does not announce itself.
    private var isFirstTrack = true

    /// Whether the expanded body has to make room for the media block.
    private var hasNowPlaying = false

    /// Extra grace around the island where hovering still counts.
    private let hoverSlack: CGFloat = 6
    /// Room around the shape for the glow to fade out completely inside the panel.
    private let glowMargin: CGFloat = 40
    private let pollInterval: TimeInterval = 0.05
    /// How long a song change keeps the island open before it folds away again.
    private static let announcementDuration: TimeInterval = 5

    init(settings: AppSettings,
         nowPlaying: NowPlayingService,
         stats: SystemStats,
         widgets: WidgetHub,
         openSettings: @escaping () -> Void) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.stats = stats
        self.widgets = widgets
        self.openSettings = openSettings
    }

    func start() {
        guard panel == nil else { return }

        let initial = makeLayout(screen: NotchLocator.activeScreen())
        let first = makePanel(frame: initial?.panel ?? .zero)
        panels = [first]

        applyCollectionBehavior()
        if let initial { apply(initial) }
        first.orderFrontRegardless()

        widgets.setAlertHandler { [weak self] alert in self?.show(alert) }
        settings.onPreviewAlert = { [weak self] in
            self?.show(IslandAlert(kind: .battery, symbol: "bolt.fill", title: "Charging",
                                   subtitle: "80%", tint: .green), force: true)
        }
        syncPositionTracking()
        settings.onChange = { [weak self] in
            self?.syncPositionTracking()
            self?.relayout()
            self?.applyCollectionBehavior()
        }

        // A cursor poll rather than tracking areas: pointer position has to be known
        // even while the panel ignores mouse events, which is what keeps the
        // transparent glow margin click-through.
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.relayout() }
        }

        // A space transition can leave the panel nudged off the notch — a swipe was seen to
        // park it 81pt to the left of centre — so the frame is re-applied once the switch
        // lands. Cheap, and it guarantees the island snaps back onto the notch.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.isWarmingUp == false { self?.joinAllSpaces() }
                self?.relayout()
            }
        }

        // The panel is sized to fit the media block either way, so a track appearing only
        // changes the shape's height, never the window's.
        nowPlayingObserver = nowPlaying.$track
            .map { $0?.id }
            .removeDuplicates()
            .sink { [weak self] id in
                MainActor.assumeIsolated { self?.handleTrackChange(id) }
            }
        nowPlaying.start()
        stats.start()
        widgets.start()
    }

    /// A new song opens the island for a few seconds to show what came on, then it folds
    /// away again unless the pointer is on it.
    private func handleTrackChange(_ id: String?) {
        let previous = lastTrackID
        lastTrackID = id
        hasNowPlaying = id != nil

        guard let id, id != previous else {
            relayout()
            return
        }

        if isFirstTrack {
            isFirstTrack = false
            relayout()
            return
        }

        guard !state.isExpanded else {
            // Already open for the user: the marquee restarts, nothing else to do.
            relayout()
            return
        }

        announce()
    }

    private func announce() {
        announceTimer?.invalidate()
        state.isAnnouncing = true
        nowPlaying.showsDetail = true
        relayout()

        let timer = Timer(timeInterval: Self.announcementDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endAnnouncement() }
        }
        RunLoop.main.add(timer, forMode: .common)
        announceTimer = timer
    }

    private func endAnnouncement() {
        announceTimer?.invalidate()
        announceTimer = nil
        guard state.isAnnouncing else { return }

        state.isAnnouncing = false
        nowPlaying.showsDetail = state.isExpanded
        relayout()
    }

    private func pollPointer() {
        guard let layout else { return }

        let shape = state.isOpen ? layout.expandedShape : layout.collapsedShape
        let target = shape.insetBy(dx: -hoverSlack, dy: -hoverSlack)
        let inside = target.contains(NSEvent.mouseLocation)

        for panel in panels where panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }

        guard settings.expandOnHover else { return }
        if inside, !state.isExpanded {
            // Reaching for an announcement takes it over, tray row and all.
            expand()
        } else if !inside, state.isExpanded {
            collapse()
        }
    }

    /// Opens the island for a moment to show `alert`. It stays out of the way of an island
    /// the user opened, and a volume change updates the one already showing.
    private func show(_ alert: IslandAlert, force: Bool = false) {
        guard force || settings.alerts.contains(alert.kind), !state.isExpanded else { return }
        if alert.kind.isMinor, let showing = state.alert, !showing.kind.isMinor { return }

        state.alert = alert
        relayout()

        alertTimer?.invalidate()
        let timer = Timer(timeInterval: alert.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endAlert() }
        }
        RunLoop.main.add(timer, forMode: .common)
        alertTimer = timer
    }

    private func endAlert() {
        alertTimer?.invalidate()
        alertTimer = nil
        guard state.alert != nil else { return }
        state.alert = nil
        relayout()
    }

    private func expand() {
        guard !state.isExpanded else { return }
        endAlert()
        announceTimer?.invalidate()
        announceTimer = nil
        state.isAnnouncing = false
        state.isExpanded = true
        nowPlaying.showsDetail = true
        relayout()
    }

    private func collapse() {
        guard state.isExpanded else { return }
        state.isExpanded = false
        nowPlaying.showsDetail = false
        relayout()
    }

    /// Only meaningful when hover is off, where clicking the island is the trigger.
    private func handleTap() {
        guard !settings.expandOnHover else { return }
        if state.isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    /// The player is only asked where the playhead is when something shows it: the song glow
    /// needs it all the time, everything else only while the island is open.
    private func syncPositionTracking() {
        nowPlaying.tracksPosition = settings.glowStyle == .progress && settings.glowEffect != .off
    }

    private func relayout() {
        guard let layout = makeLayout() else { return }
        apply(layout)
    }

    private func applyCollectionBehavior() {
        // Deliberately neither `.canJoinAllSpaces` nor `.stationary`: both pin the window to
        // the screen, so a three-finger swipe slides the desktops past a frozen island.
        // See `joinAllSpaces` for how every desktop still gets an island.
        joinAllSpaces()
    }

    private func makePanel(frame: CGRect) -> IslandPanel {
        let hosting = NSHostingView(rootView: IslandContentView(
            state: state,
            settings: settings,
            nowPlaying: nowPlaying,
            stats: stats,
            widgets: widgets,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onTapIsland: { [weak self] in self?.handleTap() }
        ))
        let panel = IslandPanel(contentRect: frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
        // Above the menu bar, below system alerts.
        panel.level = IslandLevel.panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = hosting
        return panel
    }

    /// Spaces can be created or removed at any time, so this runs again on every space change.
    private func joinAllSpaces() {
        guard let first = panels.first else { return }
        guard settings.showOnAllSpaces else {
            for extra in panels.dropFirst() { extra.close() }
            panels = [first]
            return
        }

        let spaces = SpaceMembership.userSpaceIDs(on: first.screen ?? NotchLocator.activeScreen())
        guard !spaces.isEmpty else { return }

        while panels.count < spaces.count {
            panels.append(makePanel(frame: first.frame))
        }
        while panels.count > spaces.count {
            panels.removeLast().close()
        }
        for (panel, space) in zip(panels, spaces) {
            panel.orderFrontRegardless()
            SpaceMembership.pin(panel, toSpace: space, among: spaces)
        }
        if let layout { apply(layout) }

        let unseen = spaces.filter { !warmedSpaces.contains($0) }
        guard !unseen.isEmpty, !isWarmingUp else { return }
        isWarmingUp = true
        warmedSpaces.formUnion(spaces)
        let screen = first.screen
        Task { @MainActor in
            await SpaceMembership.warmUp(spaces, on: screen) { space in
                // Ordered in while its own desktop is showing, so it is genuinely on screen there.
                if let index = spaces.firstIndex(of: space), index < panels.count {
                    panels[index].orderFrontRegardless()
                    panels[index].displayIfNeeded()
                }
            }
            isWarmingUp = false
            // Ordering panels in while visiting can pull them onto the visited desktop.
            joinAllSpaces()
        }
    }

    private func apply(_ layout: Layout) {
        self.layout = layout
        state.hasNotch = layout.hasNotch
        state.notchSize = layout.notch.size
        state.collapsedSize = layout.collapsedShape.size
        state.expandedSize = layout.expandedShape.size
        state.collapsedCornerRadius = layout.hasNotch ? 10 : layout.notch.height / 2
        for panel in panels { panel.setFrame(layout.panel, display: true) }
    }

    private func makeLayout(screen: NSScreen? = nil) -> Layout? {
        guard let screen = screen ?? panel?.screen ?? NSScreen.main else { return nil }
        let notch = NotchLocator.notchRect(on: screen)
        let top = screen.frame.maxY
        // Without a glow nothing needs to spill, so the panel hugs the shape.
        let margin: CGFloat = settings.glowEffect == .off ? 0 : glowMargin

        let collapsedPillWidth = notch.width + settings.leftWing.collapsedWidth
            + settings.rightWing.collapsedWidth
        let fullWidth = max(settings.sizePreset.expandedWidth, collapsedPillWidth)
        // An alert is a smaller message than the full island, so it gets a narrower body.
        let showsAlert = state.alert != nil && !state.isExpanded
        let shapeWidth = showsAlert
            ? max(notch.width + (IslandMetrics.alertWingWidth + IslandMetrics.alertNotchGap) * 2, collapsedPillWidth)
            : fullWidth
        // Three bodies: the announcement shows the media block alone, the island the user
        // opened shows it with the tray beneath, and with nothing playing the preset rules.
        let hasWidgets = settings.widgetLeft != .none || settings.widgetRight != .none
        let usageRows = settings.activeSystemMetrics.count
        let hasStatus = !settings.activeStatusIcons.isEmpty
        let showsTimes = settings.sizePreset.showsTrackTimes
        let bodyHeight: CGFloat
        if state.isExpanded {
            bodyHeight = IslandMetrics.expandedBodyHeight(hasMedia: hasNowPlaying, hasWidgets: hasWidgets,
                                                         hasStatus: hasStatus, usageRows: usageRows,
                                                         showsTimes: showsTimes)
        } else if showsAlert {
            bodyHeight = IslandMetrics.alertBodyHeight
        } else if state.isAnnouncing {
            bodyHeight = IslandMetrics.announcementBodyHeight(showsTimes: showsTimes)
        } else {
            bodyHeight = IslandMetrics.expandedBodyHeight(hasMedia: false, hasWidgets: hasWidgets,
                                                         hasStatus: hasStatus, usageRows: usageRows,
                                                         showsTimes: showsTimes)
        }
        let shapeHeight = notch.height + bodyHeight
        let expandedShape = CGRect(x: notch.midX - shapeWidth / 2,
                                   y: top - shapeHeight,
                                   width: shapeWidth,
                                   height: shapeHeight)
        // No margin above: the island's flat top edge sits flush with the screen edge.
        // The panel always reserves room for the tall body, so starting or stopping a
        // track resizes the shape inside a window that never moves or resizes.
        let envelopeHeight = notch.height
            + IslandMetrics.expandedBodyHeight(hasMedia: true, hasWidgets: hasWidgets,
                                                         hasStatus: hasStatus, usageRows: usageRows,
                                                         showsTimes: showsTimes)
        // The panel is sized from the full width, so an alert never resizes the window.
        let panel = CGRect(x: notch.midX - fullWidth / 2 - margin,
                           y: top - envelopeHeight - margin,
                           width: fullWidth + margin * 2,
                           height: envelopeHeight + margin)

        // The collapsed pill is the notch widened by whichever side slots are in use.
        let collapsedWidth = notch.width + settings.leftWing.collapsedWidth
            + settings.rightWing.collapsedWidth
        let collapsedShape = CGRect(x: notch.midX - collapsedWidth / 2,
                                    y: notch.minY,
                                    width: collapsedWidth,
                                    height: notch.height)

        return Layout(hasNotch: screen.auxiliaryTopLeftArea != nil,
                      notch: notch,
                      collapsedShape: collapsedShape,
                      expandedShape: expandedShape,
                      panel: panel)
    }
}
