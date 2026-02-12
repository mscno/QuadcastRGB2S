import Foundation

final class FrameGenerator: @unchecked Sendable {
    private var frames: [AnimationFrame] = []
    private var index: Int = 0
    private let lock = NSLock()

    init(mode: LightingMode, colors: [RGB], speed: Int, delay: Int, brightness: Int) {
        regenerate(mode: mode, colors: colors, speed: speed, delay: delay, brightness: brightness)
    }

    func nextFrame() -> AnimationFrame {
        lock.lock()
        defer { lock.unlock() }
        guard !frames.isEmpty else { return AnimationFrame(upper: .black, lower: .black) }
        let frame = frames[index]
        index = (index + 1) % frames.count
        return frame
    }

    func regenerate(mode: LightingMode, colors: [RGB], speed: Int, delay: Int, brightness: Int) {
        let scaled = colors.map { $0.scaled(brightness: brightness) }
        let newFrames: [AnimationFrame]
        switch mode {
        case .solid:
            newFrames = generateSolid(colors: scaled)
        case .blink:
            newFrames = generateBlink(colors: scaled, speed: speed, delay: delay)
        case .cycle:
            newFrames = generateCycle(colors: scaled, speed: speed)
        case .wave:
            newFrames = generateWave(colors: scaled, speed: speed)
        case .lightning:
            newFrames = generateLightning(colors: scaled, speed: speed, synchronous: false)
        case .pulse:
            newFrames = generateLightning(colors: scaled, speed: speed, synchronous: true)
        }
        lock.lock()
        frames = newFrames.isEmpty ? [AnimationFrame(upper: .black, lower: .black)] : newFrames
        index = 0
        lock.unlock()
    }

    // MARK: - Solid

    private func generateSolid(colors: [RGB]) -> [AnimationFrame] {
        let c = colors.first ?? .black
        return [AnimationFrame(upper: c, lower: c)]
    }

    // MARK: - Blink

    private func generateBlink(colors: [RGB], speed: Int, delay: Int) -> [AnimationFrame] {
        guard !colors.isEmpty else { return [] }
        var frames: [AnimationFrame] = []
        let colorSegment = 101 - speed
        for c in colors {
            for _ in 0..<colorSegment {
                frames.append(AnimationFrame(upper: c, lower: c))
            }
            for _ in 0..<delay {
                frames.append(AnimationFrame(upper: .black, lower: .black))
            }
        }
        return frames
    }

    // MARK: - Cycle

    private func generateCycle(colors: [RGB], speed: Int) -> [AnimationFrame] {
        guard !colors.isEmpty else { return [] }
        let trLength = transitionLength(colorCount: colors.count, speed: speed)
        var frames: [AnimationFrame] = []
        for i in 0..<colors.count {
            let start = colors[i]
            let end = colors[(i + 1) % colors.count]
            let gradient = makeGradient(from: start, to: end, length: trLength)
            for c in gradient {
                frames.append(AnimationFrame(upper: c, lower: c))
            }
        }
        return frames
    }

    // MARK: - Wave

    private func generateWave(colors: [RGB], speed: Int) -> [AnimationFrame] {
        guard colors.count >= 2 else { return generateCycle(colors: colors, speed: speed) }
        let trLength = transitionLength(colorCount: colors.count, speed: speed)

        // Upper uses original order
        var upperFrames: [RGB] = []
        for i in 0..<colors.count {
            let start = colors[i]
            let end = colors[(i + 1) % colors.count]
            upperFrames.append(contentsOf: makeGradient(from: start, to: end, length: trLength))
        }

        // Lower uses shifted order (first color moved to end)
        var shifted = colors
        shifted.append(shifted.removeFirst())
        var lowerFrames: [RGB] = []
        for i in 0..<shifted.count {
            let start = shifted[i]
            let end = shifted[(i + 1) % shifted.count]
            lowerFrames.append(contentsOf: makeGradient(from: start, to: end, length: trLength))
        }

        let count = min(upperFrames.count, lowerFrames.count)
        return (0..<count).map { AnimationFrame(upper: upperFrames[$0], lower: lowerFrames[$0]) }
    }

