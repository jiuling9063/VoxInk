import Foundation

struct RecordingPulse {
    struct Sample {
        let height: Double
        let intensity: Double
        var opacity: Double { 0.46 + 0.54 * min(1, intensity * 1.15) }
    }

    static func sample(index: Int, time: Double, level: Double, reduceMotion: Bool = false) -> Sample {
        let distance = min(1, abs(Double(index)) / 14)
        let volume = level.isFinite ? min(1, max(0, level)) : 0
        let clock = time.isFinite ? max(0, time) : 0
        let front = reduceMotion ? 0 : (clock * 0.48).truncatingRemainder(dividingBy: 1) * 2.2 - 0.4
        let edge = pow(max(0, 1 - distance * distance), 0.6)
        let main = exp(-pow((distance - front) / 0.115, 2) / 2)
        let trailing = 0.48 * exp(-pow((distance - (front - 0.32)) / 0.13, 2) / 2)
        let shape = min(1, main + trailing) * edge
        let energy = reduceMotion ? 0.25 : volume
        return Sample(height: 2.4 + energy * 31 * shape, intensity: sqrt(volume) * (reduceMotion ? edge : shape))
    }
}
