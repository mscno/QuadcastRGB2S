import Foundation
import Combine
import AVFoundation
import AudioToolbox
import AppKit

@MainActor
final class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioManager()
    @Published private(set) var state = AudioControlState()
    @Published private(set) var hardwareMuted: Bool?
    @Published private(set) var level = AudioLevel()
    @Published private(set) var metering = false
    @Published private(set) var recording = false
    @Published private(set) var playing = false
    @Published private(set) var clipDuration: Double = 0
    @Published private(set) var permissionDenied = false
    @Published var error: String?
    private let queue = DispatchQueue(label: "com.mscno.QuadcastRGBApp.audio-controls", qos: .utility)
    private let transport: any AudioControlTransport
    private var poll: DispatchSourceTimer?
    private var meterTimer: Timer?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayer?
    private let samples = AudioSamples()
    private var permissionGeneration = 0
    private var hardwareEvents: MicrophoneEvents?
    private var hardwareGeneration = 0
    private let preview: Bool

    init(transport: any AudioControlTransport = CoreAudioControls(), preview: Bool = ProcessInfo.processInfo.arguments.contains("--ui-testing")) {
        self.transport = transport; self.preview = preview
        super.init()
        if preview {
            state = AudioControlState(inputID: 1, outputID: 2, micVolume: 0.65, micMuted: false,
                                      headphoneVolume: 0.4, monitorVolume: 0.5, pattern: .cardioid,
                                      availablePatterns: PolarPattern.allCases)
            hardwareMuted = false
            if ProcessInfo.processInfo.arguments.contains("--ui-audio-unavailable") {
                state.headphoneVolume = nil; state.monitorVolume = nil
                state.pattern = nil; state.availablePatterns = []; hardwareMuted = nil
            }
        } else {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500), leeway: .milliseconds(100))
            timer.setEventHandler { [weak self, transport] in
                let next = transport.read()
                Task { @MainActor [weak self] in self?.apply(next) }
            }
            poll = timer; timer.resume()
        }
    }

    private func apply(_ next: AudioControlState) {
        if next.inputID != state.inputID || next.serial != state.serial {
            stopCapture(discard: true)
            hardwareGeneration += 1
            hardwareEvents?.stop(); hardwareEvents = nil; hardwareMuted = nil
            if let serial = next.serial {
                let generation = hardwareGeneration
                hardwareEvents = MicrophoneEvents(serial: serial) { [weak self] muted in
                    Task { @MainActor [weak self] in
                        guard let self, self.hardwareGeneration == generation else { return }
                        self.hardwareMuted = muted
                    }
                }
                hardwareEvents?.start()
            }
        }
        if next != state { state = next }
    }
    func set(_ control: AudioControl, value: Double) {
        guard value.isFinite else { return }
        if preview {
            switch control {
            case .micVolume: state.micVolume = Float(value)
            case .micMute: state.micMuted = value != 0
            case .headphoneVolume: state.headphoneVolume = Float(value)
            case .monitorVolume: state.monitorVolume = Float(value)
            case .pattern: break
            }
            return
        }
        queue.async { [weak self, transport] in
            var message: String?
            do { try transport.set(control, value: Float(value)) } catch { message = error.localizedDescription }
            let next = transport.read()
            let failure = message
            Task { @MainActor [weak self] in self?.apply(next); self?.error = failure }
        }
    }
    func select(_ pattern: PolarPattern) {
        if preview { state.pattern = pattern; return }
        queue.async { [weak self, transport] in
            var message: String?
            do { try transport.select(pattern) } catch { message = error.localizedDescription }
            let next = transport.read(); let failure = message
            Task { @MainActor [weak self] in self?.apply(next); self?.error = failure }
        }
    }
    func toggleMeter() {
        if metering { stopCapture() } else { requestCapture(record: false) }
    }
    func toggleRecording() {
        if recording {
            if !preview { clipDuration = samples.snapshot().duration }
            samples.endRecording(); recording = false; stopCapture()
        }
        else { requestCapture(record: true) }
    }
    private func requestCapture(record: Bool) {
        guard let input = state.inputID else { error = "Connect a QuadCast 2 S to test the microphone."; return }
        if preview {
            metering = true; recording = record
            level = AudioLevel(rmsDB: -18, peakDB: -9)
            if record { clipDuration = 5 }
            return
        }
        permissionGeneration += 1; let token = permissionGeneration
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: startCapture(input: input, record: record)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.permissionGeneration == token, self.state.inputID == input else { return }
                    if granted { self.startCapture(input: input, record: record) } else { self.permissionDenied = true }
                }
            }
        default: permissionDenied = true
        }
    }
    private func startCapture(input: UInt32, record: Bool) {
        permissionDenied = false; error = nil; stopPlayback()
        do {
            if engine == nil {
                let newEngine = AVAudioEngine(); let node = newEngine.inputNode
                guard let unit = node.audioUnit else { throw AudioControlError(message: "Could not open the microphone.") }
                var device = input
                let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<UInt32>.size))
                guard status == noErr else { throw AudioControlError(message: "Could not select the QuadCast input (\(status)).") }
                let format = node.outputFormat(forBus: 0)
                guard format.channelCount > 0, (8000...192000).contains(format.sampleRate), format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
                    throw AudioControlError(message: "The microphone returned an unsupported audio format.")
                }
                let storage = samples
                node.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                    if let channels = buffer.floatChannelData {
                        storage.ingest(channels, frames: Int(buffer.frameLength), channels: Int(buffer.format.channelCount))
                    }
                }
                // Keep ownership before starting so a failed start removes the tap.
                engine = newEngine
                try newEngine.start(); metering = true
                meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.updateMeter() }
                }
            }
            if record, let format = engine?.inputNode.outputFormat(forBus: 0) {
                samples.beginRecording(sampleRate: format.sampleRate, channels: Int(format.channelCount))
                recording = true; clipDuration = 0
            }
        } catch { stopCapture(); self.error = error.localizedDescription }
    }
    private func updateMeter() {
        let snapshot = samples.snapshot()
        level = snapshot.level
        if recording {
            clipDuration = snapshot.duration
            if !snapshot.recording { recording = false; stopCapture() }
        }
    }
    func stopCapture(discard: Bool = false) {
        permissionGeneration += 1
        meterTimer?.invalidate(); meterTimer = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        samples.endRecording(); samples.resetLevel()
        recording = false; metering = false; level = AudioLevel()
        stopPlayback()
        if discard { samples.discard(); clipDuration = 0 }
    }
    func playTest() {
        if playing { stopPlayback(); return }
        if preview { playing = true; return }
        stopCapture()
        guard let data = samples.waveData() else { return }
        do {
            // Playback uses the Mac's selected output. Capture is stopped first.
            let next = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            next.delegate = self; player = next
            guard next.play() else { throw AudioControlError(message: "Could not play the microphone test.") }
            playing = true
        } catch { self.error = error.localizedDescription; stopPlayback() }
    }
    func discardTest() { stopCapture(discard: true) }
    private func stopPlayback() { player?.stop(); player = nil; playing = false }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { stopPlayback() }
    func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
    func shutdown() { poll?.cancel(); poll = nil; hardwareEvents?.stop(); hardwareEvents = nil; stopCapture(discard: true) }
}
