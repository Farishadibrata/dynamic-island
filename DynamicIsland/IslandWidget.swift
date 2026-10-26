import AppKit
import ApplicationServices
import Combine
import CoreAudio
import CoreWLAN
import EventKit
import Foundation
import IOKit.ps

/// What a card in the expanded island shows.
enum IslandWidget: String, CaseIterable, Identifiable {
    case none
    case calendar
    case reminders
    case timer
    case clock
    case battery
    case discord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .timer: "Focus timer"
        case .clock: "Clock"
        case .battery: "Battery"
        case .discord: "Discord mute"
        }
    }
}

/// Everything the widgets read from. Created once and shared, so a timer keeps running
/// while the island is folded away.
@MainActor
final class WidgetHub {
    let agenda = AgendaService()
    let timer = FocusTimer()
    let battery = BatteryMonitor()
    let discord = DiscordMute()
    let status = StatusMonitor()

    func setAlertHandler(_ handler: @escaping (IslandAlert) -> Void) {
        battery.onAlert = handler
        status.onAlert = handler
        timer.onAlert = handler
    }

    func start() {
        agenda.start()
        battery.start()
        status.start()
    }
}

/// Upcoming events and due reminders from EventKit.
///
/// Access is requested the first time a widget needs it, not at launch, so the system
/// prompt appears in context.
@MainActor
final class AgendaService: ObservableObject {
    enum Access { case notDetermined, granted, denied }

    struct Entry: Equatable {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    struct Reminder: Equatable {
        let title: String
        let due: Date?
    }

    @Published private(set) var calendarAccess: Access = .notDetermined
    @Published private(set) var reminderAccess: Access = .notDetermined
    @Published private(set) var events: [Entry] = []
    @Published private(set) var reminders: [Reminder] = []

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()

        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func requestCalendar() {
        // An accessory app is never frontmost by itself, and the system only shows the
        // permission dialog for an app that is.
        NSApp.activate(ignoringOtherApps: true)
        Task {
            _ = try? await store.requestFullAccessToEvents()
            refresh()
        }
    }

    func requestReminders() {
        // An accessory app is never frontmost by itself, and the system only shows the
        // permission dialog for an app that is.
        NSApp.activate(ignoringOtherApps: true)
        Task {
            _ = try? await store.requestFullAccessToReminders()
            refresh()
        }
    }

    private static func access(for type: EKEntityType) -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func refresh() {
        calendarAccess = Self.access(for: .event)
        reminderAccess = Self.access(for: .reminder)

        if calendarAccess == .granted {
            let now = Date()
            let predicate = store.predicateForEvents(withStart: now,
                                                     end: now.addingTimeInterval(36 * 3600),
                                                     calendars: nil)
            let upcoming = store.events(matching: predicate).filter { $0.endDate > now }
            // Timed events by start, then all-day ones, which would otherwise always lead.
            let sorted = upcoming.sorted {
                if $0.isAllDay != $1.isAllDay { return !$0.isAllDay }
                return $0.startDate < $1.startDate
            }
            events = sorted.prefix(6).map {
                Entry(title: $0.title ?? "Untitled", start: $0.startDate,
                      end: $0.endDate, isAllDay: $0.isAllDay)
            }
        } else {
            events = []
        }

        if reminderAccess == .granted {
            let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil,
                                                                  ending: endOfToday,
                                                                  calendars: nil)
            store.fetchReminders(matching: predicate) { [weak self] found in
                let mapped = (found ?? []).map {
                    Reminder(title: $0.title ?? "Untitled",
                             due: $0.dueDateComponents?.date)
                }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                Task { @MainActor in self?.reminders = mapped }
            }
        } else {
            reminders = []
        }
    }
}

/// A countdown that survives the island folding away.
@MainActor
final class FocusTimer: ObservableObject {
    enum Phase { case idle, running, paused }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 0

    var onAlert: ((IslandAlert) -> Void)?

    private var endDate: Date?
    private var timer: Timer?
    private var sessionMinutes = 0

    /// Idle starts a fresh countdown of `minutes`; running pauses; paused resumes.
    func toggle(minutes: Int) {
        switch phase {
        case .idle:
            sessionMinutes = minutes
            remaining = TimeInterval(minutes * 60)
            resume()
        case .running:
            pause()
        case .paused:
            resume()
        }
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remaining = 0
        phase = .idle
    }

    private func resume() {
        endDate = Date().addingTimeInterval(remaining)
        phase = .running

        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func pause() {
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
        timer?.invalidate()
        timer = nil
        phase = .paused
    }

    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            reset()
            NSSound.beep()
            onAlert?(IslandAlert(kind: .timer, symbol: "timer", title: "Focus done",
                                 subtitle: "\(sessionMinutes) min", tint: .orange, duration: 5))
        } else {
            remaining = left
        }
    }
}

