import Combine
import ServiceManagement

public enum LoginItemState: Equatable, Sendable {
    case disabled, enabled, requiresApproval, unavailable

    public var title: String {
        switch self {
        case .disabled: "未开启"
        case .enabled: "已开启"
        case .requiresApproval: "等待系统允许"
        case .unavailable: "当前安装不可用"
        }
    }
}

@MainActor public protocol LoginItemService: AnyObject {
    var state: LoginItemState { get }
    func enable() throws
    func disable() async throws
    func openSettings()
}

@MainActor private final class SystemLoginItemService: LoginItemService {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }
    func enable() throws { try SMAppService.mainApp.register() }
    func disable() async throws { try await SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor public final class LoginItemController: ObservableObject {
    @Published public private(set) var state: LoginItemState
    @Published public private(set) var isUpdating = false
    @Published public private(set) var errorMessage: String?
    private let service: any LoginItemService

    public convenience init() { self.init(service: SystemLoginItemService()) }
    public init(service: any LoginItemService) {
        self.service = service
        state = service.state
    }

    public func refresh() { state = service.state }
    public func openSettings() { service.openSettings() }

    public func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { refresh(); isUpdating = false }
        do {
            if enabled {
                if service.state != .enabled && service.state != .requiresApproval { try service.enable() }
            } else if service.state == .enabled || service.state == .requiresApproval {
                try await service.disable()
            }
        } catch {
            errorMessage = enabled
                ? "无法开启登录启动。请检查 App 安装位置与系统的登录项设置后重试。"
                : "关闭登录启动失败，请在系统登录项中检查语落。"
        }
    }
}
