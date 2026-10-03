import SwiftUI

private let presetColors: [(name: String, rgb: RGB)] = [
    ("Red", RGB(r: 255, g: 0, b: 0)),
    ("Orange", RGB(r: 255, g: 128, b: 0)),
    ("Yellow", RGB(r: 255, g: 255, b: 0)),
    ("Green", RGB(r: 0, g: 255, b: 0)),
    ("Cyan", RGB(r: 0, g: 255, b: 255)),
    ("Blue", RGB(r: 0, g: 0, b: 255)),
    ("Purple", RGB(r: 128, g: 0, b: 255)),
    ("Pink", RGB(r: 255, g: 0, b: 128)),
    ("White", RGB(r: 255, g: 255, b: 255)),
    ("Warm white", RGB(r: 255, g: 200, b: 120)),
    ("Mint", RGB(r: 128, g: 255, b: 128)),
    ("Salmon", RGB(r: 255, g: 128, b: 128)),
]

struct SettingsWindowContent: View {
    @EnvironmentObject var dm: DeviceManager

    var body: some View {
        NavigationSplitView {
            List(LightingMode.allCases, id: \.self, selection: Binding<LightingMode?>(
                get: { dm.mode }, set: { if let mode = $0 { dm.mode = mode } }
            )) { mode in
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.label)
                        Text(mode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                } icon: {
                    Image(systemName: mode.icon)
                        .symbolRenderingMode(.hierarchical)
                }
                .tag(mode)
                .accessibilityIdentifier("mode-\(mode.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            DetailView()
        }
        .frame(minWidth: 700, minHeight: 620)
    }
}

private struct DetailView: View {
    @EnvironmentObject var dm: DeviceManager
    @State private var customColor: Color = .red
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxColors: Int { dm.mode == .solid ? 1 : 10 }
    private var visibleColors: [RGB] { Array(dm.colors.prefix(maxColors)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if dm.needsInputMonitoring { permissionBanner }
                preview
                colorSection
                selectedColors
                controls
            }
            .padding(28)
            .frame(maxWidth: 540, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(dm.mode.label)
        .navigationSubtitle(dm.mode.description)
        .toolbar {
            ToolbarItem(placement: .status) {
                Label(dm.connected ? "Connected" : "Disconnected",
                      systemImage: dm.connected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(dm.connected ? Color.green : Color.secondary)
                    .font(.caption)
                    .accessibilityIdentifier("connection-status")
            }
            ToolbarItem(placement: .primaryAction) {
                if !dm.connected {
                    Button("Reconnect", systemImage: "arrow.clockwise", action: dm.reconnect)
                        .accessibilityIdentifier("reconnect")
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: dm.mode)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Allow Input Monitoring", systemImage: "exclamationmark.shield")
                .font(.headline)
            Text("macOS requires this permission to control the microphone's lights. Allow QuadCast RGB in System Settings, then reconnect.")
                .font(.callout)
                .foregroundStyle(.secondary)
            GlassEffectContainer {
                HStack {
                    Button("Open System Settings", action: dm.openInputMonitoringSettings)
                        .buttonStyle(.glassProminent)
                    Button("Reconnect", action: dm.reconnect)
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Palette").font(.headline)
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: visibleColors.isEmpty ? [.black] : visibleColors.map { $0.scaled(brightness: dm.brightness).color },
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 64)
                .accessibilityLabel("Lighting palette at \(dm.brightness) percent brightness")
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Colors").font(.headline)
            GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 12), count: 6), spacing: 12) {
                    ForEach(presetColors, id: \.name) { preset in
                        ColorSwatch(color: preset.rgb, label: preset.name,
                                    isSelected: visibleColors.contains(preset.rgb)) {
                            addOrSetColor(preset.rgb)
                        }
                        .accessibilityIdentifier("color-\(preset.name)")
                    }
                }
            }
            GlassEffectContainer {
                HStack {
                    ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                        .accessibilityIdentifier("custom-color")
                    Button(maxColors == 1 ? "Use color" : "Add color") {
                        guard let color = NSColor(customColor).usingColorSpace(.sRGB) else { return }
                        addOrSetColor(RGB(r: UInt8(clamping: Int(color.redComponent * 255)),
                                         g: UInt8(clamping: Int(color.greenComponent * 255)),
                                         b: UInt8(clamping: Int(color.blueComponent * 255))))
                    }
                    .buttonStyle(.glass)
                    .disabled(maxColors > 1 && dm.colors.count >= maxColors)
                }
            }
        }
    }

    private var selectedColors: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(maxColors == 1 ? "Selected color" : "Palette · \(dm.colors.count)/10")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if maxColors > 1 && dm.colors.count > 1 {
                    Button("Keep first") { dm.colors = Array(dm.colors.prefix(1)) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            GlassEffectContainer(spacing: 6) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(visibleColors.enumerated()), id: \.offset) { index, color in
                        Button {
                            if dm.colors.count > 1 && maxColors > 1 { dm.colors.remove(at: index) }
                        } label: {
                            Circle().fill(color.color).frame(width: 18, height: 18).padding(7)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(color.color).interactive(), in: .circle)
                        .disabled(maxColors == 1 || dm.colors.count == 1)
                        .accessibilityLabel("Remove color \(index + 1), \(color.hexString)")
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Controls").font(.headline)
            slider("Brightness", icon: "sun.max", value: $dm.brightness)
            if dm.mode.hasSpeed { slider("Speed", icon: "hare", value: $dm.speed) }
            if dm.mode.hasDelay { slider("Delay", icon: "clock", value: $dm.delay) }
        }
    }

    private func slider(_ label: String, icon: String, value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Label(label, systemImage: icon).frame(width: 110, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }), in: 0...100, step: 1)
                .accessibilityLabel(label)
                .accessibilityIdentifier("slider-\(label)")
            Text("\(value.wrappedValue)").monospacedDigit().foregroundStyle(.secondary).frame(width: 30)
        }
        .font(.callout)
    }

    private func addOrSetColor(_ color: RGB) {
        if maxColors == 1 {
            dm.colors = [color]
        } else if dm.colors.contains(color) {
            if dm.colors.count > 1 { dm.colors.removeAll { $0 == color } }
        } else if dm.colors.count < maxColors {
            dm.colors.append(color)
        }
    }
}

private struct ColorSwatch: View {
    let color: RGB
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: 26, height: 26)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(color == RGB(r: 255, g: 255, b: 255) ? .black : .white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                }
                .padding(9)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color.color.opacity(0.3)).interactive(), in: .circle)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .help(label)
    }
}
