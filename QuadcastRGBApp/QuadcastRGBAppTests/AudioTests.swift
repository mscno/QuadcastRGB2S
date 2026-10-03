import XCTest
#if SWIFT_PACKAGE
@testable import QuadcastCore
#else
@testable import QuadcastRGBApp
#endif

final class AudioTests: XCTestCase {
    private func ingest(_ channels: [[Float]], into samples: AudioSamples) {
        let pointers = channels.map { values -> UnsafeMutablePointer<Float> in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: values.count)
            p.initialize(from: values, count: values.count); return p
        }
        defer { pointers.forEach { $0.deallocate() } }
        pointers.withUnsafeBufferPointer { samples.ingest($0.baseAddress!, frames: channels[0].count, channels: channels.count) }
    }
    func testMeterMeasuresBothChannelsWithoutPhaseCancellation() {
        let samples = AudioSamples()
        ingest([[0.5, -0.5], [-0.5, 0.5]], into: samples)
        XCTAssertEqual(samples.snapshot().level.rmsDB, -6.0206, accuracy: 0.001)
        XCTAssertEqual(samples.snapshot().level.peakDB, -6.0206, accuracy: 0.001)
        XCTAssertFalse(samples.snapshot().level.clipped)
    }
    func testSilenceInvalidSamplesAndClipping() {
        let samples = AudioSamples()
        ingest([[0, .nan, .infinity]], into: samples)
        XCTAssertEqual(samples.snapshot().level.rmsDB, -60)
        ingest([[0, 1, -1]], into: samples)
        XCTAssertTrue(samples.snapshot().level.clipped)
        XCTAssertEqual(samples.snapshot().level.peakDB, 0)
        samples.resetLevel(); XCTAssertEqual(samples.snapshot().level, AudioLevel())
    }
    func testStereoWaveHeaderAndSamplesPreserveChannels() throws {
        let samples = AudioSamples(); samples.beginRecording(sampleRate: 48000, channels: 2)
        ingest([[0.5, 0.25], [-0.5, -0.25]], into: samples)
        let data = try XCTUnwrap(samples.waveData())
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<16], encoding: .ascii), "WAVEfmt ")
        XCTAssertEqual(Array(data[22..<24]), [2, 0])
        XCTAssertEqual(Array(data[24..<28]), [0x80, 0xbb, 0, 0])
        XCTAssertEqual(Array(data[40..<44]), [8, 0, 0, 0])
        let values = stride(from: 44, to: data.count, by: 2).map { offset in
            Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
        }
        XCTAssertEqual(values, [16384, -16384, 8192, -8192])
    }
    func testRecordingEndsAfterFiveSecondsAndDoesNotGrow() throws {
        let samples = AudioSamples(); samples.beginRecording(sampleRate: 8000, channels: 1)
        let block = [Float](repeating: 0.25, count: 41000)
        ingest([block], into: samples)
        XCTAssertFalse(samples.snapshot().recording)
        XCTAssertEqual(samples.snapshot().duration, 5)
        XCTAssertEqual(try XCTUnwrap(samples.waveData()).count, 44 + 40000 * 2)
        ingest([block], into: samples)
        XCTAssertEqual(samples.snapshot().duration, 5)
        samples.discard(); XCTAssertNil(samples.waveData()); XCTAssertEqual(samples.snapshot().duration, 0)
    }
    func testCaptureDoesNotRecordUnlessExplicitlyRequested() {
        let samples = AudioSamples(); ingest([[0.5]], into: samples)
        XCTAssertNil(samples.waveData())
        samples.beginRecording(sampleRate: 48000, channels: 1)
        ingest([[0.25]], into: samples); samples.endRecording()
        ingest([[0.5]], into: samples)
        XCTAssertEqual(samples.snapshot().duration, 1.0 / 48000)
    }
    func testVendorMuteEventsAreAbsoluteAndRejectUnknownReports() {
        func decode(_ bytes: [UInt8]) -> Bool? { bytes.withUnsafeBufferPointer { MicrophoneEvent.mute($0) } }
        XCTAssertEqual(decode([0x77, 6, 1]), true)
        XCTAssertEqual(decode([0x77, 6, 0]), false)
        XCTAssertNil(decode([0x77, 6]))
        XCTAssertNil(decode([0x77, 6, 2]))
        XCTAssertNil(decode([0x77, 5, 1]))
        XCTAssertNil(decode([0x44, 6, 1]))
    }
    func testOnlyNamedPolarPatternsAreRecognized() {
        XCTAssertEqual(PolarPattern.named("Bi-directional"), .bidirectional)
        XCTAssertEqual(PolarPattern.named("Cardioid pattern"), .cardioid)
        XCTAssertNil(PolarPattern.named("Internal microphone"))
        XCTAssertNil(PolarPattern.named("Default"))
        XCTAssertEqual(PolarPattern.allCases.count, 4)
    }
}
