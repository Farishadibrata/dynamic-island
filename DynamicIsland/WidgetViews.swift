import AppKit
import SwiftUI

/// The row of widget cards in the expanded island. A slot set to "None" gives its width
/// to the other one.
struct IslandWidgetRow: View {
    @ObservedObject var settings: AppSettings
    let hub: WidgetHub

    var body: some View {
        HStack(spacing: IslandMetrics.widgetSpacing) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, widget in
                WidgetCard(widget: widget, settings: settings, hub: hub)
            }
        }
        .frame(height: IslandMetrics.widgetHeight)
    }

    private var slots: [IslandWidget] {
        [settings.widgetLeft, settings.widgetRight].filter { $0 != .none }
    }
}

/// Shared card chrome: a small caption line, a main value and a detail line.
private struct CardFrame<Detail: View>: View {
    let symbol: String
    let caption: String
    let value: String
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(caption.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            detail
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
        }
    }
}

private struct WidgetCard: View {
    let widget: IslandWidget
    @ObservedObject var settings: AppSettings
    let hub: WidgetHub

    var body: some View {
        switch widget {
        case .none:
            EmptyView()
        case .calendar:
            CalendarCard(agenda: hub.agenda)
        case .reminders:
            RemindersCard(agenda: hub.agenda)
        case .timer:
            TimerCard(timer: hub.timer, minutes: settings.focusMinutes)
        case .clock:
            ClockCard()
        case .battery:
            BatteryCard(battery: hub.battery)
        case .discord:
            DiscordCard(discord: hub.discord, shortcut: settings.discordShortcut)
        }
    }
}

private struct CalendarCard: View {
    @ObservedObject var agenda: AgendaService

    var body: some View {
        switch agenda.calendarAccess {
        case .notDetermined:
            Button { agenda.requestCalendar() } label: {
                CardFrame(symbol: "calendar", caption: "Calendar", value: "Allow access") {
                    Text("Tap to show your events")
                }
            }
            .buttonStyle(.plain)
            .hoverHighlight()
        case .denied:
            Button { PrivacySettings.open(.calendars) } label: {
                CardFrame(symbol: "calendar", caption: "Calendar", value: "Access is off") {
                    Text("Tap to open Settings")
                }
            }
            .buttonStyle(.plain)
            .hoverHighlight()
        case .granted:
            Button { AppLauncher.open("com.apple.iCal") } label: {
                if let event = agenda.events.first {
                    CardFrame(symbol: "calendar", caption: "Next up", value: event.title) {
                        Text(timing(of: event))
                    }
                } else {
                    CardFrame(symbol: "calendar", caption: "Calendar", value: "Nothing scheduled") {
                        Text("Your next 36 hours are clear")
                    }
                }
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .help("Open Calendar")
        }
    }

    private func timing(of event: AgendaService.Entry) -> String {
        if event.isAllDay { return "All day" }
        let clock = event.start.formatted(date: .omitted, time: .shortened)
        let minutes = Int(event.start.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))" }
        if minutes < 60 { return "in \(minutes) min · \(clock)" }
        if minutes < 24 * 60 { return "in \(minutes / 60) h \(minutes % 60) min · \(clock)" }
        return event.start.formatted(.dateTime.weekday(.abbreviated)) + " · " + clock
    }
}

private struct RemindersCard: View {
    @ObservedObject var agenda: AgendaService

    var body: some View {
        switch agenda.reminderAccess {
        case .notDetermined:
            Button { agenda.requestReminders() } label: {
                CardFrame(symbol: "checklist", caption: "Reminders", value: "Allow access") {
                    Text("Tap to show what's due")
                }
            }
            .buttonStyle(.plain)
            .hoverHighlight()
        case .denied:
            Button { PrivacySettings.open(.reminders) } label: {
                CardFrame(symbol: "checklist", caption: "Reminders", value: "Access is off") {
                    Text("Tap to open Settings")
                }
            }
            .buttonStyle(.plain)
            .hoverHighlight()
        case .granted:
            Button { AppLauncher.open("com.apple.reminders") } label: {
                if let reminder = agenda.reminders.first {
                    CardFrame(symbol: "checklist", caption: "Due today", value: reminder.title) {
                        Text(detail(reminder))
                    }
                } else {
                    CardFrame(symbol: "checklist", caption: "Reminders", value: "All done") {
                        Text("Nothing due today")
                    }
                }
            }
            .buttonStyle(.plain)
            .hoverHighlight()
            .help("Open Reminders")
        }
    }

    private func detail(_ reminder: AgendaService.Reminder) -> String {
        let others = agenda.reminders.count - 1
        let time = reminder.due.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Today"
        return others > 0 ? "\(time) · +\(others) more" : time
    }
}

private struct TimerCard: View {
    @ObservedObject var timer: FocusTimer
    let minutes: Int

