import AppKit
import ApplicationServices
import Foundation

public enum RemotePasteTiming: String, CaseIterable, Sendable {
    case stable, faster, fast, experimental
    public var title: String {
        switch self {
        case .stable: "稳定 · 2 秒"
        case .faster: "较快 · 1.5 秒"
        case .fast: "快速 · 1 秒"
        case .experimental: "试验 · 0.7 秒"
        }
    }
    var delay: Duration {
        switch self {
        case .stable: .seconds(2)
        case .faster: .milliseconds(1500)
        case .fast: .seconds(1)
        case .experimental: .milliseconds(700)
        }
    }
}

public struct RemoteApplicationProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public var usesControl: Bool
    public init(bundleID: String, name: String, usesControl: Bool = false) {
        self.bundleID = bundleID; self.name = name; self.usesControl = usesControl
    }
}

public struct PasteTarget: Sendable, Equatable {
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let remoteDeviceName: String?
    public let remoteUsesControl: Bool?

    public init(pid: Int32, bundleID: String, name: String, remoteDeviceName: String? = nil, remoteUsesControl: Bool? = nil) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.remoteDeviceName = remoteDeviceName
        self.remoteUsesControl = remoteUsesControl
    }
}

public enum PasteOutcome: Sendable, Equatable {
    case sent
    case sentWithCleanupFailure(String)
    case cancelledBeforeSend
    case cancelledAfterSend
    case failed(String)

    public var wasIssued: Bool {
        switch self {
        case .sent, .sentWithCleanupFailure, .cancelledAfterSend:
            true
        case .cancelledBeforeSend, .failed:
            false
        }
    }

    public var message: String {
        switch self {
        case .sent:
            "已发送粘贴"
        case .sentWithCleanupFailure(let message), .failed(let message):
            message
        case .cancelledBeforeSend:
            "已取消，未发送粘贴"
        case .cancelledAfterSend:
            "取消发生在粘贴发送后，剪贴板清理已完成"
        }
    }
}

struct PasteboardSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let types: [String: Data]
    }

    let items: [Item]
    let changeCount: Int
}

struct PasteboardMutationError: Error {
    let ownedChangeCount: Int
}

enum PasteboardRestoreResult: Equatable {
    case restored
    case skippedOwnershipLost
    case failed
}

@MainActor
protocol PasteEnvironment: AnyObject {
    func captureTarget() -> PasteTarget?
    func remoteDeviceName(for target: PasteTarget, candidates: [String]) -> String?
    var accessibilityGranted: Bool { get }
    func requestAccessibility() -> Bool
    func isTargetValid(_ target: PasteTarget) -> Bool
    func activateAndConfirm(_ target: PasteTarget, timeout: Duration) async -> Bool
    func isKnownSecureFocusedField() -> Bool
    func pasteboardSnapshot() throws -> PasteboardSnapshot
    func writePlainText(_ text: String) throws -> Int
    func currentPasteboardChangeCount() -> Int
    func restorePasteboard(_ snapshot: PasteboardSnapshot, expectedChangeCount: Int) -> PasteboardRestoreResult
    func areCommandModifiersReleased() -> Bool
    func postPaste(to target: PasteTarget, usingControl: Bool) -> Bool
    func delay(for duration: Duration) async
    func delayIgnoringCancellation(for duration: Duration) async
}

extension PasteEnvironment {
    func remoteDeviceName(for target: PasteTarget, candidates: [String]) -> String? { nil }
}

public enum RemoteDeviceProfiles {
    public static func names(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public static func make(mac: String, windows: String) -> [String: Bool] {
        let macNames = Set(names(mac)), windowsNames = Set(names(windows))
        // A name assigned to both systems is ambiguous and must not be guessed.
        var result: [String: Bool] = [:]
        for name in macNames.subtracting(windowsNames) { result[name] = false }
        for name in windowsNames.subtracting(macNames) { result[name] = true }
        return result
    }

    static func match(labels: [String], candidates: [String]) -> String? {
        let labels = Set(labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let matches = Set(candidates).intersection(labels)
        return matches.count == 1 ? matches.first : nil
    }
}

@MainActor
protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    var types: [NSPasteboard.PasteboardType] { get }
    @discardableResult func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

@MainActor
private final class SystemPasteboardAccess: PasteboardAccess {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    var pasteboardItems: [NSPasteboardItem]? { pasteboard.pasteboardItems }
    var types: [NSPasteboard.PasteboardType] { pasteboard.types ?? [] }
    func clearContents() -> Int { pasteboard.clearContents() }
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        pasteboard.setString(string, forType: dataType)
    }
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool { pasteboard.writeObjects(objects) }
}

@MainActor
public final class PasteCoordinator {
    private let environment: any PasteEnvironment
    private var attemptedSessions: Set<UUID> = []
    private var activeTransactionID: UUID?
    private var cancellationRequested = false
    private var pendingCleanup: Task<Void, Never>?
    private var cleanupFailureHandler: (@MainActor (UUID) -> Void)?
    private var remoteTiming: RemotePasteTiming = .stable
    private var remoteApplications: [RemoteApplicationProfile] = []
    private var uuWindowsPaste = false
    private var remoteDevices: [String: Bool] = [:]

