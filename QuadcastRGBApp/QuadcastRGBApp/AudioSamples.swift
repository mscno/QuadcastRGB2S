import Foundation

struct AudioLevel: Equatable, Sendable {
    var rmsDB: Float = -60
    var peakDB: Float = -60
    var clipped = false
    var fraction: Double { Double(max(0, min(1, (rmsDB + 60) / 60))) }
    static func decibels(_ amplitude: Float) -> Float {
        amplitude.isFinite && amplitude > 0 ? max(-60, 20 * log10(amplitude)) : -60
    }
}

// The tap writes on the audio thread; the UI only reads at 20 Hz. Five seconds
// maximum, held in memory, preserving stereo rather than summing it to mono.
final class AudioSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var remaining = 0
    private var sampleRate: Double = 48000
    private var channels = 2
    private var level = AudioLevel()
    private var recording = false

    func beginRecording(sampleRate: Double, channels: Int) {
        lock.lock(); defer { lock.unlock() }
        self.sampleRate = sampleRate.isFinite && (8000...192000).contains(sampleRate) ? sampleRate : 48000
        self.channels = max(1, min(2, channels))
        remaining = Int(self.sampleRate * 5) * self.channels
        samples = []; samples.reserveCapacity(remaining); recording = true
    }
    func ingest(_ pointers: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int, channels: Int) {
        guard frames > 0, channels > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        var highestRMS: Float = 0; var peak: Float = 0
        for channel in 0..<min(2, channels) {
            var squares: Float = 0
            for frame in 0..<frames {
                let raw = pointers[channel][frame]
                let value = raw.isFinite ? min(1, max(-1, raw)) : 0
                squares += value * value; peak = max(peak, abs(value))
            }
            highestRMS = max(highestRMS, sqrt(squares / Float(frames)))
        }
        level = AudioLevel(rmsDB: AudioLevel.decibels(highestRMS), peakDB: AudioLevel.decibels(peak), clipped: peak >= 0.999)
        if recording {
            let count = min(frames, remaining / self.channels)
            for frame in 0..<count {
                for channel in 0..<self.channels {
                    let value = pointers[min(channel, channels - 1)][frame]
                    samples.append(value.isFinite ? min(1, max(-1, value)) : 0)
                }
            }
            remaining -= count * self.channels
            if remaining == 0 { recording = false }
        }
    }
    func snapshot() -> (level: AudioLevel, recording: Bool, duration: Double) {
        lock.lock(); defer { lock.unlock() }
        return (level, recording, Double(samples.count) / Double(channels) / sampleRate)
    }
    func endRecording() { lock.lock(); recording = false; lock.unlock() }
    func resetLevel() { lock.lock(); level = AudioLevel(); lock.unlock() }
    func discard() { lock.lock(); samples.removeAll(keepingCapacity: false); recording = false; remaining = 0; level = AudioLevel(); lock.unlock() }
    func waveData() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        var data = Data(); data.reserveCapacity(44 + samples.count * 2)
        func text(_ string: String) { data.append(contentsOf: string.utf8) }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        text("RIFF"); u32(36 + bytes); text("WAVEfmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * UInt32(channels * 2)); u16(UInt16(channels * 2)); u16(16)
        text("data"); u32(bytes)
        for sample in samples { u16(UInt16(bitPattern: Int16((sample * 32767).rounded()))) }
        return data
    }
}
