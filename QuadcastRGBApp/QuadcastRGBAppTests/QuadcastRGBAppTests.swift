import XCTest
#if SWIFT_PACKAGE
@testable import QuadcastCore
#else
@testable import QuadcastRGBApp
#endif

final class AnimationTests: XCTestCase {
    private let red = RGB(r: 255, g: 0, b: 0)
    private let blue = RGB(r: 0, g: 0, b: 255)

    func testRGBParsingAndBrightnessBounds() {
        XCTAssertEqual(RGB(hex: "FF0080"), RGB(r: 255, g: 0, b: 128))
        XCTAssertNil(RGB(hex: "nope00"))
        XCTAssertNil(RGB(hex: "FFFFFFF"))
        XCTAssertEqual(red.scaled(brightness: -1), .black)
        XCTAssertEqual(red.scaled(brightness: 200), red)
        XCTAssertEqual(red.scaled(brightness: 50).r, 127)
    }

    func testSolidUsesFirstColorAndRepeats() {
        let generator = FrameGenerator(mode: .solid, colors: [red, blue], speed: 50, delay: 0, brightness: 50)
        let expected = AnimationFrame(upper: red.scaled(brightness: 50), lower: red.scaled(brightness: 50))
        for _ in 0..<10 { XCTAssertEqual(generator.nextFrame(), expected) }
    }

    func testBlinkTimingAndLoop() {
        let generator = FrameGenerator(mode: .blink, colors: [red, blue], speed: 100, delay: 1, brightness: 100)
        let expected = [red, RGB.black, blue, RGB.black, red]
        for color in expected {
            XCTAssertEqual(generator.nextFrame(), AnimationFrame(upper: color, lower: color))
        }
    }

    func testCycleIncludesEndpointsAndWraps() {
        let generator = FrameGenerator(mode: .cycle, colors: [red, blue], speed: 100, delay: 0, brightness: 100)
        let frames = (0..<24).map { _ in generator.nextFrame() }
        XCTAssertEqual(frames[0].upper, red)
        XCTAssertEqual(frames[11].upper, blue)
        XCTAssertEqual(frames[12].upper, blue)
        XCTAssertEqual(frames[23].upper, red)
        XCTAssertEqual(generator.nextFrame(), frames[0])
    }

    func testWaveHasOppositeZoneEndpoints() {
        let generator = FrameGenerator(mode: .wave, colors: [red, blue], speed: 100, delay: 0, brightness: 100)
        let frames = (0..<24).map { _ in generator.nextFrame() }
        XCTAssertEqual(frames[0], AnimationFrame(upper: red, lower: blue))
        XCTAssertEqual(frames[11], AnimationFrame(upper: blue, lower: red))
        XCTAssertEqual(frames[12], AnimationFrame(upper: blue, lower: red))
        XCTAssertEqual(generator.nextFrame(), frames[0])
    }

    func testEmptyPalettesAndCorruptSettingsNeverCrash() {
        for mode in LightingMode.allCases {
            let empty = FrameGenerator(mode: mode, colors: [], speed: -1000, delay: -5, brightness: 1000)
            XCTAssertEqual(empty.nextFrame(), AnimationFrame(upper: .black, lower: .black))
            let corrupt = FrameGenerator(mode: mode, colors: [red], speed: 1000, delay: -5, brightness: -1000)
            for _ in 0..<200 { XCTAssertEqual(corrupt.nextFrame().upper, .black) }
        }
    }

    func testPulseSynchronizesZonesAndLightningOffsetsThem() {
        let pulse = FrameGenerator(mode: .pulse, colors: [red], speed: 100, delay: 0, brightness: 100)
        for _ in 0..<50 {
            let frame = pulse.nextFrame()
            XCTAssertEqual(frame.upper, frame.lower)
        }
        let lightning = FrameGenerator(mode: .lightning, colors: [red], speed: 100, delay: 0, brightness: 100)
        _ = lightning.nextFrame()
        let frame = lightning.nextFrame()
        XCTAssertNotEqual(frame.upper, frame.lower)
    }

    func testConcurrentRegenerationAndConsumption() {
        let generator = FrameGenerator(mode: .wave, colors: [red, blue], speed: 50, delay: 0, brightness: 100)
        DispatchQueue.concurrentPerform(iterations: 500) { index in
            if index.isMultiple(of: 3) {
                generator.regenerate(mode: .wave, colors: [RGB(r: 255, g: 0, b: 0)], speed: index, delay: 0, brightness: 100)
            } else { _ = generator.nextFrame() }
        }
        XCTAssertEqual(generator.nextFrame().upper, red)
    }
}

