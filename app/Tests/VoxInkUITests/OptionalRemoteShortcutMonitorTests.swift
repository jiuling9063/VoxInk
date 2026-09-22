import Testing
@testable import VoxInkUI

@MainActor private final class FakeRemoteMonitor: RemoteShortcutMonitoring {
    var isQuiescent = true
    var isActive = false
    var startSucceeds = false
    var starts = 0
    var stops = 0
    func start() -> Bool { starts += 1; isActive = startSucceeds; return startSucceeds }
    func stop() { stops += 1; isActive = false }
}

@MainActor struct OptionalRemoteShortcutMonitorTests {
    @Test func unavailableMonitorCanRetryAfterAuthorizationWithoutBlockingShortcut() {
        let monitor = FakeRemoteMonitor()
        let support = OptionalRemoteShortcutMonitor { monitor }
        support.update(enabled: true)
        #expect(!support.isActive && support.isQuiescent)
        #expect(monitor.stops == 1)
        monitor.startSucceeds = true
        support.update(enabled: true)
        #expect(support.isActive && monitor.starts == 2)
        support.update(enabled: true)
        #expect(monitor.starts == 2)
        support.update(enabled: false)
        #expect(!support.isActive && monitor.stops == 2)
    }
    @Test func disabledShortcutDoesNotCreateRemoteMonitor() {
        var creations = 0
        let support = OptionalRemoteShortcutMonitor { creations += 1; return FakeRemoteMonitor() }
        support.update(enabled: false)
        #expect(creations == 0)
    }
    @Test func lostPermissionFallsBackAndCanRecover() {
        let monitor = FakeRemoteMonitor(); monitor.startSucceeds = true
        let support = OptionalRemoteShortcutMonitor { monitor }
        support.update(enabled: true)
        monitor.isActive = false; monitor.startSucceeds = false
        support.update(enabled: true)
        #expect(!support.isActive && support.isQuiescent)
        monitor.startSucceeds = true
        support.update(enabled: true)
        #expect(support.isActive)
    }
    @Test func refreshDoesNotRebuildMonitorDuringHeldShortcut() {
        let monitor = FakeRemoteMonitor(); monitor.startSucceeds = true
        let support = OptionalRemoteShortcutMonitor { monitor }
        support.update(enabled: true)
        monitor.isQuiescent = false; monitor.isActive = false
        support.update(enabled: true)
        #expect(!support.isQuiescent && monitor.stops == 0)
        support.update(enabled: false)
        #expect(support.isQuiescent && monitor.stops == 1)
    }
}
