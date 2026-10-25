import SwiftUI

struct SettingsView: View {
    static let size = CGSize(width: 460, height: 500)

    @ObservedObject var settings: AppSettings
    @State private var tab: Tab = .island

    private enum Tab: String, CaseIterable, Identifiable {
        case island = "Island"
        case expanded = "Expanded"
        case glow = "Glow"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .island: "capsule.tophalf.filled"
            case .expanded: "rectangle.expand.vertical"
            case .glow: "sparkles"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            ScrollView {
                VStack(spacing: 14) {
                    switch tab {
                    case .island: islandPage
                    case .expanded: expandedPage
                    case .glow: glowPage
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.background)
    }

    // MARK: Chrome

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if tab == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.quaternary)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == item ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("Dynamic Island \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: Pages

    private var islandPage: some View {
        Group {
            card("Size", symbol: "arrow.left.and.right") {
                Picker("Island size", selection: $settings.sizePreset) {
                    ForEach(IslandSizePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                hint("Compact skips the track times beside the progress bar.")
            }

            card("Small state", symbol: "capsule") {
                row("Left") { pick(IslandWingItem.allCases, selection: $settings.leftWing) { $0.title } }
                row("Right") { pick(IslandWingItem.allCases, selection: $settings.rightWing) { $0.title } }
            }

            card("Behavior", symbol: "cursorarrow.motionlines") {
                toggleRow("Expand on hover", isOn: $settings.expandOnHover)
                toggleRow("Show on all Spaces", isOn: $settings.showOnAllSpaces)
                hint(settings.expandOnHover
                     ? "Hover the notch to expand. Move the pointer away to collapse."
                     : "Click the notch to expand or collapse.")
            }
        }
    }

    private var expandedPage: some View {
        Group {
            card("Widgets", symbol: "square.grid.2x2") {
                row("Left") { pick(IslandWidget.allCases, selection: $settings.widgetLeft) { $0.title } }
                row("Right") { pick(IslandWidget.allCases, selection: $settings.widgetRight) { $0.title } }
                row("Focus timer") {
                    Picker("Focus length", selection: $settings.focusMinutes) {
                        ForEach([15, 25, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                row("Discord mute") {
                    ShortcutRecorderRow(shortcut: $settings.discordShortcut)
                }
            }

            card("Status icons", symbol: "battery.75") {
                checkboxes(StatusIcon.allCases, binding: statusBinding) { $0.title }
                hint("Click an icon in the island to open its System Settings pane.")
            }

            card("System usage", symbol: "gauge.with.dots.needle.50percent") {
                checkboxes(SystemMetric.allCases, binding: metricBinding) { $0.title }
                hint("Disk shows what is left of the whole. Memory shows used of total.")
            }
        }
    }

    private var glowPage: some View {
        Group {
            card("Effect", symbol: "wand.and.stars") {
                row("Palette") { pick(GlowEffect.allCases, selection: $settings.glowEffect) { $0.title } }
                row("Motion") {
                    Picker("Shape", selection: $settings.glowStyle) {
                        ForEach(GlowStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                toggleRow("Match playing media", isOn: $settings.glowFollowsMedia)
                row("Colors") {
                    HStack(spacing: 8) {
                        ForEach(0..<settings.customGlowColors.count, id: \.self) { index in
                            ColorPicker("Colour \(index + 1)", selection: colorBinding(index),
                                        supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                }
                .disabled(settings.glowEffect != .custom)
                .opacity(settings.glowEffect == .custom ? 1 : 0.4)

                hint("Song makes the lit edge fill around the island as the track plays.")
            }

            // Only the sliders are gated on the effect: the palette picker and the inner
            // glow switch stay live, or choosing "Off" would lock the user out of the
            // controls needed to switch the glow back on.
            card("Intensity", symbol: "slider.horizontal.3") {
                slider("Border", value: $settings.glowIntensity, range: 0.1...1.0)
                    .disabled(!glowActive)
                    .opacity(glowActive ? 1 : 0.4)
                slider("Speed", value: $settings.glowSpeed, range: 0.4...2.5, unit: "×")
                    .disabled(!glowActive)
                    .opacity(glowActive ? 1 : 0.4)
            }

            card("Notch halo", symbol: "circle.dashed") {
                toggleRow("Inner glow", isOn: $settings.innerGlowEnabled)
                slider("Strength", value: $settings.innerGlowIntensity, range: 0.1...1.0)
                    .disabled(!innerGlowActive)
                    .opacity(innerGlowActive ? 1 : 0.4)
                hint("A halo around the physical notch while the island is expanded.")
            }
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(_ title: String,
                                     symbol: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.6))
        }
    }

    private func row<Control: View>(_ label: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            control()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Toggle(label, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pick<Value: Hashable & Identifiable>(_ values: [Value],
                                                      selection: Binding<Value>,
                                                      title: @escaping (Value) -> String) -> some View {
        Picker("", selection: selection) {
            ForEach(values) { Text(title($0)).tag($0) }
        }
        .labelsHidden()
        .frame(width: 160)
    }

    private func checkboxes<Value: Hashable & Identifiable>(_ values: [Value],
                                                            binding: @escaping (Value) -> Binding<Bool>,
                                                            title: @escaping (Value) -> String) -> some View {
        HStack(spacing: 16) {
            ForEach(values) { value in
                Toggle(title(value), isOn: binding(value))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
            Spacer(minLength: 0)
        }
    }

    private func slider(_ label: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        unit: String = "%") -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
            Text(unit == "%" ? "\(Int((value.wrappedValue * 100).rounded()))%"
                             : String(format: "%.1f%@", value.wrappedValue, unit))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: State

    private var glowActive: Bool { settings.glowEffect != .off }
    private var innerGlowActive: Bool { settings.innerGlowEnabled && glowActive }

    private func statusBinding(_ icon: StatusIcon) -> Binding<Bool> {
        Binding(
            get: { settings.statusIcons.contains(icon) },
            set: { isOn in
                if isOn { settings.statusIcons.insert(icon) } else { settings.statusIcons.remove(icon) }
            }
        )
    }

    private func metricBinding(_ metric: SystemMetric) -> Binding<Bool> {
        Binding(
            get: { settings.systemMetrics.contains(metric) },
            set: { isOn in
                if isOn { settings.systemMetrics.insert(metric) } else { settings.systemMetrics.remove(metric) }
            }
        )
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { settings.customGlowColors[index].color },
            set: { newValue in
                var colors = settings.customGlowColors
                colors[index] = GlowColor(newValue)
                settings.customGlowColors = colors
            }
        )
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
