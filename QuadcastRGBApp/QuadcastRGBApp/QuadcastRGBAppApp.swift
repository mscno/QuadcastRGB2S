import SwiftUI
import ServiceManagement

@main
struct QuadcastRGBApp: App {
    @StateObject private var deviceManager = DeviceManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(deviceManager)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundStyle(deviceManager.primaryColor)
        }
        .menuBarExtraStyle(.menu)

        Window("QuadCast RGB Settings", id: "settings") {
            SettingsWindowContent()
                .environmentObject(deviceManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 500)
    }
}

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

        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            deviceManager.stop()
            NSApplication.shared.terminate(nil)
        }
    }
}
