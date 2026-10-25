import AppKit
import Combine
import Foundation

/// A track as reported by a scriptable media app.
struct NowPlayingTrack: Equatable {
    let sourceID: String
    let title: String
    let artist: String
    let album: String
    var isPlaying: Bool
    let duration: TimeInterval
    /// Refreshed on its own, without re-reading the rest of the track.
    var position: TimeInterval
    let artworkURL: URL?

    /// Identity of one song, so the island can restart the marquee when it changes.
    var id: String { "\(sourceID)|\(title)|\(artist)" }
}

enum NowPlayingSource: String, CaseIterable {
    case spotify
    case music

    var appName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    /// Spotify reports the track length in milliseconds, Music in seconds.
    var durationScale: TimeInterval {
        switch self {
        case .spotify: 0.001
        case .music: 1
        }
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
}

/// Reads the current track over Apple Events.
///
/// `MediaRemote` is the usual route for this, but macOS 27 hands back an empty dictionary
/// to any app without Apple's private entitlement, so the scriptable players are queried
/// instead. That costs one Automation grant per player.
///
/// Every AppleScript property access is its own round trip to the player — around 20ms
/// each — which is why this is split into a cheap title probe, a position probe, and a
/// full read that only runs when the song actually changes.
enum NowPlayingReader {
    enum Outcome {
        case track(NowPlayingTrack)
        case denied
        /// The player is gone, or has nothing loaded.
        case unavailable
    }

    /// The user declined the Automation prompt, so this player is not worth asking again.
    private static let notAuthorised = -1743

    /// What the cheap per-poll probe returns: enough to tell whether the song changed and
    /// whether this player still owns the island.
    struct Probe {
        let title: String
        let isPlaying: Bool
    }

    static func probe(_ source: NowPlayingSource) -> Probe? {
        let (descriptor, _) = execute(script(for: source, detail: .tick))
        guard let title = descriptor?.atIndex(1)?.stringValue,
              !title.isEmpty,
              let state = descriptor?.atIndex(2)?.stringValue else { return nil }
        return Probe(title: title, isPlaying: state == "playing")
    }

    static func position(of source: NowPlayingSource) -> TimeInterval? {
        let (descriptor, _) = execute(script(for: source, detail: .position))
        guard let text = descriptor?.atIndex(1)?.stringValue else { return nil }
        return TimeInterval(text)
    }

    static func read(_ source: NowPlayingSource) -> Outcome {
        let (descriptor, errorCode) = execute(script(for: source, detail: .full), reportingErrors: true)
        if errorCode == notAuthorised { return .denied }

        guard let descriptor,
              descriptor.numberOfItems >= 7,
              let state = descriptor.atIndex(1)?.stringValue,
              !state.isEmpty,
              let title = descriptor.atIndex(3)?.stringValue,
              !title.isEmpty else { return .unavailable }

        func string(_ index: Int) -> String {
            descriptor.atIndex(index)?.stringValue ?? ""
        }

        return .track(NowPlayingTrack(
            sourceID: source.rawValue,
            title: title,
            artist: string(4),
            album: string(5),
            isPlaying: state == "playing",
            duration: (TimeInterval(string(6)) ?? 0) * source.durationScale,
            position: TimeInterval(string(7)) ?? 0,
            artworkURL: URL(string: string(2))
        ))
    }

    private enum Detail {
        case tick
        case position
        case full
    }

    /// `NSAppleScript` must stay on the thread that created it, so a fresh script is
    /// compiled for each execution on the caller's serial queue.
    private static func execute(_ source: String,
                                reportingErrors: Bool = false) -> (NSAppleEventDescriptor?, Int?) {
        guard let script = NSAppleScript(source: source) else { return (nil, nil) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error, reportingErrors, let code = error[NSAppleScript.errorNumber] as? Int {
            return (nil, code)
        }
        return (result, nil)
    }

    private static func script(for source: NowPlayingSource, detail: Detail) -> String {
        let player = source.appName

        switch detail {
        case .tick:
            return """
            if application "\(player)" is not running then return {}
            tell application "\(player)"
                try
                    set trackName to (name of current track)
                on error
                    return {}
                end try
                set stateText to "stopped"
                try
                    set stateText to (player state as string)
                end try
                return {trackName, stateText}
            end tell
            """

        case .position:
            return """
            if application "\(player)" is not running then return {}
            tell application "\(player)"
                try
                    return {((player position) as string)}
                on error
                    return {}
                end try
            end tell
            """

        case .full:
            return """
            if application "\(player)" is not running then return {}
            tell application "\(player)"
                try
                    set t to current track
                    set trackName to (name of t)
                on error
                    return {}
                end try
                set stateText to "stopped"
                try
                    set stateText to (player state as string)
                end try
                set trackPosition to 0
                try
                    set trackPosition to player position
                end try
                set artworkAddress to ""
                try
                    set artworkAddress to (artwork url of t)
                end try
                return {stateText, artworkAddress, trackName, (artist of t), (album of t), ¬
                    ((duration of t) as string), ((trackPosition) as string)}
            end tell
            """
        }
    }
}

/// Publishes the track the island should show.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var artwork: NSImage?