private final class MockTransport: DeviceTransport, @unchecked Sendable {
    // Callback state is installed before starting the worker; calls are serialized.
    var permissionGranted = true
    var opensSuccessfully = true
    var sendsSuccessfully = true
    var onSend: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpen: (() -> Void)?
    func open() -> Bool { onOpen?(); return opensSuccessfully }
    func send(_ frame: AnimationFrame) -> Bool { onSend?(); return sendsSuccessfully }
    func isConnected() -> Bool { true }
    func close() { onClose?() }
}

final class DeviceWorkerTests: XCTestCase {
    private func generator() -> FrameGenerator {
        FrameGenerator(mode: .solid, colors: [RGB(r: 255, g: 0, b: 0)], speed: 50, delay: 0, brightness: 100)
    }

    func testStopWaitsForInFlightSendBeforeClosing() {
        let transport = MockTransport()
        let sending = expectation(description: "send entered")
        let closed = expectation(description: "closed after send returned")
        let returned = expectation(description: "stop returned")
        let releaseSend = DispatchSemaphore(value: 0)
        let sendFinished = DispatchSemaphore(value: 0)
        transport.onSend = {
            sending.fulfill()
            _ = releaseSend.wait(timeout: .now() + 5)
            sendFinished.signal()
        }
        transport.onClose = {
            XCTAssertEqual(sendFinished.wait(timeout: .now()), .success)
            closed.fulfill()
        }
        let worker = DeviceWorker(transport: transport, generator: generator()) { _ in }
        worker.start()
        wait(for: [sending], timeout: 2)
        DispatchQueue.global().async { worker.stop(); returned.fulfill() }
        // Stop cannot close the transport while send is blocked.
        releaseSend.signal()
        wait(for: [closed, returned], timeout: 2, enforceOrder: true)
    }

    func testSteadyColorDoesNotContinuouslyWriteUSBFrames() {
        let transport = MockTransport()
        let sent = expectation(description: "initial frame")
        let duplicate = expectation(description: "duplicate frame")
        duplicate.isInverted = true
        var count = 0
        transport.onSend = {
            count += 1
            if count == 1 { sent.fulfill() } else { duplicate.fulfill() }
        }
        let worker = DeviceWorker(transport: transport, generator: generator()) { _ in }
        worker.start()
        wait(for: [sent], timeout: 2)
        wait(for: [duplicate], timeout: 0.6)
        worker.stop()
    }

    func testPermissionDenialDoesNotOpenDevice() {
        let transport = MockTransport()
        transport.permissionGranted = false
        let permission = expectation(description: "permission state")
        let open = expectation(description: "no open without permission")
        open.isInverted = true
        transport.onOpen = { open.fulfill() }
        let worker = DeviceWorker(transport: transport, generator: generator()) { status in
            if status == .needsPermission { permission.fulfill() }
        }
        worker.start()
        wait(for: [permission], timeout: 2)
        worker.stop()
        wait(for: [open], timeout: 0.05)
    }

    func testFailedSendClosesAndReportsDisconnect() {
        let transport = MockTransport()
        transport.sendsSuccessfully = false
        let closed = expectation(description: "failed handle closed")
        let disconnected = expectation(description: "disconnect")
        transport.onClose = { closed.fulfill() }
        let worker = DeviceWorker(transport: transport, generator: generator()) { status in
            if status == .disconnected { disconnected.fulfill() }
        }
        worker.start()
        wait(for: [closed, disconnected], timeout: 2, enforceOrder: true)
        worker.stop()
    }

    func testRestartClosesOldHandleAndSendsNewSessionFrame() {
        let transport = MockTransport()
        let first = expectation(description: "first session")
        let second = expectation(description: "second session")
        var sends = 0
        var closes = 0
        transport.onSend = {
            sends += 1
            if sends == 1 { first.fulfill() } else { second.fulfill() }
        }
        transport.onClose = { closes += 1 }
        let worker = DeviceWorker(transport: transport, generator: generator()) { _ in }
        worker.start()
        wait(for: [first], timeout: 2)
        worker.stop()
        worker.start()
        wait(for: [second], timeout: 2)
        worker.stop()
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(closes, 2)
    }
}
