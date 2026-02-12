import SwiftUI
import ServiceManagement

@main
struct QuadcastRGBApp: App {
    @StateObject private var deviceManager = DeviceManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(deviceManager)
        } label: {
            Image(nsImage: menuBarIcon(ledColor: deviceManager.primaryColor))
        }
        .menuBarExtraStyle(.menu)

        Window("QuadCast RGB", id: "settings") {
            SettingsWindowContent()
                .environmentObject(deviceManager)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 680, height: 580)
        .defaultLaunchBehavior(.presented)
    }
}

// MARK: - Menu Bar Icon

private func menuBarIcon(ledColor: Color) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: true) { rect in
        let w = rect.width
        let h = rect.height

        // Mic capsule body
        let bodyRect = NSRect(x: w * 0.22, y: 0, width: w * 0.56, height: h * 0.62)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: w * 0.22, yRadius: w * 0.22)
        NSColor.labelColor.setFill()
        bodyPath.fill()

        // Three LED strips
        let led = NSColor(ledColor)
        for i in 0..<3 {
            let y = h * (0.12 + Double(i) * 0.16)
            let strip = NSRect(x: w * 0.28, y: y, width: w * 0.44, height: h * 0.06)
            let stripPath = NSBezierPath(roundedRect: strip, xRadius: 1, yRadius: 1)
            led.setFill()
            stripPath.fill()
        }

        // Stand
        NSColor.labelColor.setFill()
        NSBezierPath(rect: NSRect(x: w * 0.42, y: h * 0.62, width: w * 0.16, height: h * 0.24)).fill()

        // Base
        NSBezierPath(roundedRect: NSRect(x: w * 0.22, y: h * 0.84, width: w * 0.56, height: h * 0.1),
                      xRadius: h * 0.03, yRadius: h * 0.03).fill()

        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Menu Bar Menu

struct MenuBarMenu: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(deviceManager.connected ? .green : .red)
                .frame(width: 6, height: 6)
            Text(deviceManager.connected ? "Connected" : "Disconnected")
        }
        .disabled(true)

        Divider()

        Toggle("Start at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()

        Button("Open Settings") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                for window in NSApp.windows where window.level == .normal {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }

        Divider()

        Button("Quit") {
            deviceManager.stop()
            NSApplication.shared.terminate(nil)
        }
    }
}
