import Foundation
import IOKit.hid

struct MicrophoneEvent {
    // HyperX's absolute vendor mute event, not a toggle. Unknown/malformed
    // reports must not turn an unknown hardware state into 'unmuted'.
    static func mute(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard bytes.count >= 3, bytes[0] == 0x77, bytes[1] == 0x06, bytes[2] <= 1 else { return nil }
        return bytes[2] == 1
    }
}

// IOHID callbacks are scheduled on the main run loop. Uses the audio device's
// vendor input reports and never seizes it or sends undocumented commands.
final class MicrophoneEvents: @unchecked Sendable {
    private struct Registration { let device: IOHIDDevice; let buffer: UnsafeMutablePointer<UInt8> }
    private var manager: IOHIDManager?
    private var registrations: [UInt: Registration] = [:]
    private let serial: String
    private let receive: @Sendable (Bool?) -> Void
    init(serial: String, receive: @escaping @Sendable (Bool?) -> Void) { self.serial = serial; self.receive = receive }
    func start() {
        guard manager == nil else { return }
        let next = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerSetDeviceMatching(next, [kIOHIDVendorIDKey: 0x03f0, kIOHIDProductIDKey: 0x0d84, kIOHIDSerialNumberKey: serial] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(next, { context, result, _, device in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<MicrophoneEvents>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(next, { context, _, _, device in
            guard let context else { return }
            Unmanaged<MicrophoneEvents>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(next, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if IOHIDManagerOpen(next, 0) == kIOReturnSuccess { manager = next }
        else { IOHIDManagerUnscheduleFromRunLoop(next, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) }
    }
    private func attach(_ device: IOHIDDevice) {
        let key = UInt(CFHash(device))
        guard registrations[key] == nil, IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { return }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)
        registrations[key] = Registration(device: device, buffer: buffer)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, type, _, bytes, size in
            guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput, size > 0, size <= 64, let context else { return }
            if let muted = MicrophoneEvent.mute(UnsafeBufferPointer(start: bytes, count: size)) {
                Unmanaged<MicrophoneEvents>.fromOpaque(context).takeUnretainedValue().receive(muted)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    private func detach(_ device: IOHIDDevice) {
        guard let registration = registrations.removeValue(forKey: UInt(CFHash(device))) else { return }
        IOHIDDeviceRegisterInputReportCallback(device, registration.buffer, 64, nil, nil)
        IOHIDDeviceClose(device, 0); registration.buffer.deallocate(); receive(nil)
    }
    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        for registration in Array(registrations.values) { detach(registration.device) }
        IOHIDManagerClose(manager, 0); self.manager = nil
    }
}
