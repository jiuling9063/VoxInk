import AppKit
import XCTest

final class UpdateUITests: XCTestCase {
    private let bundleURL = URL(fileURLWithPath: "/Applications/VoxInk.app")

    private func button(_ app: XCUIApplication, titles: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@ OR title IN %@", titles, titles)).firstMatch
    }

    func testReleasedAppInstallsAndRelaunchesFromCheckForUpdates() throws {
        continueAfterFailure = false
        let app = XCUIApplication(url: bundleURL)
        let previousPID = try XCTUnwrap(NSRunningApplication.runningApplications(
            withBundleIdentifier: "local.voxink.preview").first?.processIdentifier)
        let check = button(app, titles: ["检查更新…", "Check for Updates…"])
        XCTAssertTrue(check.waitForExistence(timeout: 30), app.debugDescription)
        check.click()

        let install = button(app, titles: ["安装更新", "Install Update"])
        XCTAssertTrue(install.waitForExistence(timeout: 90), app.debugDescription)
        install.click()
        let relaunch = button(app, titles: ["安装并重启应用", "Install and Relaunch"])
        XCTAssertTrue(relaunch.waitForExistence(timeout: 300), app.debugDescription)
        relaunch.click()

        let restarted = NSPredicate { _, _ in
            NSRunningApplication.runningApplications(withBundleIdentifier: "local.voxink.preview")
                .contains { $0.processIdentifier != previousPID && $0.bundleURL == self.bundleURL && $0.isFinishedLaunching }
        }
        let wait = XCTNSPredicateExpectation(predicate: restarted, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 90), .completed)
    }
}
