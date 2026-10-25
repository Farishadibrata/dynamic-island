import Combine
import CoreGraphics

@MainActor
final class IslandState: ObservableObject {
    @Published var isExpanded = false
    /// Short-lived opening shown when the track changes. It carries the media block alone,
    /// without the tray row, so a song change announces itself rather than looking like the
    /// island the user opened.
    @Published var isAnnouncing = false
    @Published var hasNotch = false
    /// The physical notch. The collapsed pill is this widened by its side slots, so the
    /// two are no longer the same rect.
    @Published var notchSize: CGSize = .zero
    @Published var collapsedSize: CGSize = .zero
    @Published var expandedSize: CGSize = .zero
    @Published var collapsedCornerRadius: CGFloat = 10

    /// Either kind of opening draws the island body rather than the notch pill.
    var isOpen: Bool { isExpanded || isAnnouncing }
}
