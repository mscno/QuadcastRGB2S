import SwiftUI

private let presetColors: [RGB] = [
    RGB(r: 255, g: 0, b: 0),       // Red
    RGB(r: 255, g: 128, b: 0),     // Orange
    RGB(r: 255, g: 255, b: 0),     // Yellow
    RGB(r: 0, g: 255, b: 0),       // Green
    RGB(r: 0, g: 255, b: 255),     // Cyan
    RGB(r: 0, g: 0, b: 255),       // Blue
    RGB(r: 128, g: 0, b: 255),     // Purple
    RGB(r: 255, g: 0, b: 128),     // Pink
    RGB(r: 255, g: 255, b: 255),   // White
    RGB(r: 255, g: 200, b: 120),   // Warm white
    RGB(r: 128, g: 255, b: 128),   // Mint
    RGB(r: 255, g: 128, b: 128),   // Salmon
]

// MARK: - Settings Window

struct SettingsWindowContent: View {
    @EnvironmentObject var dm: DeviceManager
    @State private var selectedMode: LightingMode?

    var body: some View {
        NavigationSplitView {
            List(LightingMode.allCases, id: \.self, selection: $selectedMode) { mode in
                ModeRow(mode: mode, isActive: dm.mode == mode, tint: dm.primaryColor)
                    .tag(mode)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            DetailView()
        }
        .frame(minWidth: 660, minHeight: 560)
        .onAppear { selectedMode = dm.mode }
        .onChange(of: selectedMode) { _, newMode in
            if let m = newMode { dm.mode = m }
        }
    }
}

// MARK: - Sidebar Mode Row

private struct ModeRow: View {
    let mode: LightingMode
    let isActive: Bool
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.label)
                Text(mode.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: mode.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? tint : .secondary)
                .frame(width: 20)
        }
    }
}

// MARK: - Detail View

private struct DetailView: View {
    @EnvironmentObject var dm: DeviceManager
    @State private var brightness: Double = 100
    @State private var speed: Double = 50
    @State private var delay: Double = 10

    private var maxColors: Int {
        dm.mode == .solid ? 1 : 10
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                previewBar
                colorSection
                if !dm.colors.isEmpty {
                    selectedColors
                }
                animationSection
            }
            .padding(24)
            .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(dm.mode.label)
        .navigationSubtitle(dm.mode.description)
        .toolbar {
            ToolbarItem(placement: .status) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dm.connected ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(dm.connected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if !dm.connected {
                    Button("Reconnect", systemImage: "arrow.clockwise") {
                        dm.reconnect()
                    }
                }
            }
        }
        .animation(.smooth, value: dm.mode)
        .onAppear { syncFromModel() }
        .onChange(of: dm.mode) { _, _ in syncFromModel() }
        .onChange(of: brightness) { _, val in dm.brightness = Int(val) }
        .onChange(of: speed) { _, val in dm.speed = Int(val) }
        .onChange(of: delay) { _, val in dm.delay = Int(val) }
    }

    private func syncFromModel() {
        brightness = Double(dm.brightness)
        speed = Double(dm.speed)
        delay = Double(dm.delay)
    }

    // MARK: - Preview

    private var previewBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)

            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: dm.colors.isEmpty
                        ? [Color.black]
                        : dm.colors.map { $0.scaled(brightness: dm.brightness).color },
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.08))
                )
                .shadow(
                    color: (dm.colors.first?.color ?? .clear).opacity(0.25),
                    radius: 16, y: 6
                )
        }
    }

    // MARK: - Colors

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Colors")
                    .font(.headline)
                Spacer()
                Button("Custom Color...") {
                    openColorPanel()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(presetColors, id: \.self) { preset in
                    ColorSwatch(
                        color: preset,
                        isSelected: dm.colors.contains(preset),
                        action: { addOrSetColor(preset) }
                    )
                }
            }
        }
    }

    private var selectedColors: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if dm.colors.count > 1 {
                    Button("Clear") {
                        if let first = dm.colors.first {
                            dm.colors = [first]
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(Array(dm.colors.enumerated()), id: \.offset) { index, c in
                    Circle()
                        .fill(c.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                        .onTapGesture {
                            if dm.colors.count > 1 {
                                dm.colors.remove(at: index)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Animation Controls

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls")
                .font(.headline)

            sliderRow(label: "Brightness", icon: "sun.max", value: $brightness)

            if dm.mode.hasSpeed {
                sliderRow(label: "Speed", icon: "hare", value: $speed)
            }

            if dm.mode.hasDelay {
                sliderRow(label: "Delay", icon: "clock", value: $delay)
            }
        }
    }

    private func sliderRow(
        label: String,
        icon: String,
        value: Binding<Double>
    ) -> some View {
        HStack(spacing: 10) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Slider(value: value, in: 0...100, step: 1)
            Text("\(Int(value.wrappedValue))")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Color Management

    private func addOrSetColor(_ c: RGB) {
        if maxColors == 1 {
            dm.colors = [c]
        } else if dm.colors.contains(c) {
            if dm.colors.count > 1 {
                dm.colors.removeAll { $0 == c }
            }
        } else if dm.colors.count < maxColors {
            dm.colors.append(c)
        }
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = false
        panel.mode = .wheel
        panel.isContinuous = false

        let handler = ColorPanelHandler { nsColor in
            let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            let rgb = RGB(
                r: UInt8(max(0, min(255, r * 255))),
                g: UInt8(max(0, min(255, g * 255))),
                b: UInt8(max(0, min(255, b * 255)))
            )
            DispatchQueue.main.async {
                self.addOrSetColor(rgb)
            }
        }
        panel.setTarget(handler)
        panel.setAction(#selector(ColorPanelHandler.colorChanged(_:)))
        panel.orderFront(nil)
        objc_setAssociatedObject(panel, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Color Swatch

private struct ColorSwatch: View {
    let color: RGB
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color.color)
            .frame(width: 40, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(color: isSelected ? color.color.opacity(0.4) : .clear, radius: 6)
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
    }
}

// MARK: - Color Panel Handler

private class ColorPanelHandler: NSObject {
    let callback: (NSColor) -> Void
    init(callback: @escaping (NSColor) -> Void) {
        self.callback = callback
    }
    @objc func colorChanged(_ sender: NSColorPanel) {
        callback(sender.color)
    }
}
