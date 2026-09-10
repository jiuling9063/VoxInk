// A separate local test app. Never built into VoxInk or connected to messaging apps.
import AppKit

@MainActor final class CountedTextView: NSTextView {
    var onPaste: (() -> Void)?
    override func paste(_ sender: Any?) { super.paste(sender); onPaste?() }
}

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var count = 0
    private var clipboardBaseline: [[String: Data]]?
    private let clipboardStatus = NSTextField(labelWithString: "尚未记录剪贴板")
    private let eventStatus = NSTextField(labelWithString: "尚未收到按键事件")
    private var eventMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出测试框", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 340),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "VoxInk 本地粘贴测试框"
        let content = NSView(frame: window.contentView!.bounds)
        let label = NSTextField(labelWithString: "粘贴次数：0（本地测试，不会发送消息）")
        label.frame = NSRect(x: 20, y: 300, width: 580, height: 22)
        label.autoresizingMask = [.width, .minYMargin]
        content.addSubview(label)
        eventStatus.frame = NSRect(x: 20, y: 278, width: 580, height: 20)
        eventStatus.autoresizingMask = [.width, .minYMargin]
        content.addSubview(eventStatus)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.eventStatus.stringValue = "按键 \(event.keyCode) · \(event.type == .keyDown ? "按下" : "松开") · Command=\(event.modifierFlags.contains(.command)) · Option=\(event.modifierFlags.contains(.option))"
            }
            return event
        }
        let baseline = NSButton(title: "记录剪贴板状态", target: self, action: #selector(recordClipboard))
        baseline.frame = NSRect(x: 20, y: 20, width: 155, height: 26)
        content.addSubview(baseline)
        clipboardStatus.frame = NSRect(x: 185, y: 23, width: 415, height: 20)
        clipboardStatus.autoresizingMask = [.width]
        content.addSubview(clipboardStatus)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 60, width: 580, height: 210))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = CountedTextView(frame: scroll.bounds)
        text.isRichText = false
        text.font = .systemFont(ofSize: 18)
        text.autoresizingMask = [.width]
        text.onPaste = { [weak self, weak label] in
            guard let self else { return }
            self.count += 1
            label?.stringValue = "粘贴次数：\(self.count)（本地测试，不会发送消息）"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1700))
                guard let self, let baseline = self.clipboardBaseline else { return }
                self.clipboardStatus.stringValue = self.readClipboard() == baseline ? "剪贴板完整恢复：通过" : "剪贴板与基线不同"
            }
        }
        scroll.documentView = text
        content.addSubview(scroll)
        window.contentView = content
        window.center(); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func recordClipboard() {
        clipboardBaseline = readClipboard()
        clipboardStatus.stringValue = clipboardBaseline == nil ? "快照不可读" : "已记录完整项目/类型快照"
        if let text = (window?.contentView?.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? NSTextView) {
            window?.makeFirstResponder(text)
        }
    }

    private func readClipboard() -> [[String: Data]]? {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        var snapshot: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var values: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                values[type.rawValue] = Data(data)
            }
            snapshot.append(values)
        }
        return pasteboard.changeCount == count ? snapshot : nil
    }
}

let delegate = FixtureDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
