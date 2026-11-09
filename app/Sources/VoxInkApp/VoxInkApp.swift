import AppKit
import Darwin
import Combine
import SwiftUI
import Sparkle
import VoxInkUI
import VoxInkCore

@MainActor private enum ApplicationState {
    static let dictionary = UserDictionaryController(storage: UserDictionaryFileStore())
    static let store = AppStore(audioRecovery: AudioRecoveryStore(),
                               temporaryAudioJanitor: AudioFilePreparation.purgeExpiredTemporaryAudio,
                               dictionary: dictionary)
    static let loginItem = LoginItemController()
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var store: AppStore?
    private var quitting = false
    private var terminationSignalSource: DispatchSourceSignal?
    private var shortcuts: GlobalShortcutController?
    private var feedback: RecordingPanel?
    private var observation: AnyCancellable?
    private var feedbackUpdate: Task<Void, Never>?
    private var mainWindow: WorkspaceWindowController?
    private var updateController: SPUStandardUpdaterController?

    func showMainWindow() {
        guard let store else { return }
        store.refreshPermissions()
        if mainWindow == nil {
            mainWindow = WorkspaceWindowController(store: store)
        }
        mainWindow?.present()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last, url.scheme?.lowercased() == "voxink" else { return }
        connect(ApplicationState.store)
        showMainWindow()
        mainWindow?.openRoute(url.pathComponents.last(where: { $0 != "/" }) ?? url.host ?? "")
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
        store.configureShortcutSuspension { [weak shortcuts] in shortcuts?.stop() }
        store.configureShortcutRegistration { [weak shortcuts] in shortcuts?.changeShortcut(to: $0) ?? false }
        observation = Publishers.CombineLatest(store.$phase, store.$status).sink { [weak self] _ in
            guard let self, self.feedbackUpdate == nil else { return }
            self.feedbackUpdate = Task { @MainActor [weak self] in
                guard let self, let store = self.store else { return }
                defer { self.feedbackUpdate = nil }
                let enabled = store.shortcutTargetName != nil && store.canCancel
                let registered = self.shortcuts?.setCancellationEnabled(enabled) == true
                store.setCancellationShortcutAvailable(enabled && registered)
                if !registered {
                    store.setShortcutStatus(L("Esc 注册失败，可在语落窗口点击取消"))
                }
                self.feedback?.update(store: store)
            }
        }
        store.prepareForUse()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        connect(ApplicationState.store)
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        updateController = controller
        store?.configureUpdateWindow { [weak controller] in controller?.checkForUpdates(nil) }
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

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard let store, !store.canEditModelServices else { return false }
        Task { @MainActor in
            while !store.canEditModelServices && !quitting {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !quitting { installHandler() }
        }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateLater }
        guard let store else { return .terminateNow }
        quitting = true
        shortcuts?.stop()
        feedbackUpdate?.cancel(); feedbackUpdate = nil
        feedback?.hide()
        Task { await store.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

@main struct VoxInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ApplicationState.store
    var body: some Scene {
        MenuBarExtra(L("语落 VoxInk"), systemImage: "waveform") {
            Text(store.phase == .failed ? L("需要处理 · 打开语落查看") : store.transcriptionStatus)
            Button(L("打开语落")) { delegate.showMainWindow() }
            Button(store.phase == .recording ? L("停止并识别") : L("开始录音")) {
                delegate.showMainWindow()
                if store.phase == .recording { store.finishRecording() } else { store.beginRecording() }
            }.disabled(!store.canStart && store.phase != .recording)
            Button(L("复制结果")) { store.copyResult() }.disabled(store.transcript.isEmpty || !store.canStart)
            Divider()
            if let uu = store.uuRemoteApplication {
                Menu(L("UU 默认系统：\(uu.defaultSystem.title)")) {
                    Picker(L("默认远端系统"), selection: Binding(get: { uu.defaultSystem }, set: { system in
                        var profile = uu
                        profile.defaultSystem = system
                        store.setRemoteApplication(profile)
                    })) {
                        ForEach(RemotePasteSystem.allCases, id: \.self) { system in
                            Text(system.menuTitle).tag(system)
                        }
                    }.pickerStyle(.inline)
                }.disabled(!store.canStart)
            }
            SettingsLink { Text(L("设置…")) }.keyboardShortcut(",")
            Button(L("检查更新…")) { store.requestUpdate() }.disabled(!store.canRequestUpdate)
            Button(L("退出语落")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings {
            PreferencesView(store: store, loginItem: ApplicationState.loginItem,
                showGuide: { delegate.showMainWindow() })
        }
    }
}