    var body: some View {
        Button { timer.toggle(minutes: minutes) } label: {
            CardFrame(symbol: "timer", caption: "Focus", value: clock) {
                switch timer.phase {
                case .idle: Text("Tap to start · \(minutes) min")
                case .running: Text("Running · tap to pause")
                case .paused: Text("Paused · tap to resume")
                }
            }
            .overlay(alignment: .topTrailing) {
                if timer.phase != .idle {
                    Button { timer.reset() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Reset timer")
                }
            }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    private var clock: String {
        let total = Int((timer.phase == .idle ? Double(minutes * 60) : timer.remaining).rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ClockCard: View {
    var body: some View {
        Button { AppLauncher.open("com.apple.clock") } label: {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                CardFrame(symbol: "clock",
                          caption: context.date.formatted(.dateTime.weekday(.wide)),
                          value: context.date.formatted(date: .omitted, time: .shortened)) {
                    Text(context.date.formatted(.dateTime.day().month(.wide)))
                }
            }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .help("Open Clock")
    }
}

private struct BatteryCard: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        Button { NSWorkspace.shared.open(StatusIcon.battery.settingsURL) } label: {
            if let level = battery.level {
                CardFrame(symbol: symbol(for: level), caption: "Battery", value: "\(level)%") {
                    Text(battery.isCharging ? "Charging" : (battery.isOnPower ? "On power" : "On battery"))
                }
            } else {
                CardFrame(symbol: "powerplug", caption: "Battery", value: "No battery") {
                    Text("Running on power")
                }
            }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .help("Open Battery settings")
    }

    private func symbol(for level: Int) -> String {
        BatteryGlyph.symbol(level: level, charging: battery.isCharging)
    }
}

private struct DiscordCard: View {
    @ObservedObject var discord: DiscordMute
    let shortcut: KeyShortcut?

    var body: some View {
        Button { discord.toggle(using: shortcut) } label: {
            CardFrame(symbol: discord.isMuted ? "mic.slash.fill" : "mic.fill",
                      caption: "Discord",
                      value: discord.isMuted ? "Muted" : "Mic on") {
                Text(detail)
            }
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .contextMenu {
            Button("Mark as unmuted") { discord.resetGuess() }
        }
    }

    private var detail: String {
        switch discord.problem {
        case .noShortcut: "Set a shortcut in Settings"
        case .needsAccessibility: "Enable in Accessibility, then tap"
        case nil: shortcut == nil ? "Set a shortcut in Settings" : "Tap to toggle · \(shortcut?.label ?? "")"
        }
    }
}

private enum PrivacySettings {
    enum Pane: String {
        case calendars = "Privacy_Calendars"
        case reminders = "Privacy_Reminders"
    }

    static func open(_ pane: Pane) {
        let url = "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

/// A row of live status icons. Each shows its current state and opens its System Settings
/// pane when clicked.
struct StatusIconRow: View {
    let icons: [StatusIcon]
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var status: StatusMonitor

    var body: some View {
        HStack(spacing: IslandMetrics.widgetSpacing) {
            ForEach(icons) { icon in
                StatusTile(icon: icon, symbol: symbol(icon), label: label(icon),
                           dimmed: isOff(icon),
                           variableValue: icon == .wifi && status.wifiOn ? max(status.wifiStrength, 0.05) : nil)
            }
        }
        .frame(height: IslandMetrics.statusHeight)
    }

    private func symbol(_ icon: StatusIcon) -> String {
        switch icon {
        case .battery:
            return BatteryGlyph.symbol(level: battery.level ?? 100, charging: battery.isCharging)
        case .wifi:
            return status.wifiOn ? "wifi" : "wifi.slash"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        case .sound:
            if status.isMuted || status.volume <= 0.001 { return "speaker.slash.fill" }
            switch status.volume {
            case ..<0.34: return "speaker.wave.1.fill"
            case ..<0.67: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        }
    }

    private func label(_ icon: StatusIcon) -> String {
        switch icon {
        case .battery: battery.level.map { "\($0)%" } ?? "AC"
        case .wifi: status.wifiOn ? "On" : "Off"
        case .bluetooth:
            !status.bluetoothOn ? "Off" : (status.bluetoothConnected > 0 ? "\(status.bluetoothConnected) connected" : "On")
        case .sound: status.isMuted ? "Muted" : "\(Int((status.volume * 100).rounded()))%"
        }
    }

    private func isOff(_ icon: StatusIcon) -> Bool {
        switch icon {
        case .battery: false
        case .wifi: !status.wifiOn
        case .bluetooth: !status.bluetoothOn
        case .sound: status.isMuted
        }
    }
}

private struct StatusTile: View {
    let icon: StatusIcon
    let symbol: String
    let label: String
    let dimmed: Bool
    let variableValue: Double?

    @State private var isHovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(icon.settingsURL)
        } label: {
            VStack(spacing: 3) {
                glyph
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 16)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(dimmed ? 0.4 : 0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.16 : 0.08))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Open \(icon.title) settings")
    }

    @ViewBuilder
    private var glyph: some View {
        if let variableValue {
            Image(systemName: symbol, variableValue: variableValue)
        } else {
            Image(systemName: symbol)
        }
    }
}

/// Battery symbol for a charge level, shared by the card and the status icon.
enum BatteryGlyph {
    static func symbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Opens an app by bundle identifier, bringing it forward if it is already running.
private enum AppLauncher {
    static func open(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

private extension View {
    /// A faint wash while the pointer is over a card, so it reads as something to click.
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

private struct HoverHighlight: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
