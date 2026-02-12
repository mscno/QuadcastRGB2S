import SwiftUI

struct RGB: Equatable, Codable, Hashable {
    var r: UInt8, g: UInt8, b: UInt8

    static let black = RGB(r: 0, g: 0, b: 0)

    var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    func scaled(brightness: Int) -> RGB {
        RGB(
            r: UInt8(Int(r) * brightness / 100),
            g: UInt8(Int(g) * brightness / 100),
            b: UInt8(Int(b) * brightness / 100)
        )
    }

    var hexString: String {
        String(format: "%02X%02X%02X", r, g, b)
    }

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        guard hex.count == 6, let val = UInt32(hex, radix: 16) else { return nil }
        self.r = UInt8((val >> 16) & 0xFF)
        self.g = UInt8((val >> 8) & 0xFF)
        self.b = UInt8(val & 0xFF)
    }
}

struct AnimationFrame {
    let upper: RGB
    let lower: RGB
}

enum LightingMode: String, CaseIterable, Codable {
    case solid, blink, cycle, wave, lightning, pulse

    var label: String { rawValue.capitalized }
    var hasSpeed: Bool { self != .solid }
    var hasDelay: Bool { self == .blink }
}
