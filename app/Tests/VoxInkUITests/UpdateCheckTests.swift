import Foundation
import Testing
@testable import VoxInkUI

private actor ReleaseFixture: ModelHTTPTransport {
    private(set) var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        #expect(request.url?.path == "/repos/jiuling9063/VoxInk/releases/latest")
        return (Data(#"{"tag_name":"v1.10.0"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor struct UpdateCheckTests {
    @Test func explicitUpdateOpensInstallerEvenWhenLaunchChecksAreOff() {
        let store = AppStore(preferences: nil)
        var checks = 0
        store.configureUpdateWindow { checks += 1 }
        store.setChecksForUpdates(false)
        store.requestUpdate()
        #expect(checks == 1)
        store.configureShortcutRegistration { _ in true }
        #expect(store.beginShortcutRecording())
        store.requestUpdate()
        #expect(checks == 1)
    }

    @Test func checksAtMostDailyAcrossLaunchesAndHonorsPreference() async throws {
        let name = "release-check-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: defaults), fixture = ReleaseFixture(), now = Date()
        await store.checkForUpdate(current: "1.2.0", now: now, transport: fixture)
        #expect(store.availableVersion == "1.10.0")
        let next = AppStore(preferences: defaults)
        await next.checkForUpdate(current: "1.2.0", now: now.addingTimeInterval(86399), transport: fixture)
        #expect(next.availableVersion == "1.10.0")
        #expect(await fixture.calls == 1)
        await next.checkForUpdate(current: "1.10.0", now: now.addingTimeInterval(86400), transport: fixture)
        #expect(next.availableVersion == nil)
        next.setChecksForUpdates(false)
        await next.checkForUpdate(current: "1.2.0", now: now.addingTimeInterval(172800), transport: fixture)
        #expect(await fixture.calls == 2)
    }
}
