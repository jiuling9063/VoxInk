import AppKit

@MainActor final class ServicesProvider: NSObject {
    @objc func insertProbeText(_ pasteboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        pasteboard.clearContents()
        guard pasteboard.setString("VoxInk 服务测试：今天我们开会。", forType: .string) else {
            error.pointee = "无法写入服务专用粘贴板。"
            return
        }
        let report = URL.applicationSupportDirectory.appendingPathComponent("VoxInkServicesProbe/results.txt")
        do {
            try FileManager.default.createDirectory(at: report.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "Services callback: sandbox=\(entitlementEnabled("com.apple.security.app-sandbox")); network.client=\(entitlementEnabled("com.apple.security.network.client")); returned fixed text using service pasteboard only\n"
                .write(to: report, atomically: true, encoding: .utf8)
        } catch { NSLog("Services probe could not save its test report: %@", error.localizedDescription) }
    }
}

@MainActor final class ServicesDelegate: NSObject, NSApplicationDelegate {
    private let provider = ServicesProvider()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "退出验证程序", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = submenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 160),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VoxInk · 系统服务验证"
        let label = NSTextField(wrappingLabelWithString: "在测试文稿中使用应用菜单 → 服务 → VoxInk 插入测试文字。\n\n仅返回固定测试文字；不录音、不读取其他应用、不模拟按键。")
        label.frame = NSRect(x: 24, y: 30, width: 490, height: 100)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

@main struct ServicesProbeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ServicesDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