/// Charge of the internal battery, polled slowly: it changes over minutes, not seconds.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isOnPower = false

    var onAlert: ((IslandAlert) -> Void)?

    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private var lastOnPower: Bool?
    private var lastLevel: Int?

    func start() {
        guard timer == nil else { return }
        sample()

        // The system says when the charger goes in or out, so that is shown at once; the
        // timer below only keeps the percentage fresh.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.sample() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        }

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            level = nil
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }

            level = Int((Double(current) / Double(maximum) * 100).rounded())
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            isOnPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            announceChanges()
            return
        }
        level = nil
    }

    /// Plugging in or out, dropping to 20% or 10% on battery, and reaching full.
    private func announceChanges() {
        defer {
            lastOnPower = isOnPower
            lastLevel = level
        }
        guard let level, let lastOnPower, let lastLevel else { return }

        if isOnPower != lastOnPower {
            onAlert?(isOnPower
                ? IslandAlert(kind: .battery, symbol: "bolt.fill", title: "Charging",
                              subtitle: "\(level)%", level: Double(level) / 100, tint: .green)
                : IslandAlert(kind: .battery, symbol: BatteryGlyph.symbol(level: level, charging: false),
                              title: "On battery", subtitle: "\(level)%", level: Double(level) / 100))
        } else if !isOnPower, let threshold = [10, 20].first(where: { level <= $0 && lastLevel > $0 }) {
            onAlert?(IslandAlert(kind: .battery,
                                 symbol: threshold == 10 ? "battery.0" : "battery.25",
                                 title: "Low battery", subtitle: "\(level)%",
                                 level: Double(level) / 100,
                                 tint: threshold == 10 ? .red : .orange, duration: 5))
        } else if isOnPower, level == 100, lastLevel < 100 {
            onAlert?(IslandAlert(kind: .battery, symbol: "battery.100", title: "Fully charged",
                                 subtitle: "100%", level: 1, tint: .green))
        }
    }
}

/// A key combination to press on the user's behalf.
struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    /// `CGEventFlags` raw value, limited to the four modifier keys.
    var flags: UInt64
    var label: String
}

/// Toggles Discord's mute by pressing the shortcut the user bound to "Toggle Mute" in
/// Discord's own keybind settings.
///
/// Discord offers other apps no way to read or set mute, so this is blind: it presses the
/// key, and `isMuted` is only a guess that starts unmuted and flips on each press. Discord's
/// keybinds are global, so the press works while another app is in front.
@MainActor
final class DiscordMute: ObservableObject {
    enum Problem { case noShortcut, needsAccessibility }

    @Published private(set) var isMuted = false
    @Published private(set) var problem: Problem?
    private var hasPrompted = false

    func toggle(using shortcut: KeyShortcut?) {
        guard let shortcut else {
            problem = .noShortcut
            return
        }
        guard AXIsProcessTrusted() else {
            problem = .needsAccessibility
            // The system prompt once per launch; after that a tap opens the pane itself,
            // so a permission that did not stick is not answered with another dialog.
            if hasPrompted {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } else {
                hasPrompted = true
                AXIsProcessTrustedWithOptions(
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            }
            return
        }

        problem = nil
        NSLog("DiscordMute: pressing keyCode %d flags %llu", shortcut.keyCode, shortcut.flags)
        press(shortcut)
        isMuted.toggle()
    }

    /// The guess drifts if mute is changed in Discord itself, so it can be set back.
    func resetGuess() {
        isMuted = false
    }

    /// Presses the modifiers as keys of their own, then the key, then releases in reverse.
    /// A global-hotkey hook that tracks which keys are down only sees a combination if the
    /// modifiers arrive as events too; flags on the key event alone are not enough for it.
    private func press(_ shortcut: KeyShortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags(rawValue: shortcut.flags)

        // Virtual key codes of the modifier keys, with the flag each one raises.
        let modifiers: [(code: CGKeyCode, flag: CGEventFlags)] = [
            (59, .maskControl), (58, .maskAlternate), (56, .maskShift), (55, .maskCommand),
        ].filter { flags.contains($0.flag) }

        var held: CGEventFlags = []
        for modifier in modifiers {
            held.insert(modifier.flag)
            post(modifier.code, down: true, flags: held, source: source)
        }

        post(shortcut.keyCode, down: true, flags: flags, source: source)
        post(shortcut.keyCode, down: false, flags: flags, source: source)

        for modifier in modifiers.reversed() {
            held.remove(modifier.flag)
            post(modifier.code, down: false, flags: held, source: source)
        }
    }

    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource?) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        // Hooks that poll key state need a moment between transitions to see each one.
        usleep(8_000)
    }
}

/// Wi-Fi, Bluetooth and sound output, polled every few seconds. Each read is a cheap local
/// query that needs no permission: signal strength rather than the network name, the
/// Bluetooth power flag from the system preferences, and the default output device.
@MainActor
final class StatusMonitor: ObservableObject {
    @Published private(set) var wifiOn = true
    /// 0...1, from the received signal strength.
    @Published private(set) var wifiStrength = 0.0
    @Published private(set) var bluetoothOn = false
    @Published private(set) var bluetoothConnected = 0
    @Published private(set) var volume = 0.0
    @Published private(set) var isMuted = false

    var onAlert: ((IslandAlert) -> Void)?

