import VoxInkCore
import Foundation

@MainActor public protocol PasteService: AnyObject {
    var accessibilityGranted: Bool { get }
    func requestAccessibility() -> Bool
    func captureTarget() -> PasteTarget?
    func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome
    func cancel()
    func finishPendingCleanup() async
    func setRemotePasteTiming(_ timing: RemotePasteTiming)
    func setUUWindowsPaste(_ enabled: Bool)
    func setRemoteApplications(_ profiles: [RemoteApplicationProfile])
    func setRemoteDevices(_ devices: [String: Bool])
    func setCleanupFailureHandler(_ handler: @escaping @MainActor (UUID) -> Void)
}

extension PasteService {
    public func finishPendingCleanup() async {}
    public func setRemotePasteTiming(_ timing: RemotePasteTiming) {}
    public func setUUWindowsPaste(_ enabled: Bool) {}
    public func setRemoteApplications(_ profiles: [RemoteApplicationProfile]) {}
    public func setRemoteDevices(_ devices: [String: Bool]) {}
    public func setCleanupFailureHandler(_ handler: @escaping @MainActor (UUID) -> Void) {}
}

extension PasteCoordinator: PasteService {}
