import Foundation
import CoreAudio

// Audio state belongs to the device, not UserDefaults. Optional values mean the
// device/driver did not expose that control; never substitute a saved guess.
struct AudioControlState: Equatable, Sendable {
    var serial: String?
    var inputID: UInt32?
    var outputID: UInt32?
    var micVolume: Float?
    var micMuted: Bool?
    var headphoneVolume: Float?
    var monitorVolume: Float?
    var pattern: PolarPattern?
    var availablePatterns: [PolarPattern] = []
    var connected: Bool { inputID != nil }
}

enum PolarPattern: String, CaseIterable, Sendable {
    case cardioid, omnidirectional, bidirectional, stereo
    var label: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .cardioid: "Picks up sound in front. Best for calls, streaming and solo vocals."
        case .omnidirectional: "Picks up sound from all sides. Good for a group around the microphone."
        case .bidirectional: "Picks up the front and back. Good for a face-to-face interview."
        case .stereo: "Captures left and right. Good for instruments and spatial recordings."
        }
    }
    var icon: String {
        switch self {
        case .cardioid: "person.fill"
        case .omnidirectional: "person.3.fill"
        case .bidirectional: "person.2.fill"
        case .stereo: "hifispeaker.2.fill"
        }
    }
    static func named(_ name: String) -> Self? {
        let normalized = name.lowercased().filter(\.isLetter)
        return allCases.first { normalized == $0.rawValue || normalized == $0.rawValue + "pattern" }
    }
}

enum AudioControl: Sendable { case micVolume, micMute, headphoneVolume, monitorVolume, pattern }

protocol AudioControlTransport: AnyObject, Sendable {
    func read() -> AudioControlState
    func set(_ control: AudioControl, value: Float) throws
    func select(_ pattern: PolarPattern) throws
}

struct AudioControlError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Called exclusively on the manager's serial queue, including writes/readback.
final class CoreAudioControls: AudioControlTransport, @unchecked Sendable {
    private struct Endpoint { let id: AudioObjectID; let addresses: [AudioObjectPropertyAddress] }
    private var endpoints: [String: Endpoint] = [:]
    private var patternIDs: [PolarPattern: UInt32] = [:]
    private var patternEndpoint: Endpoint?

