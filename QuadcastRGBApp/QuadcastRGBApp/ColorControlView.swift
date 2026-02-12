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

struct SettingsWindowContent: View {
    @EnvironmentObject var deviceManager: DeviceManager

    private var maxColors: Int {
        deviceManager.mode == .solid ? 1 : 10
    }

    var body: some View {
        VStack(spacing: 16) {
            connectionStatus
            modeSection
            colorSection
            animationSection

            if !deviceManager.connected {
                Button("Reconnect") {
                    deviceManager.reconnect()
                }
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(.ultraThinMaterial)
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        HStack {
            Spacer()
            Circle()
                .fill(deviceManager.connected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(deviceManager.connected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODE")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $deviceManager.mode) {
                ForEach(LightingMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Colors

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLORS")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6), spacing: 6) {
                ForEach(presetColors, id: \.self) { preset in
                    swatchButton(preset)
                }
            }

            Button("Custom Color...") {
                openColorPanel()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)

            if !deviceManager.colors.isEmpty {
                selectedColors
            }
        }
    }

    private var selectedColors: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Selected")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(deviceManager.colors.enumerated()), id: \.offset) { index, c in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(c.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
                        )
                        .onTapGesture {
                            if deviceManager.colors.count > 1 {
                                deviceManager.colors.remove(at: index)
                            }
                        }
                }
                Spacer()
                if deviceManager.colors.count > 1 {
                    Button("Clear") {
                        if let first = deviceManager.colors.first {
                            deviceManager.colors = [first]
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func swatchButton(_ preset: RGB) -> some View {
        let isSelected = deviceManager.colors.contains(preset)
        return RoundedRectangle(cornerRadius: 6)
            .fill(preset.color)
            .frame(width: 36, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
            .onTapGesture {
                addOrSetColor(preset)
            }
    }

    private func addOrSetColor(_ c: RGB) {
        if maxColors == 1 {
            deviceManager.colors = [c]
        } else if deviceManager.colors.contains(c) {
            if deviceManager.colors.count > 1 {
                deviceManager.colors.removeAll { $0 == c }
            }
        } else if deviceManager.colors.count < maxColors {
            deviceManager.colors.append(c)
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

    // MARK: - Animation

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANIMATION")
                .font(.caption)
                .foregroundStyle(.secondary)

            if deviceManager.mode.hasSpeed {
                sliderRow(label: "Speed", value: Binding(
                    get: { Double(deviceManager.speed) },
                    set: { deviceManager.speed = Int($0) }
                ), range: 0...100)
            }

            sliderRow(label: "Brightness", value: Binding(
                get: { Double(deviceManager.brightness) },
                set: { deviceManager.brightness = Int($0) }
            ), range: 0...100)

            if deviceManager.mode.hasDelay {
                sliderRow(label: "Delay", value: Binding(
                    get: { Double(deviceManager.delay) },
                    set: { deviceManager.delay = Int($0) }
                ), range: 0...100)
            }
        }
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
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
