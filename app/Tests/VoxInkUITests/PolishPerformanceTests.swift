import Foundation
import Testing
@testable import VoxInkUI

struct PolishPerformanceTests {
    @Test func recommendationsRespectHardwareAndPreference() {
        #expect(PolishPerformancePolicy.recommended(device: .init(memoryGB: 8), preference: .quality) == .light)
        #expect(PolishPerformancePolicy.recommended(device: .init(memoryGB: 16), preference: .balanced) == .balanced)
        #expect(PolishPerformancePolicy.recommended(device: .init(memoryGB: 32), preference: .quality) == .medium)
        #expect(PolishPerformancePolicy.recommended(device: .init(memoryGB: 64, cores: 12), preference: .quality) == .quality)
        #expect(PolishPerformancePolicy.recommended(device: .init(memoryGB: 64, cores: 4), preference: .quality) == .light)
        #expect(PolishPerformancePolicy.recommended(device: .init(memoryGB: 64, pressure: 1), preference: .quality) == .light)
    }

    @Test func automaticOnlyUsesInstalledModelsAndNeverUsesCloud() {
        let policy = PolishPerformancePolicy()
        #expect(policy.select(device: .init(memoryGB: 16), preference: .balanced, installed: [.quality]) == nil)
        #expect(policy.select(device: .init(memoryGB: 16), preference: .balanced, installed: [.light]) == .light)
        #expect(policy.select(device: .init(memoryGB: 64, pressure: 2), preference: .balanced, installed: [.light]) == nil)
        #expect(policy.select(device: .init(memoryGB: 16, appleSilicon: false), preference: .balanced, installed: [.light]) == nil)
    }

    @Test func downgradesOnlyAfterThreeSlowMeasurements() throws {
        var policy = PolishPerformancePolicy()
        let device = PolishDevice(memoryGB: 16)
        for _ in 0..<2 {
            policy.record(model: .balanced, characters: 40, generationSeconds: 10, timedOut: false, preference: .balanced)
        }
        #expect(policy.select(device: device, preference: .balanced, installed: [.light, .balanced]) == .balanced)
        policy.record(model: .balanced, characters: 40, generationSeconds: 10, timedOut: false, preference: .balanced)
        #expect(policy.select(device: device, preference: .balanced, installed: [.light, .balanced]) == .light)
        #expect(policy.select(device: device, preference: .balanced, installed: [.light, .balanced],
                              now: Date().addingTimeInterval(601)) == .balanced)
        let restored = try JSONDecoder().decode(PolishPerformancePolicy.self, from: JSONEncoder().encode(policy))
        #expect(restored.timings["balanced"]?.count == 3)
    }

    @Test func coldStartAndLongTextsDoNotCauseFalseDowngrade() {
        var policy = PolishPerformancePolicy()
        policy.record(model: .balanced, characters: 40, generationSeconds: nil, timedOut: false, preference: .balanced)
        #expect(policy.timings.isEmpty)
        for _ in 0..<3 {
            policy.record(model: .balanced, characters: 800, generationSeconds: 10, timedOut: false, preference: .balanced)
        }
        #expect(policy.select(device: .init(memoryGB: 16), preference: .balanced, installed: [.light, .balanced]) == .balanced)
        #expect(!PolishPerformancePolicy.canDownload(.quality, device: .init(memoryGB: 64, freeDiskGB: 9)))
    }

    @Test func repeatedLongTextTimeoutsStillDowngrade() {
        var policy = PolishPerformancePolicy()
        for _ in 0..<3 {
            policy.record(model: .balanced, characters: 800, generationSeconds: nil, timedOut: true, preference: .balanced)
        }
        #expect(policy.select(device: .init(memoryGB: 16), preference: .balanced, installed: [.light, .balanced]) == .light)
    }
}