    public func setRemotePasteTiming(_ timing: RemotePasteTiming) { remoteTiming = timing }
    public func setRemoteApplications(_ profiles: [RemoteApplicationProfile]) { remoteApplications = profiles }
    public func setUUWindowsPaste(_ enabled: Bool) { uuWindowsPaste = enabled }
    public func setRemoteDevices(_ devices: [String: Bool]) { remoteDevices = devices }
    public func setCleanupFailureHandler(_ handler: @escaping @MainActor (UUID) -> Void) {
        cleanupFailureHandler = handler
    }
    public func finishPendingCleanup() async { await pendingCleanup?.value }

    public convenience init() {
        self.init(environment: AppKitPasteEnvironment())
    }

    init(environment: any PasteEnvironment) {
        self.environment = environment
    }

    public func captureTarget() -> PasteTarget? {
        guard let target = environment.captureTarget() else { return nil }
        guard target.bundleID == "com.netease.uuremote" else {
            guard let profile = remoteApplications.first(where: { $0.bundleID == target.bundleID }) else { return target }
            return PasteTarget(pid: target.pid, bundleID: target.bundleID, name: target.name,
                               remoteUsesControl: profile.usesControl)
        }
        let device = environment.remoteDeviceName(for: target, candidates: Array(remoteDevices.keys))
        let name = device.map { "\(target.name) · \($0)" } ?? target.name
        return PasteTarget(pid: target.pid, bundleID: target.bundleID, name: name,
                           remoteDeviceName: device, remoteUsesControl: device.flatMap { remoteDevices[$0] } ?? uuWindowsPaste)
    }

    private func remoteTargetMatches(_ target: PasteTarget) -> Bool {
        guard let device = target.remoteDeviceName else { return true }
        return environment.remoteDeviceName(for: target, candidates: Array(remoteDevices.keys)) == device
    }

    public var accessibilityGranted: Bool {
        environment.accessibilityGranted
    }

    @discardableResult
    public func requestAccessibility() -> Bool {
        environment.requestAccessibility()
    }

    public func cancel() {
        guard activeTransactionID != nil else { return }
        cancellationRequested = true
    }

    public func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed("没有可粘贴的文字")
        }
        guard !attemptedSessions.contains(sessionID) else {
            return .failed("该会话已尝试粘贴")
        }
        guard activeTransactionID == nil else {
            return .failed("已有粘贴事务正在进行")
        }
        attemptedSessions.insert(sessionID)
        let transactionID = UUID()
        activeTransactionID = transactionID
        cancellationRequested = false
        defer {
            if activeTransactionID == transactionID {
                activeTransactionID = nil
                cancellationRequested = false
            }
        }

        // A subsequent paste must not snapshot the previous dictation or replace
        // its clipboard before the remote computer has had time to consume it.
        await finishPendingCleanup()
        guard !cancellationRequested else { return .cancelledBeforeSend }
        guard environment.accessibilityGranted else {
            return .failed("需要辅助功能权限")
        }
        guard environment.isTargetValid(target),
              await environment.activateAndConfirm(target, timeout: .milliseconds(600)) else {
            return .failed("无法确认粘贴目标")
        }
        guard remoteTargetMatches(target) else { return .failed("UU 远端设备已切换或无法识别，请回到原设备重试") }
        guard !environment.isKnownSecureFocusedField() else {
            return .failed("安全输入框不允许自动粘贴")
        }
        guard !cancellationRequested else {
            return .cancelledBeforeSend
        }

        let snapshot: PasteboardSnapshot
        do {
            snapshot = try environment.pasteboardSnapshot()
        } catch {
            return .failed("无法完整读取剪贴板")
        }

        let ownedChangeCount: Int
        do {
            guard environment.currentPasteboardChangeCount() == snapshot.changeCount else {
                return .failed("剪贴板已被其他操作修改")
            }
            ownedChangeCount = try environment.writePlainText(text)
        } catch {
            guard let mutation = error as? PasteboardMutationError else {
                return .failed("无法写入剪贴板")
            }
            switch environment.restorePasteboard(snapshot, expectedChangeCount: mutation.ownedChangeCount) {
            case .restored, .skippedOwnershipLost:
                return .failed("无法写入剪贴板")
            case .failed:
                return .failed("无法写入剪贴板，且原剪贴板恢复失败")
            }
        }

