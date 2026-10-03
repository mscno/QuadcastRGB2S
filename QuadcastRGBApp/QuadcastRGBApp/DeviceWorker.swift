import Foundation

/// All transport calls, including close, belong to one serial queue.
protocol DeviceTransport: AnyObject, Sendable {
    var permissionGranted: Bool { get }
    func open() -> Bool
    func send(_ frame: AnimationFrame) -> Bool
    func isConnected() -> Bool
    func close()
}

enum DeviceStatus: Equatable, Sendable {
    case disconnected, connected, needsPermission
}

final class DeviceWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mscno.quadcast.device", qos: .utility)
    private let transport: any DeviceTransport
    private let generator: FrameGenerator
    private let statusChanged: @Sendable (DeviceStatus) -> Void
    // Access only on queue. Generation invalidates pending work after reconnect.
    private var generation = 0
    private var running = false
    private var opened = false
    private var lastStatus: DeviceStatus?
    private var lastFrame: AnimationFrame?
    private var lastProbe = ProcessInfo.processInfo.systemUptime

    init(transport: any DeviceTransport, generator: FrameGenerator,
         statusChanged: @escaping @Sendable (DeviceStatus) -> Void) {
        self.transport = transport
        self.generator = generator
        self.statusChanged = statusChanged
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            generation += 1
            step(generation)
        }
    }

    /// Wait for in-flight USB I/O before freeing its handle.
    func stop() {
        queue.sync {
            running = false
            generation += 1
            disconnect()
            report(.disconnected)
        }
    }

    private func report(_ status: DeviceStatus) {
        guard lastStatus != status else { return }
        lastStatus = status
        statusChanged(status)
    }

    private func disconnect() {
        if opened { transport.close() }
        opened = false
        lastFrame = nil
    }

    private func step(_ token: Int) {
        guard running, token == generation else { return }
        var nextDelay = 0.27 // Preserve the six groups' 45 ms frame cadence.
        if !opened {
            if !transport.permissionGranted {
                report(.needsPermission)
                nextDelay = 3
            } else if transport.open() {
                opened = true
                lastProbe = ProcessInfo.processInfo.systemUptime
                report(.connected)
                nextDelay = 0
            } else {
                report(.disconnected)
                nextDelay = 2
            }
        } else {
            let frame = generator.nextFrame()
            let now = ProcessInfo.processInfo.systemUptime
            var succeeded = true
            if frame != lastFrame {
                let started = now
                succeeded = transport.send(frame)
                if succeeded { lastFrame = frame }
                lastProbe = now
                // HID already sleeps between groups; don't double that delay.
                nextDelay = max(0, 0.27 - (ProcessInfo.processInfo.systemUptime - started))
            } else if now - lastProbe >= 2 {
                succeeded = transport.isConnected()
                lastProbe = now
            }
            if !succeeded {
                disconnect()
                report(.disconnected)
                nextDelay = 2
            }
        }
        queue.asyncAfter(deadline: .now() + nextDelay) { [weak self] in
            self?.step(token)
        }
    }
}
