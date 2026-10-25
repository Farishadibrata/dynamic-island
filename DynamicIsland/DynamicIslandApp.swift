import SwiftUI

@main
struct DynamicIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let nowPlaying = NowPlayingService()
    private let stats = SystemStats()
    private let widgets = WidgetHub()
    private var island: IslandController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settingsWindow = SettingsWindowController(settings: settings)
        let island = IslandController(settings: settings, nowPlaying: nowPlaying, stats: stats, widgets: widgets) {
            settingsWindow.show()
        }
        let statusItem = StatusItemController()
        statusItem.install(onOpenSettings: { settingsWindow.show() })

        island.start()

        self.settingsWindow = settingsWindow
        self.island = island
        self.statusItem = statusItem
    }
}
