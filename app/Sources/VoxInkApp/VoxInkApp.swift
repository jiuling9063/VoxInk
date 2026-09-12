import AppKit
import Darwin
import Combine
import SwiftUI
import VoxInkUI
import VoxInkCore

@MainActor private enum ApplicationState {
    static let dictionary = UserDictionaryController(storage: UserDictionaryFileStore())
    static let store = AppStore(audioRecovery: AudioRecoveryStore(),
                               temporaryAudioJanitor: AudioFilePreparation.purgeExpiredTemporaryAudio,
                               dictionary: dictionary)
    static let loginItem = LoginItemController()
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore?
    private var quitting = false
    private var terminationSignalSource: DispatchSourceSignal?
    private var shortcuts: GlobalShortcutController?
    private var feedback: RecordingPanel?
    private var observation: AnyCancellable?
    private var mainWindow: NSWindow?

    func showMainWindow() {
        guard let store else { return }
        store.refreshPermissions()
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "语落 VoxInk"
            window.identifier = NSUserInterfaceItemIdentifier("voxink-main")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: ContentView(store: store))
            window.contentMinSize = NSSize(width: 660, height: 600)
            window.setContentSize(NSSize(width: 720, height: 760))
            if !window.setFrameUsingName("voxink-main") { window.center() }
            window.setFrameAutosaveName("voxink-main")
            mainWindow = window
        }
        mainWindow?.deminiaturize(nil)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store?.refreshPermissions()
        ApplicationState.loginItem.refresh()
    }

    func connect(_ store: AppStore) {
        guard self.store == nil else { return }
        self.store = store
        feedback = RecordingPanel()
        let shortcuts = GlobalShortcutController(
            toggle: { [weak store] in store?.handleShortcutPressed() },
            released: { [weak store] in store?.handleShortcutReleased() },
            cancel: { [weak store] in store?.handleShortcutCancelled() }
        )
        self.shortcuts = shortcuts
        store.configureShortcutRegistration { [weak shortcuts] in shortcuts?.changeShortcut(to: $0) ?? false }
        observation = Publishers.CombineLatest(store.$phase, store.$status).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let store = self.store else { return }
                let enabled = store.shortcutTargetName != nil && store.canCancel
                let registered = self.shortcuts?.setCancellationEnabled(enabled) == true
                store.setCancellationShortcutAvailable(enabled && registered)
                if !registered {
                    store.setShortcutStatus("Esc 注册失败，可在语落窗口点击取消")
                }
                self.feedback?.update(store: store)
            }
        }
        store.prepareForUse()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        connect(ApplicationState.store)
        showMainWindow()
        Darwin.signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
        source.resume()
        terminationSignalSource = source
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateLater }
        guard let store else { return .terminateNow }
        quitting = true
        shortcuts?.stop()
        feedback?.hide()
        Task { await store.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

@main struct VoxInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ApplicationState.store
    var body: some Scene {
        MenuBarExtra("语落 VoxInk", systemImage: "waveform") {
            Text(store.phase == .failed ? "需要处理 · 打开语落查看" : store.modelState.title)
            Button("打开语落") { delegate.showMainWindow() }
            Button(store.phase == .recording ? "停止并识别" : "开始录音") {
                delegate.showMainWindow()
                if store.phase == .recording { store.finishRecording() } else { store.beginRecording() }
            }.disabled(!store.canStart && store.phase != .recording)
            Button("复制结果") { store.copyResult() }.disabled(store.transcript.isEmpty || !store.canStart)
            Divider()
            SettingsLink { Text("设置…") }.keyboardShortcut(",")
            Button("退出语落") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings {
            PreferencesView(store: store, loginItem: ApplicationState.loginItem,
                showGuide: { delegate.showMainWindow() })
        }
    }
}
