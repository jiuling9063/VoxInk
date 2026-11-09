import AppKit
import ApplicationServices
import Carbon

/// WeChat's custom chat editor can return AXNoValue even while its native Paste
/// command is usable. Bind that command to the main window captured at dictation start.
@MainActor
final class WeChatPasteCommand {
    static let bundleID = "com.tencent.xinWeChat"
    private let application: AXUIElement
    private let window: AXUIElement
    private let pid: pid_t
    let token = UUID()

    init?(application running: NSRunningApplication) {
        guard running.bundleIdentifier == Self.bundleID, running.isActive else { return nil }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let window = Self.chatWindow(in: app) else { return nil }
        self.application = app
        self.window = window
        self.pid = running.processIdentifier
    }

    func matches(_ target: PasteTarget) -> Bool {
        guard target.bundleID == Self.bundleID, target.pid == pid, target.weChatWindowToken == token,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let current = Self.chatWindow(in: application) else { return false }
        return CFEqual(current, window)
    }

    func perform(for target: PasteTarget, whileOwningClipboard: () -> Bool) -> Bool {
        guard matches(target), let item = pasteItem(), Self.value(item, kAXEnabledAttribute) as? Bool == true,
              matches(target), !IsSecureEventInputEnabled(), whileOwningClipboard() else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private func pasteItem() -> AXUIElement? {
        guard let bar = Self.element(application, kAXMenuBarAttribute) else { return nil }
        let editTitles = ["编辑", "編輯", "Edit"]
        guard let edit = Self.children(bar).first(where: { editTitles.contains(Self.value($0, kAXTitleAttribute) as? String ?? "") }),
              let menu = Self.children(edit).first else { return nil }
        return Self.children(menu).first { item in
            Self.value(item, kAXRoleAttribute) as? String == kAXMenuItemRole &&
                (Self.value(item, kAXMenuItemCmdCharAttribute) as? String)?.uppercased() == "V" &&
                Self.value(item, kAXMenuItemCmdModifiersAttribute) as? Int == 0
        }
    }

    private static func chatWindow(in app: AXUIElement) -> AXUIElement? {
        guard let focused = element(app, kAXFocusedWindowAttribute),
              let main = element(app, kAXMainWindowAttribute), CFEqual(focused, main),
              value(focused, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              value(focused, kAXModalAttribute) as? Bool == false,
              ["微信", "WeChat", "Weixin"].contains(value(focused, kAXTitleAttribute) as? String ?? ""),
              !children(focused).contains(where: { value($0, kAXRoleAttribute) as? String == kAXSheetRole }) else { return nil }
        return focused
    }

    private static func element(_ parent: AXUIElement, _ key: String) -> AXUIElement? {
        guard let raw = value(parent, key), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
}