    func read() -> AudioControlState {
        endpoints.removeAll(); patternIDs.removeAll(); patternEndpoint = nil
        let devices: [UInt32] = array(UInt32(kAudioObjectSystemObject), address(kAudioHardwarePropertyDevices))
        let matches = devices.filter {
            let name = string($0, kAudioObjectPropertyName).lowercased().filter(\.isLetter)
            let uid = string($0, kAudioDevicePropertyDeviceUID)
            return name == "hyperxquadcasts" && uid.contains("AppleUSBAudioEngine:HP, Inc:HyperX QuadCast 2 S:")
        }
        var state = AudioControlState()
        state.inputID = matches.first { channels($0, kAudioDevicePropertyScopeInput) > 0 }
        // Match the input's serial/UID prefix, rather than pairing two different microphones.
        if let input = state.inputID {
            let uid = string(input, kAudioDevicePropertyDeviceUID)
            state.serial = uid.split(separator: ":").dropLast().last.map(String.init)
            let prefix = uid.split(separator: ":").dropLast().joined(separator: ":") + ":"
            state.outputID = matches.first {
                string($0, kAudioDevicePropertyDeviceUID).hasPrefix(prefix) &&
                (channels($0, kAudioDevicePropertyScopeOutput) > 0 || writable($0, address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)))
            }
            state.micVolume = scalar(input, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput, key: "mic")
            state.micMuted = boolean(input, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, key: "mute")
            state.monitorVolume = scalar(input, kAudioDevicePropertyPlayThruVolumeScalar, kAudioDevicePropertyScopePlayThrough, key: "monitor")
            let sourceAddress = address(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeInput)
            let sourceIDs: [UInt32] = array(input, address(kAudioDevicePropertyDataSources, kAudioDevicePropertyScopeInput))
            for id in sourceIDs {
                if let pattern = PolarPattern.named(sourceName(input, id)) { patternIDs[pattern] = id }
            }
            // A generic source selector is not necessarily a polar pattern selector.
            if patternIDs.count == PolarPattern.allCases.count && writable(input, sourceAddress) {
                patternEndpoint = Endpoint(id: input, addresses: [sourceAddress])
                state.availablePatterns = PolarPattern.allCases
                let current: [UInt32] = array(input, sourceAddress)
                state.pattern = patternIDs.first { $0.value == current.first }?.key
            }
        }
        if let output = state.outputID {
            state.headphoneVolume = scalar(output, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, key: "headphones")
        }
        return state
    }

    func set(_ control: AudioControl, value: Float) throws {
        // Refresh capabilities/IDs after hotplug, before every write.
        _ = read()
        let key: String
        switch control {
        case .micVolume: key = "mic"
        case .micMute: key = "mute"
        case .headphoneVolume: key = "headphones"
        case .monitorVolume: key = "monitor"
        case .pattern: throw AudioControlError(message: "Use the pattern selector.")
        }
        guard value.isFinite, let endpoint = endpoints[key] else {
            throw AudioControlError(message: "This control is not available from the microphone.")
        }
        for var a in endpoint.addresses {
            let result: OSStatus
            if control == .micMute {
                var mute: UInt32 = value > 0 ? 1 : 0
                result = AudioObjectSetPropertyData(endpoint.id, &a, 0, nil, 4, &mute)
            } else {
                var scalar = min(1, max(0, value))
                result = AudioObjectSetPropertyData(endpoint.id, &a, 0, nil, 4, &scalar)
            }
            guard result == noErr else { throw AudioControlError(message: "The microphone rejected the change (\(result)).") }
        }
    }

    func select(_ pattern: PolarPattern) throws {
        _ = read()
        guard let endpoint = patternEndpoint, var id = patternIDs[pattern] else {
            throw AudioControlError(message: "Select the polar pattern using the microphone’s knob.")
        }
        var a = endpoint.addresses[0]
        let result = AudioObjectSetPropertyData(endpoint.id, &a, 0, nil, 4, &id)
        guard result == noErr else { throw AudioControlError(message: "The microphone rejected the pattern (\(result)).") }
    }

    private func scalar(_ id: UInt32, _ selector: UInt32, _ scope: UInt32, key: String) -> Float? {
        let elements: [UInt32] = writable(id, address(selector, scope)) ? [0] : Array(1...max(1, channels(id, scope)))
        let addresses = elements.map { address(selector, scope, $0) }.filter { writable(id, $0) }
        let values: [Float] = addresses.compactMap { value(id, $0, initial: Float(0)) }.filter { $0.isFinite && (0...1).contains($0) }
        guard !values.isEmpty, values.count == addresses.count else { return nil }
        endpoints[key] = Endpoint(id: id, addresses: addresses)
        return values.reduce(0, +) / Float(values.count)
    }
    private func boolean(_ id: UInt32, _ selector: UInt32, _ scope: UInt32, key: String) -> Bool? {
        let a = address(selector, scope)
        guard writable(id, a), let raw = value(id, a, initial: UInt32(0)) else { return nil }
        endpoints[key] = Endpoint(id: id, addresses: [a]); return raw != 0
    }
    private func address(_ selector: UInt32, _ scope: UInt32 = kAudioObjectPropertyScopeGlobal, _ element: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    private func writable(_ id: UInt32, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address; var result: DarwinBoolean = false
        return AudioObjectHasProperty(id, &a) && AudioObjectIsPropertySettable(id, &a, &result) == noErr && result.boolValue
    }
    private func value<T>(_ id: UInt32, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var a = address; var result = initial; var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return status == noErr && size == MemoryLayout<T>.size ? result : nil
    }
    private func array(_ id: UInt32, _ address: AudioObjectPropertyAddress) -> [UInt32] {
        var a = address; var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0, size % 4 == 0 else { return [] }
        var result = [UInt32](repeating: 0, count: Int(size / 4))
        let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? Array(result.prefix(Int(size / 4))) : []
    }
    private func string(_ id: UInt32, _ selector: UInt32) -> String {
        guard let ref: Unmanaged<CFString> = value(id, address(selector), initial: Optional<Unmanaged<CFString>>.none) ?? nil else { return "" }
        return ref.takeRetainedValue() as String
    }
    private func sourceName(_ device: UInt32, _ id: UInt32) -> String {
        var id = id; var name: Unmanaged<CFString>?
        var a = address(kAudioDevicePropertyDataSourceNameForIDCFString, kAudioDevicePropertyScopeInput)
        let status = withUnsafeMutablePointer(to: &id) { input in
            withUnsafeMutablePointer(to: &name) { output in
                var translation = AudioValueTranslation(mInputData: input, mInputDataSize: 4, mOutputData: output, mOutputDataSize: UInt32(MemoryLayout<Unmanaged<CFString>?>.size))
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &translation)
            }
        }
        return status == noErr ? (name?.takeRetainedValue() as String? ?? "") : ""
    }
    private func channels(_ id: UInt32, _ scope: UInt32) -> UInt32 {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, storage) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + $1.mNumberChannels }
    }
}
