import VoxInkCore
import Darwin
import Foundation

public enum PolishPreference: String, CaseIterable, Sendable {
    case responsive, balanced, quality
    public var title: String {
        switch self { case .responsive: L("响应更快"); case .balanced: L("兼顾速度与效果"); case .quality: L("效果优先") }
    }
    var waitSeconds: Double {
        switch self { case .responsive: 6; case .balanced: 12; case .quality: 30 }
    }
    var targetSeconds: Double { waitSeconds / 2 }
}

public struct PolishDevice: Sendable {
    public var memoryGB: Int
    public var cores: Int
    public var appleSilicon: Bool
    public var freeDiskGB: Double
    public var pressure: Int // 0 normal, 1 warning, 2 critical
    public var thermalPressure: Bool

    public init(memoryGB: Int, cores: Int = 8, appleSilicon: Bool = true, freeDiskGB: Double = 100,
                pressure: Int = 0, thermalPressure: Bool = false) {
        self.memoryGB = memoryGB; self.cores = cores; self.appleSilicon = appleSilicon
        self.freeDiskGB = freeDiskGB; self.pressure = pressure; self.thermalPressure = thermalPressure
    }

    public static func current() -> Self {
        var arm: Int32 = 0
        var size = MemoryLayout.size(ofValue: arm)
        sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0)
        let info = ProcessInfo.processInfo
        let disk = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber
        return .init(memoryGB: Int(info.physicalMemory / 1_073_741_824), cores: info.processorCount,
                     appleSilicon: arm == 1, freeDiskGB: (disk?.doubleValue ?? 0) / 1_000_000_000,
                     thermalPressure: info.thermalState == .serious || info.thermalState == .critical)
    }
    var signature: String { "v1-\(appleSilicon)-\(memoryGB)-\(cores)" }
    var summary: String { L("\(appleSilicon ? "Apple Silicon" : "Intel") · \(memoryGB) GB 内存 · \(cores) 核") }
}

struct PolishTiming: Codable, Sendable {
    var count = 0
    var normalizedSeconds: Double = 0
    var slowStreak = 0
    var lastMeasuredAt: Date?
}

struct PolishPerformancePolicy: Codable, Sendable {
    var timings: [String: PolishTiming] = [:]

    static func recommended(device: PolishDevice, preference: PolishPreference) -> PolishModel {
        guard device.appleSilicon, device.memoryGB >= 12, device.cores > 4,
              device.pressure == 0, !device.thermalPressure else { return .light }
        if preference == .responsive { return .light }
        if preference == .quality, device.memoryGB >= 48, device.cores >= 10 { return .quality }
        if preference == .quality, device.memoryGB >= 24, device.cores >= 8 { return .medium }
        return .balanced
    }

    func select(device: PolishDevice, preference: PolishPreference, installed: Set<PolishModel>, now: Date = Date()) -> PolishModel? {
        guard device.appleSilicon, device.pressure < 2 else { return nil }
        let ceiling = Self.recommended(device: device, preference: preference).rank
        let candidates = PolishModel.allCases.filter { $0.rank <= ceiling && installed.contains($0) }
        return candidates.reversed().first { model in
            guard let sample = timings[model.rawValue], sample.count >= 3,
                  let measured = sample.lastMeasuredAt, now.timeIntervalSince(measured) < 600 else { return true }
            return sample.slowStreak < 3 || sample.normalizedSeconds <= preference.targetSeconds
        } ?? candidates.first
    }

    mutating func record(model: PolishModel, characters: Int, generationSeconds: Double?, timedOut: Bool,
                         preference: PolishPreference, now: Date = Date()) {
        guard characters > 0, timedOut || (generationSeconds?.isFinite == true && generationSeconds! >= 0) else { return }
        var sample = timings[model.rawValue] ?? .init()
        if let measured = sample.lastMeasuredAt, now.timeIntervalSince(measured) >= 600 { sample = .init() }
        let seconds = timedOut ? preference.waitSeconds : generationSeconds!
        let normalized = timedOut ? seconds : seconds / max(1, Double(characters) / 80)
        sample.count += 1
        sample.normalizedSeconds = sample.count == 1 ? normalized : sample.normalizedSeconds * 0.6 + normalized * 0.4
        sample.slowStreak = normalized > preference.targetSeconds ? sample.slowStreak + 1 : 0
        sample.lastMeasuredAt = now
        timings[model.rawValue] = sample
    }

    static func canDownload(_ model: PolishModel, device: PolishDevice) -> Bool {
        device.appleSilicon && device.freeDiskGB >= model.downloadGB + 2
    }
}

extension PolishModel {
    var rank: Int { Self.allCases.firstIndex(of: self)! }
    var downloadGB: Double {
        switch self { case .light: 1; case .balanced: 2.3; case .medium: 4.6; case .quality: 8.3 }
    }
}
