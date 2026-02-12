import SwiftUI
import Combine

@MainActor
final class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    @Published var mode: LightingMode = .solid {
        didSet { onSettingsChanged() }
    }
    @Published var colors: [RGB] = [RGB(r: 255, g: 0, b: 0)] {
        didSet { onSettingsChanged() }
    }
    @Published var speed: Int = 50 {
        didSet { onSettingsChanged() }
    }
    @Published var delay: Int = 10 {
        didSet { onSettingsChanged() }
    }
    @Published var brightness: Int = 100 {
        didSet { onSettingsChanged() }
    }
    @Published var connected: Bool = false

    var primaryColor: Color {
        (colors.first ?? .black).color
    }

    private var ctx: OpaquePointer?
    private let lock = NSLock()
    private let generator: FrameGenerator
    private var workerThread: Thread?
    private var running = false

    private init() {
        generator = FrameGenerator(mode: .solid, colors: [RGB(r: 255, g: 0, b: 0)], speed: 50, delay: 10, brightness: 100)
        loadSettings()
        generator.regenerate(mode: mode, colors: colors, speed: speed, delay: delay, brightness: brightness)
        start()
    }

    func start() {
        guard !running else { return }
        running = true
        let thread = Thread { [weak self] in
            self?.workerLoop()
        }
        thread.name = "QC2S-Worker"
        thread.qualityOfService = .userInitiated
        thread.start()
        workerThread = thread
    }

    func stop() {
        running = false
        workerThread = nil
        lock.lock()
        if let c = ctx { qc2s_close(c); ctx = nil }
        lock.unlock()
        connected = false
    }

    func reconnect() {
        stop()
        start()
    }

    // MARK: - Private

    private func onSettingsChanged() {
        generator.regenerate(mode: mode, colors: colors, speed: speed, delay: delay, brightness: brightness)
        persistSettings()
    }

    private func workerLoop() {
        while running {
            lock.lock()
            let currentCtx = ctx
            lock.unlock()

            if let c = currentCtx {
                let frame = generator.nextFrame()
                let res = qc2s_set_frame(
                    c,
                    frame.upper.r, frame.upper.g, frame.upper.b,
                    frame.lower.r, frame.lower.g, frame.lower.b
                )
                if res < 0 {
                    lock.lock()
                    qc2s_close(c)
                    ctx = nil
                    lock.unlock()
                    DispatchQueue.main.async { [weak self] in
                        self?.connected = false
                    }
                    continue
                }
            } else {
                let newCtx = qc2s_open()
                if let c = newCtx {
                    lock.lock()
                    ctx = c
                    lock.unlock()
                    DispatchQueue.main.async { [weak self] in
                        self?.connected = true
                    }
                } else {
                    Thread.sleep(forTimeInterval: 2.0)
                }
                continue
            }
        }
    }

    // MARK: - Persistence

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: "lightingMode")
        defaults.set(colors.map { $0.hexString }, forKey: "colors")
        defaults.set(speed, forKey: "speed")
        defaults.set(delay, forKey: "delay")
        defaults.set(brightness, forKey: "brightness")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let modeStr = defaults.string(forKey: "lightingMode"),
           let m = LightingMode(rawValue: modeStr) {
            mode = m
        }
        if let hexes = defaults.stringArray(forKey: "colors"), !hexes.isEmpty {
            let parsed = hexes.compactMap { RGB(hex: $0) }
            if !parsed.isEmpty { colors = parsed }
        }
        if defaults.object(forKey: "speed") != nil { speed = defaults.integer(forKey: "speed") }
        if defaults.object(forKey: "delay") != nil { delay = defaults.integer(forKey: "delay") }
        if defaults.object(forKey: "brightness") != nil { brightness = defaults.integer(forKey: "brightness") }
    }
}
