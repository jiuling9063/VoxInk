import AVFoundation
import Foundation

public enum MicrophoneAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted

    public static func current() -> Self {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    public var title: String {
        switch self {
        case .notDetermined: "等待允许"
        case .authorized: "已允许"
        case .denied: "尚未允许"
        case .restricted: "系统已限制"
        }
    }
}

public enum ModelState: Equatable, Sendable {
    case notLoaded, loading, ready, failed, needsDownload

    public var title: String {
        switch self {
        case .notLoaded: "尚未加载"
        case .loading: "正在加载"
        case .ready: "本地模型已就绪"
        case .failed: "加载失败"
        case .needsDownload: "需要安装或修复"
        }
    }
}

public enum RecoveryAction: Equatable, Sendable {
    case microphone, reloadModel, recordAgain, chooseAudio, checkTarget, pastePermission, inspectClipboard, installModel, checkInstallation

    public var guidance: String {
        switch self {
        case .microphone: "在系统设置的「隐私与安全」中允许麦克风，然后重新录音。"
        case .reloadModel: "重新加载本地模型后再试。已有识别文字会保留。"
        case .installModel: "首次下载约 713 MB，完成后可离线使用。中断后可继续，校验通过才会加载。"
        case .checkInstallation: "请检查 App 安装文件或模型目录，处理后再加载模型。当前文件不会用于识别。"
        case .recordAgain: "检查输入设备后重新录音。已有识别文字会保留。"
        case .chooseAudio: "请选择不超过 60 秒、可正常播放的音频文件。"
        case .checkTarget: "确认目标输入框可编辑。文字已保留，可复制，或确认目标后重新粘贴。"
        case .pastePermission: "允许辅助功能后返回语落；也可在主窗口录音并手动复制结果。"
        case .inspectClipboard: "粘贴按键已经发出，请先检查目标文字和剪贴板，避免重复粘贴。"
        }
    }
}