        // Remote clients synchronize the clipboard asynchronously; restoring it too soon can
        // make the remote computer paste the previous contents instead.
        let isRemote = target.bundleID == "com.netease.uuremote" || target.remoteUsesControl != nil
            || remoteApplications.contains(where: { $0.bundleID == target.bundleID })
        await environment.delay(for: isRemote ? remoteTiming.delay : .milliseconds(150))

        if cancellationRequested {
            return cleanupBeforeSend(snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard await environment.activateAndConfirm(target, timeout: .milliseconds(600)) else {
            return failBeforeSend("无法确认粘贴目标", snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard !environment.isKnownSecureFocusedField() else {
            return failBeforeSend("安全输入框不允许自动粘贴", snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard await waitForModifierRelease() else {
            return failBeforeSend("修饰键未释放", snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard await environment.activateAndConfirm(target, timeout: .milliseconds(600)),
              !environment.isKnownSecureFocusedField() else {
            return failBeforeSend("无法再次确认粘贴目标", snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard environment.accessibilityGranted else {
            return failBeforeSend("辅助功能权限已失效", snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard environment.currentPasteboardChangeCount() == ownedChangeCount else {
            return .failed("剪贴板已被其他操作修改")
        }
        guard !cancellationRequested else {
            return cleanupBeforeSend(snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard remoteTargetMatches(target) else {
            return failBeforeSend("UU 远端设备已切换或无法识别，请回到原设备重试", snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }
        guard environment.postPaste(to: target, usingControl: isRemote && (target.remoteUsesControl ?? remoteApplications.first(where: { $0.bundleID == target.bundleID })?.usesControl ?? (target.bundleID == "com.netease.uuremote" && uuWindowsPaste))) else {
            return failBeforeSend("无法发送粘贴按键", snapshot: snapshot, ownedChangeCount: ownedChangeCount)
        }

        if isRemote {
            pendingCleanup = Task { @MainActor in
                await environment.delayIgnoringCancellation(for: .seconds(3))
                if environment.currentPasteboardChangeCount() == ownedChangeCount,
                   environment.restorePasteboard(snapshot, expectedChangeCount: ownedChangeCount) == .failed {
                    cleanupFailureHandler?(sessionID)
                }
                pendingCleanup = nil
            }
            return .sent
        }
        await environment.delayIgnoringCancellation(for: .milliseconds(1_200))
        let wasCancelled = cancellationRequested
        if environment.currentPasteboardChangeCount() == ownedChangeCount,
           environment.restorePasteboard(snapshot, expectedChangeCount: ownedChangeCount) == .failed {
            return .sentWithCleanupFailure("已发送粘贴，但剪贴板恢复失败")
        }
        return wasCancelled ? .cancelledAfterSend : .sent
    }

    private func waitForModifierRelease() async -> Bool {
        for attempt in 0..<12 {
            if environment.areCommandModifiersReleased() { return true }
            if attempt < 11 { await environment.delay(for: .milliseconds(50)) }
        }
        return false
    }

    private func cleanupBeforeSend(
        snapshot: PasteboardSnapshot,
        ownedChangeCount: Int
    ) -> PasteOutcome {
        if environment.currentPasteboardChangeCount() == ownedChangeCount,
           environment.restorePasteboard(snapshot, expectedChangeCount: ownedChangeCount) == .failed {
            return .failed("已取消粘贴，但剪贴板恢复失败")
        }
        return .cancelledBeforeSend
    }

    private func failBeforeSend(
        _ message: String,
        snapshot: PasteboardSnapshot,
        ownedChangeCount: Int
    ) -> PasteOutcome {
        if environment.currentPasteboardChangeCount() == ownedChangeCount,
           environment.restorePasteboard(snapshot, expectedChangeCount: ownedChangeCount) == .failed {
            return .failed("\(message)，且剪贴板恢复失败")
        }
        return .failed(message)
    }
}

@MainActor
final class AppKitPasteEnvironment: PasteEnvironment {
    private enum ClipboardError: Error { case changedDuringRead, unreadableType }
    private let pasteboard: any PasteboardAccess

    init(pasteboard: any PasteboardAccess = SystemPasteboardAccess()) {
        self.pasteboard = pasteboard
    }

    func captureTarget() -> PasteTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = application.bundleIdentifier else {
            return nil
        }
        return PasteTarget(
            pid: application.processIdentifier,
            bundleID: bundleID,
            name: application.localizedName ?? bundleID
        )
    }

    func remoteDeviceName(for target: PasteTarget, candidates: [String]) -> String? {
        guard target.bundleID == "com.netease.uuremote", !candidates.isEmpty else { return nil }
        let application = AXUIElementCreateApplication(target.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeDowncast(value, to: AXUIElement.self)
        var labels: [String] = []
        // UU exposes its connection name in window chrome. Do not walk remote content.
        func collect(_ element: AXUIElement, depth: Int) {
            for attribute in [kAXTitleAttribute, kAXValueAttribute] {
                var text: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &text) == .success,
                   let text = text as? String { labels.append(text) }
            }
            guard depth < 2 else { return }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] {
                for child in children.prefix(40) { collect(child, depth: depth + 1) }
            }
        }
        collect(window, depth: 0)
        return RemoteDeviceProfiles.match(labels: labels, candidates: candidates)
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func isTargetValid(_ target: PasteTarget) -> Bool {
        guard target.pid != ProcessInfo.processInfo.processIdentifier else { return false }
        guard let application = NSRunningApplication(processIdentifier: target.pid) else { return false }
        return !application.isTerminated && application.bundleIdentifier == target.bundleID
    }

    func activateAndConfirm(_ target: PasteTarget, timeout: Duration) async -> Bool {
        guard isTargetValid(target),
              let application = NSRunningApplication(processIdentifier: target.pid) else { return false }
        if matchesFrontmost(target) { return true }
        application.activate(options: [])
        for _ in 0..<12 {
            if matchesFrontmost(target) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return matchesFrontmost(target)
    }

    func isKnownSecureFocusedField() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
              let value = subrole as? String else { return false }
        return value == "AXSecureTextField"
    }

    func pasteboardSnapshot() throws -> PasteboardSnapshot {
        let before = pasteboard.changeCount
        guard let sourceItems = pasteboard.pasteboardItems else {
            guard pasteboard.types.isEmpty else { throw ClipboardError.unreadableType }
            guard pasteboard.changeCount == before else { throw ClipboardError.changedDuringRead }
            return PasteboardSnapshot(items: [], changeCount: before)
        }
        let items = try sourceItems.map { item in
            var values: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw ClipboardError.unreadableType }
                values[type.rawValue] = Data(data)
            }
            return PasteboardSnapshot.Item(types: values)
        }
        guard pasteboard.changeCount == before else { throw ClipboardError.changedDuringRead }
        return PasteboardSnapshot(items: items, changeCount: before)
    }

    func writePlainText(_ text: String) throws -> Int {
        let ownedChangeCount = pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string),
              pasteboard.changeCount == ownedChangeCount else {
            throw PasteboardMutationError(ownedChangeCount: ownedChangeCount)
        }
        return ownedChangeCount
    }

    func currentPasteboardChangeCount() -> Int { pasteboard.changeCount }

    func restorePasteboard(
        _ snapshot: PasteboardSnapshot,
        expectedChangeCount: Int
    ) -> PasteboardRestoreResult {
        var objects: [NSPasteboardItem] = []
        for saved in snapshot.items {
            let item = NSPasteboardItem()
            for (rawType, data) in saved.types {
                guard item.setData(data, forType: NSPasteboard.PasteboardType(rawType)) else {
                    return .failed
                }
            }
            objects.append(item)
        }
        guard pasteboard.changeCount == expectedChangeCount else { return .skippedOwnershipLost }
        let restoreChangeCount = pasteboard.clearContents()
        let didWrite = objects.isEmpty || pasteboard.writeObjects(objects)
        guard pasteboard.changeCount == restoreChangeCount else { return .skippedOwnershipLost }
        return didWrite ? .restored : .failed
    }

    func areCommandModifiersReleased() -> Bool {
        let held = CGEventSource.flagsState(.combinedSessionState)
        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        return held.intersection(relevant).isEmpty
    }

    static func pasteEvents(usingControl: Bool) -> [CGEvent]? {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return nil }
        down.flags = usingControl ? .maskControl : .maskCommand
        up.flags = down.flags
        return [down, up]
    }

    func postPaste(to target: PasteTarget, usingControl: Bool) -> Bool {
        guard let events = Self.pasteEvents(usingControl: usingControl) else { return false }
        for event in events { event.post(tap: .cghidEventTap) }
        return true
    }

    func delay(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    func delayIgnoringCancellation(for duration: Duration) async {
        await Task.detached {
            try? await Task.sleep(for: duration)
        }.value
    }

    private func matchesFrontmost(_ target: PasteTarget) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        return !frontmost.isTerminated
            && frontmost.processIdentifier == target.pid
            && frontmost.bundleIdentifier == target.bundleID
    }
}