    /// The progress bar only shows while the island is open. Position costs an extra round
    /// trip, so it is read — and the poll restarts straight away — only then.
    var showsDetail = false {
        didSet {
            guard showsDetail != oldValue else { return }
            startPolling(immediately: true)
        }
    }

    /// The song glow follows the playhead even with the island folded, so it needs the
    /// position every poll, not just while the island is open.
    var tracksPosition = false {
        didSet {
            guard tracksPosition != oldValue else { return }
            startPolling(immediately: true)
        }
    }

    /// Fast enough that a skip shows up before the user looks away from the keyboard.
    private static let pollInterval: TimeInterval = 1
    private static let artworkCacheLimit = 24

    /// Apple Events block, so the scripts run off the main thread and only one poll is ever
    /// outstanding.
    private let queue = DispatchQueue(label: "com.local.dynamicisland.nowplaying")
    private var timer: Timer?
    private var isPolling = false
    private var deniedSources: Set<String> = []
    private var artworkCache: [String: NSImage] = [:]
    private var loadedArtworkURL: String?

    func start() {
        guard timer == nil else { return }
        startPolling(immediately: true)
    }

    /// Re-armed after every poll rather than left repeating, so an expansion can pull the
    /// next poll forward instead of waiting out the interval.
    private func startPolling(immediately: Bool) {
        timer?.invalidate()
        if immediately { poll() }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
                self?.startPolling(immediately: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard !isPolling else { return }

        // `isRunning` first: a script against a closed player would launch it.
        let sources = NowPlayingSource.allCases.filter {
            !deniedSources.contains($0.rawValue) && $0.isRunning
        }
        guard !sources.isEmpty else {
            clear()
            return
        }

        isPolling = true
        let current = track
        let wantsPosition = showsDetail || tracksPosition

        queue.async { [weak self] in
            let refresh = Self.refresh(sources: sources, current: current, wantsPosition: wantsPosition)
            Task { @MainActor [weak self] in self?.apply(refresh) }
        }
    }

    private enum Refresh {
        case track(NowPlayingTrack)
        /// Same song, nothing new to show.
        case unchanged
        case denied(NowPlayingSource)
        case nothing
    }

    /// Runs on the polling queue: every call here is a blocking Apple Event round trip.
    private static func refresh(sources: [NowPlayingSource],
                                current: NowPlayingTrack?,
                                wantsPosition: Bool) -> Refresh {
        // Stay on the player already showing something, so two open players cannot make
        // the island flap between them.
        var ordered = sources
        if let id = current?.sourceID,
           let index = ordered.firstIndex(where: { $0.rawValue == id }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }

        if let current, ordered.first?.rawValue == current.sourceID {
            let source = ordered[0]

            // Same song: one probe is a fraction of the cost of the full record.
            if let probe = NowPlayingReader.probe(source), probe.title == current.title {
                var moved = current
                moved.isPlaying = probe.isPlaying

                // A paused player keeps the island only while no other player is running,
                // so switching players does not leave the paused track on screen.
                if probe.isPlaying || ordered.count == 1 {
                    if wantsPosition, let position = NowPlayingReader.position(of: source) {
                        moved.position = position
                    }
                    return moved == current ? .unchanged : .track(moved)
                }

                switch discover(Array(ordered.dropFirst())) {
                case .track(let track): return .track(track)
                case .denied(let other): return .denied(other)
                case .unchanged, .nothing: return moved == current ? .unchanged : .track(moved)
                }
            }

            // The same player started a different song.
            switch NowPlayingReader.read(source) {
            case .track(let track): return .track(track)
            case .denied: return .denied(source)
            case .unavailable: break
            }
        }

        return discover(ordered)
    }

    /// The first player actually playing, else the first with anything loaded at all.
    private static func discover(_ sources: [NowPlayingSource]) -> Refresh {
        var paused: NowPlayingTrack?
        for source in sources {
            switch NowPlayingReader.read(source) {
            case .track(let track) where track.isPlaying: return .track(track)
            case .track(let track): paused = paused ?? track
            case .denied: return .denied(source)
            case .unavailable: continue
            }
        }
        return paused.map(Refresh.track) ?? .nothing
    }

    private func apply(_ refresh: Refresh) {
        isPolling = false

        switch refresh {
        case .track(let track):
            self.track = track
            loadArtwork()
        case .unchanged:
            break
        case .denied(let source):
            deniedSources.insert(source.rawValue)
            clear()
        case .nothing:
            clear()
        }
    }

    private func clear() {
        if track != nil { track = nil }
        if artwork != nil { artwork = nil }
        loadedArtworkURL = nil
    }

    private func loadArtwork() {
        guard let url = track?.artworkURL else {
            if artwork != nil { artwork = nil }
            loadedArtworkURL = nil
            return
        }

        let key = url.absoluteString
        guard key != loadedArtworkURL else { return }
        loadedArtworkURL = key

        if let cached = artworkCache[key] {
            artwork = cached
            return
        }

        if artwork != nil { artwork = nil }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.artworkCache[key] = image
                if self.artworkCache.count > Self.artworkCacheLimit {
                    self.artworkCache.removeAll()
                    self.artworkCache[key] = image
                }
                // A fetch that lands after the user skipped the track must not show.
                if self.loadedArtworkURL == key { self.artwork = image }
            }
        }.resume()
    }
}
