import SwiftUI
import Combine

@MainActor
final class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    @Published var mode: LightingMode = .solid
    @Published var colors: [RGB] = [RGB(r: 255, g: 0, b: 0)]
    @Published var speed: Int = 50
    @Published var delay: Int = 10
    @Published var brightness: Int = 100
    @Published var connected: Bool = false
    @Published var needsInputMonitoring: Bool = false

    var primaryColor: Color {
        (colors.first ?? .black).color
    }

    private let generator: FrameGenerator
    private var worker: DeviceWorker?
    private var session = 0
    private var settingsSubscription: AnyCancellable?

    private init() {
        generator = FrameGenerator(mode: .solid, colors: [RGB(r: 255, g: 0, b: 0)], speed: 50, delay: 10, brightness: 100)
        if !Self.isTesting { loadSettings() }
        generator.regenerate(mode: mode, colors: colors, speed: speed, delay: delay, brightness: brightness)
        observeSettings()
        // Unit/UI tests never touch USB devices or the user's saved settings.
        if !Self.isTesting {
            start()
        }
    }

    func start() {
        guard worker == nil else { return }
        session += 1
        let token = session
        let newWorker = DeviceWorker(transport: HIDTransport(), generator: generator) { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                self.connected = status == .connected
                self.needsInputMonitoring = status == .needsPermission
            }
        }
        worker = newWorker
        newWorker.start()
    }

    func stop() {
        session += 1
        worker?.stop()
        worker = nil
        connected = false
    }

    func reconnect() {
        stop()
        needsInputMonitoring = false
        start()
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private func observeSettings() {
        settingsSubscription = Publishers.MergeMany(
            $mode.map { _ in () }.eraseToAnyPublisher(),
            $colors.map { _ in () }.eraseToAnyPublisher(),
            $speed.map { _ in () }.eraseToAnyPublisher(),
            $delay.map { _ in () }.eraseToAnyPublisher(),
            $brightness.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(40), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            self?.onSettingsChanged()
        }
    }

    private func onSettingsChanged() {
        generator.regenerate(mode: mode, colors: colors, speed: speed, delay: delay, brightness: brightness)
        persistSettings()
    }

    // MARK: - Persistence

    private static var isTesting: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        return false
        #endif
    }

    private static var settingsDefaults: UserDefaults {
        if Self.isTesting {
            return UserDefaults(suiteName: "com.mscno.QuadcastRGBApp.tests")!
        }
        return .standard
    }

    private func persistSettings() {
        guard !Self.isTesting else { return }
        let defaults = Self.settingsDefaults
        defaults.set(mode.rawValue, forKey: "lightingMode")
        defaults.set(colors.map { $0.hexString }, forKey: "colors")
        defaults.set(speed, forKey: "speed")
        defaults.set(delay, forKey: "delay")
        defaults.set(brightness, forKey: "brightness")
    }

    private func loadSettings() {
        let defaults = Self.settingsDefaults
        if let modeStr = defaults.string(forKey: "lightingMode"),
           let m = LightingMode(rawValue: modeStr) {
            mode = m
        }
        if let hexes = defaults.stringArray(forKey: "colors"), !hexes.isEmpty {
            let parsed = hexes.compactMap { RGB(hex: $0) }
            if !parsed.isEmpty { colors = Array(parsed.prefix(10)) }
        }
        if defaults.object(forKey: "speed") != nil { speed = min(100, max(0, defaults.integer(forKey: "speed"))) }
        if defaults.object(forKey: "delay") != nil { delay = min(100, max(0, defaults.integer(forKey: "delay"))) }
        if defaults.object(forKey: "brightness") != nil { brightness = min(100, max(0, defaults.integer(forKey: "brightness"))) }
    }
}

/// The worker owns this object and accesses its HID context only on its queue.
private final class HIDTransport: DeviceTransport, @unchecked Sendable {
    private var context: OpaquePointer?
    var permissionGranted: Bool { qc2s_tcc_listen_access_allowed() != 0 }
    func open() -> Bool {
        context = qc2s_open()
        return context != nil
    }
    func send(_ frame: AnimationFrame) -> Bool {
        guard let context else { return false }
        return qc2s_set_frame(context, frame.upper.r, frame.upper.g, frame.upper.b,
                              frame.lower.r, frame.lower.g, frame.lower.b) == 0
    }
    func isConnected() -> Bool { qc2s_is_connected(context) != 0 }
    func close() {
        qc2s_close(context)
        context = nil
    }
}
