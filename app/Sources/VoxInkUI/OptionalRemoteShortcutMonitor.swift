import Foundation

@MainActor protocol RemoteShortcutMonitoring: AnyObject {
    var isQuiescent: Bool { get }
    var isActive: Bool { get }
    func start() -> Bool
    func stop()
}

/// Remote event interception is an optional compatibility aid, not a prerequisite for Carbon shortcuts.
@MainActor final class OptionalRemoteShortcutMonitor {
    private var monitor: (any RemoteShortcutMonitoring)?
    private let makeMonitor: () -> (any RemoteShortcutMonitoring)?
    init(makeMonitor: @escaping () -> (any RemoteShortcutMonitoring)?) { self.makeMonitor = makeMonitor }
    var isActive: Bool { monitor?.isActive == true }
    var isQuiescent: Bool { monitor?.isQuiescent != false }

    func update(enabled: Bool) {
        if enabled, isActive { return }
        if enabled, !isQuiescent { return }
        monitor?.stop(); monitor = nil
        guard enabled, let candidate = makeMonitor() else { return }
        guard candidate.start() else { candidate.stop(); return }
        monitor = candidate
    }
}