    private var timer: Timer?
    private var soundTimer: Timer?
    private var tick = 0
    private var knownDevices: Set<String>?
    private var hasSoundBaseline = false
    private var lastBrightness: Double?

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Volume is watched much faster than the rest, so the key presses show as they happen.
        let soundTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleSound()
                self?.sampleBrightness()
            }
        }
        RunLoop.main.add(soundTimer, forMode: .common)
        self.soundTimer = soundTimer
    }

    private func sample() {
        let interface = CWWiFiClient.shared().interface()
        wifiOn = interface?.powerOn() ?? false
        let rssi = interface?.rssiValue() ?? 0
        // 0 means not associated; -90 is a barely usable link and -40 an excellent one.
        wifiStrength = rssi == 0 ? 0 : min(max(Double(rssi + 90) / 50, 0.05), 1)

        // Slower than the rest: it is a subprocess, and Bluetooth changes rarely.
        if tick % 2 == 0 { sampleBluetooth() }
        tick += 1
    }

    /// `IOBluetooth` aborts a process that has no Bluetooth permission, so the state is
    /// read from `system_profiler` instead, which needs none and answers in a few ms.
    private func sampleBluetooth() {
        Task.detached(priority: .utility) { [weak self] in
            let reading = Self.readBluetooth()
            await self?.apply(reading)
        }
    }

    private func apply(_ reading: (isOn: Bool, devices: [String])) {
        bluetoothOn = reading.isOn
        bluetoothConnected = reading.devices.count

        let now = Set(reading.devices)
        defer { knownDevices = now }
        // The first reading is the starting point, not news.
        guard let known = knownDevices else { return }
        for name in reading.devices where !known.contains(name) {
            onAlert?(IslandAlert(kind: .bluetooth, symbol: Self.symbol(forDevice: name),
                                 title: name, subtitle: "Connected", tint: .blue))
        }
    }

    private static func symbol(forDevice name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("keyboard") { return "keyboard" }
        if lowered.contains("mouse") || lowered.contains("trackpad") { return "computermouse.fill" }
        if lowered.contains("pods") || lowered.contains("buds") || lowered.contains("head")
            || lowered.contains("wh-") || lowered.contains("beats") { return "headphones" }
        if lowered.contains("speaker") { return "hifispeaker.fill" }
        return "dot.radiowaves.left.and.right"
    }

    private nonisolated static func readBluetooth() -> (isOn: Bool, devices: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return (false, []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = (root["SPBluetoothDataType"] as? [[String: Any]])?.first else {
            return (false, [])
        }
        let properties = entry["controller_properties"] as? [String: Any]
        let isOn = properties?["controller_state"] as? String == "attrib_on"
        // Each connected device is a one-key dictionary named after the device.
        let devices = (entry["device_connected"] as? [[String: Any]] ?? []).flatMap(\.keys).sorted()
        return (isOn, devices)
    }

    /// `DisplayServices` is private, so it is looked up at run time; without it brightness
    /// alerts simply never appear.
    private typealias BrightnessReader = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let readBrightness: BrightnessReader? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                                  RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: BrightnessReader.self)
    }()

    private func sampleBrightness() {
        guard let read = Self.readBrightness else { return }

        // The built-in panel, which is the one the brightness keys move.
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &displays, &count)
        let panel = displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()

        var value: Float = 0
        guard read(panel, &value) == 0 else { return }

        let level = Double(value)
        defer { lastBrightness = level }
        guard let previous = lastBrightness, abs(level - previous) > 0.004 else { return }

        onAlert?(IslandAlert(kind: .brightness,
                             symbol: level < 0.35 ? "sun.min.fill" : "sun.max.fill",
                             title: "Brightness",
                             subtitle: "\(Int((level * 100).rounded()))%",
                             level: level, tint: .yellow, duration: 1.6))
    }

    private func sampleSound() {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return }

        // The system's own volume control ('vmvc'), which is what the keys and menu bar move.
        let previousVolume = volume, previousMuted = isMuted
        var level = Float32(0)
        size = UInt32(MemoryLayout<Float32>.size)
        address = AudioObjectPropertyAddress(mSelector: 0x766D_7663,
                                             mScope: kAudioObjectPropertyScopeOutput,
                                             mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr {
            volume = Double(level)
        }

        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                             mScope: kAudioObjectPropertyScopeOutput,
                                             mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr {
            isMuted = muted != 0
        }

        defer { hasSoundBaseline = true }
        guard hasSoundBaseline,
              abs(volume - previousVolume) > 0.004 || isMuted != previousMuted else { return }

        let silent = isMuted || volume <= 0.001
        let symbol = silent ? "speaker.slash.fill" : (volume < 0.34 ? "speaker.wave.1.fill"
                     : (volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        onAlert?(IslandAlert(kind: .volume, symbol: symbol,
                             title: isMuted ? "Muted" : "Volume",
                             subtitle: isMuted ? nil : "\(Int((volume * 100).rounded()))%",
                             level: isMuted ? 0 : volume, duration: 1.6))
    }
}
