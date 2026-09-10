import Foundation
import VoxInkCore

@MainActor public protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    func requestPermission() async -> Bool
    func start() throws
    func stop() throws -> URL
    func sample() -> AudioCaptureSample
    func cancel()
}

extension AudioCapture: AudioRecording {}

public enum ShortcutMode: String, CaseIterable, Sendable {
    case holdToTalk
    case toggle

    public var title: String {
        switch self {
        case .holdToTalk: "按住说话，松开写入"
        case .toggle: "按一次开始，再按结束"
        }
    }
    public var instruction: String {
        switch self {
        case .holdToTalk: "按住 ⌥ Space 录音，松开后识别并写入；Esc 取消。"
        case .toggle: "按 ⌥ Space 录音，再按结束并写入；Esc 取消。"
        }
    }
}