    // MARK: - Lightning / Pulse

    private func generateLightning(colors: [RGB], speed: Int, synchronous: Bool) -> [AnimationFrame] {
        guard !colors.isEmpty else { return [] }
        let blankSize = speedRange(min: 1, max: 9, speed: speed)
        let upSize = speedRange(min: 3, max: 10, speed: speed)
        let downSize = speedRange(min: 21, max: 131, speed: speed)

        var upperFrames: [RGB] = []
        var lowerFrames: [RGB] = []

        for c in colors {
            // Lower: blank before flash (async lightning only)
            if !synchronous {
                for _ in 0..<blankSize { lowerFrames.append(.black) }
            }

            // Fade up: black -> color
            let fadeUp = makeGradient(from: .black, to: c, length: upSize)
            upperFrames.append(contentsOf: fadeUp)
            lowerFrames.append(contentsOf: fadeUp)

            // Fade down: next_gradient_color(color, black, downSize) -> black
            let fadeDownStart = nextGradientStep(from: c, to: .black, length: downSize)
            let fadeDown = makeGradient(from: fadeDownStart, to: .black, length: downSize)
            upperFrames.append(contentsOf: fadeDown)
            lowerFrames.append(contentsOf: fadeDown)

            // Upper (or both if synchronous): blank after flash
            if synchronous {
                for _ in 0..<blankSize {
                    upperFrames.append(.black)
                    lowerFrames.append(.black)
                }
            } else {
                for _ in 0..<blankSize { upperFrames.append(.black) }
            }
        }

        let count = max(upperFrames.count, lowerFrames.count)
        // Pad shorter array
        while upperFrames.count < count { upperFrames.append(upperFrames.last ?? .black) }
        while lowerFrames.count < count { lowerFrames.append(lowerFrames.last ?? .black) }

        return (0..<count).map { AnimationFrame(upper: upperFrames[$0], lower: lowerFrames[$0]) }
    }

    // MARK: - Helpers

    private func transitionLength(colorCount: Int, speed: Int) -> Int {
        // MIN_CYCL_TR=12, MAX_CYCL_TR=128
        let tr = 12 + (128 - 12) * (100 - speed) / 100
        if tr * colorCount > 720 { // MAX_COLPAIR_COUNT = 720
            return 12 + (720 / colorCount - 12) * (100 - speed) / 100
        }
        return tr
    }

    private func speedRange(min: Int, max: Int, speed: Int) -> Int {
        min + (max - min) * (100 - speed) / 100
    }

    private func makeGradient(from start: RGB, to end: RGB, length: Int) -> [RGB] {
        guard length > 1 else { return [start] }
        return (0..<length).map { i in
            RGB(
                r: UInt8(clamping: Int(start.r) + i * (Int(end.r) - Int(start.r)) / (length - 1)),
                g: UInt8(clamping: Int(start.g) + i * (Int(end.g) - Int(start.g)) / (length - 1)),
                b: UInt8(clamping: Int(start.b) + i * (Int(end.b) - Int(start.b)) / (length - 1))
            )
        }
    }

    private func nextGradientStep(from color: RGB, to endColor: RGB, length: Int) -> RGB {
        guard length > 1 else { return color }
        return RGB(
            r: UInt8(clamping: Int(color.r) + 1 * (Int(endColor.r) - Int(color.r)) / (length - 1)),
            g: UInt8(clamping: Int(color.g) + 1 * (Int(endColor.g) - Int(color.g)) / (length - 1)),
            b: UInt8(clamping: Int(color.b) + 1 * (Int(endColor.b) - Int(color.b)) / (length - 1))
        )
    }
}
