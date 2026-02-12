import SwiftUI

@main
struct QuadcastRGBApp: App {
    @StateObject private var deviceManager = DeviceManager.shared

    var body: some Scene {
        MenuBarExtra {
            ColorControlView()
                .environmentObject(deviceManager)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundStyle(deviceManager.primaryColor)
        }
        .menuBarExtraStyle(.window)
    }
}
