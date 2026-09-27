import AppKit
import SwiftUI
import VoxInkCore
import VoxInkUI

private enum Scenario: String, CaseIterable, Identifiable {
    case setupRemote = "引导：远程配置", setupText = "引导：文字测试", setupSpeech = "引导：语音试用"
    case setup = "首次引导", ready = "日常就绪", loading = "模型加载"
    case recording = "录音", transcribing = "识别", pasting = "写入", cancelling = "取消"
    case result = "长结果", empty = "空识别", failure = "目标失效", cleanup = "剪贴板恢复失败"
    case modelFailure = "模型失败"
    var id: String { rawValue }
}

private let fixtureURL = URL(fileURLWithPath: "/voxink-interface-check-memory-fixture.wav")
private let exampleText = "明天上午 10:30 讨论 VoxInk 0.1，预算 1234.50 元。网址 https://example.com/a?q=1，路径 /tmp/report.json。\n" +
    String(repeating: "这是一段用于检查换行和滚动的模拟文字，中英文 English 与数字 123 保持原样。\n", count: 12)

private actor PreviewTranscriber: TranscriptionService {
    var held: Scenario?
    var text = exampleText
    var fails = false
    func configure(held: Scenario? = nil, empty: Bool = false, fails: Bool = false) {
        self.held = held; self.text = empty ? "" : exampleText; self.fails = fails
    }
    func prepare() async throws {
        while held == .loading { try await Task.sleep(for: .milliseconds(30)) }
        if fails { throw CocoaError(.fileReadUnknown) }
    }
    func transcribe(url: URL) async throws -> String {
        while held == .transcribing { try await Task.sleep(for: .milliseconds(30)) }
        return text
    }
    func cancel() async {
        while held == .cancelling { try? await Task.sleep(for: .milliseconds(30)) }
    }
}

@MainActor private final class PreviewRecorder: AudioRecording {
    var isRecording = false
    func requestPermission() async -> Bool { true }
    func start() throws { isRecording = true }
    func stop() throws -> URL { isRecording = false; return fixtureURL }
    func sample() -> AudioCaptureSample { .init(elapsed: 12, level: 0.62) }
    func cancel() { isRecording = false }
}

@MainActor private final class PreviewPaste: PasteService {
    var accessibilityGranted = true
    var held = false
    var outcome: PasteOutcome = .sent
    func requestAccessibility() -> Bool { accessibilityGranted }
    func captureTarget() -> PasteTarget? { .init(pid: -1, bundleID: "preview", name: "模拟远程输入框") }
    func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome {
        while held && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(30)) }
        return Task.isCancelled ? .cancelledBeforeSend : outcome
    }
    func cancel() { held = false }
}

private actor PreviewRecovery: AudioRecoveryStorage {
    var record: RetainedAudio?
    func save(_ source: URL) -> RetainedAudio {
        let value = RetainedAudio(id: UUID(), createdAt: Date(), url: source)
        record = value; return value
    }
    func latest() -> RetainedAudio? { record }
    func discard(_ id: UUID) { if record?.id == id { record = nil } }
    func purgeExpired() {}
}

private actor PreviewDictionary: UserDictionaryStorage {
    var entries: [UserDictionaryEntry] = []
    var fails = false
    func setFailure(_ value: Bool) { fails = value }
    func load() -> [UserDictionaryEntry] { entries }
    func save(_ entries: [UserDictionaryEntry]) throws {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        self.entries = entries
    }
}

@MainActor private final class PreviewLogin: LoginItemService {
    var state: LoginItemState = .disabled
    var fails = false
    func enable() throws {
        if fails { throw CocoaError(.fileWriteNoPermission) }
        state = .enabled
    }
    func disable() async throws { state = .disabled }
    func openSettings() {}
}

@MainActor private final class GalleryController: ObservableObject {
    @Published var store: AppStore
    @Published var changing = false
    @Published var error: String?
    @Published var exportStatus = "⌘⇧E 导出当前演示图"
    private var workspaceWindow: WorkspaceWindowController?

    func showWorkspaceWindow(compact: Bool) {
        workspaceWindow?.close()
        workspaceWindow = WorkspaceWindowController(store: store, restoresFrame: false)
        workspaceWindow?.window?.setContentSize(NSSize(width: compact ? 660 : 820, height: 600))
        workspaceWindow?.present()
    }

    private var service: PreviewTranscriber
    private var paste: PreviewPaste
    let dictionaryStorage = PreviewDictionary()
    let loginService = PreviewLogin()
    let loginItem: LoginItemController

    func exportCurrentView() {
        do { exportStatus = try DemoExport.save(phase: String(describing: store.phase)) }
        catch { exportStatus = "导出失败，请检查目录和窗口状态。" }
    }

    init() {
        let service = PreviewTranscriber(), paste = PreviewPaste()
        self.service = service; self.paste = paste
        loginItem = LoginItemController(service: loginService)
        store = Self.makeStore(service, paste, dictionaryStorage)
    }

    private static func makeStore(_ service: PreviewTranscriber, _ paste: PreviewPaste, _ dictionary: PreviewDictionary) -> AppStore {
        AppStore(service: service, pasteService: paste, recorder: PreviewRecorder(), preferences: nil,
                 microphoneStatus: { .authorized }, audioPreparer: { $0 }, audioCleaner: { _ in },
                 audioRecovery: PreviewRecovery(), dictionary: UserDictionaryController(storage: dictionary),
                 clipboardWriter: { _ in true })
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.validationMissingMandatoryProperty) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func show(_ scenario: Scenario) async {
        guard !changing else { return }
        changing = true; error = nil
        defer { changing = false }
        await service.configure(); paste.held = false
        await store.shutdown()
        service = PreviewTranscriber(); paste = PreviewPaste()
        store = Self.makeStore(service, paste, dictionaryStorage)
        await store.dictionary?.load()
        store.refreshPermissions(); store.configureShortcutRegistration { _ in true }
        do {
            if scenario == .setup { return }
            store.warmUp()
            try await waitFor { store.modelState == .ready && store.canStart }
            if [.setupRemote, .setupText, .setupSpeech].contains(scenario) {
                store.advanceSetup(); store.advanceSetup()
                store.setRemoteApplication(.init(bundleID: "preview", name: "模拟远程工具"))
                if scenario != .setupRemote {
                    store.confirmSetupClipboardSync(true); store.advanceSetup()
                }
                if scenario == .setupSpeech {
                    store.startSetupTextTest(); store.handleGlobalShortcut()
                    try await waitFor { store.canStart }
                    store.confirmSetupTrial(true); store.advanceSetup()
                }
                return
            }
            store.deferSetup()
            switch scenario {
            case .setup, .setupRemote, .setupText, .setupSpeech, .ready: break
            case .loading:
                await service.configure(held: .loading); store.warmUp()
            case .modelFailure:
                await service.configure(fails: true); store.warmUp()
                try await waitFor { store.phase == .failed }
            case .recording:
                store.beginRecording(); try await waitFor { store.phase == .recording }
            case .transcribing, .cancelling:
                await service.configure(held: .transcribing); store.importAudio(fixtureURL)
                try await waitFor { store.phase == .transcribing }
                if scenario == .cancelling {
                    await service.configure(held: .cancelling)
                    let cancellingStore = store
                    Task { await cancellingStore.cancel() }
                    try await waitFor { store.phase == .cancelling }
                }
            case .result, .empty:
                await service.configure(empty: scenario == .empty)
                store.importAudio(fixtureURL)
                try await waitFor { store.canStart && store.retainedAudio != nil }
            case .pasting, .failure, .cleanup:
                paste.held = scenario == .pasting
                if scenario == .failure {
                    paste.outcome = .failed("原目标输入框已失去焦点，文字已保留。请点选输入框，确认没有重复内容后，再手动重新粘贴。")
                } else if scenario == .cleanup {
                    paste.outcome = .sentWithCleanupFailure("粘贴已发出，但剪贴板恢复失败。请检查目标文字与剪贴板内容。")
                }
                store.handleGlobalShortcut(); try await waitFor { store.phase == .recording }
                store.finishRecording()
                try await waitFor { scenario == .pasting ? store.phase == .pasting : store.phase == .failed && store.canStart }
            }
        } catch { self.error = "状态驱动失败：\(scenario.rawValue)。请重新选择并检查开发工具。" }
    }
}

@MainActor private struct InterfaceGallery: View {
    @ObservedObject var controller: GalleryController
    @State private var scenario: Scenario = .ready
    @State private var dark = true
    @State private var compact = true
    @State private var short = true
    @State private var contentSize = CGSize.zero

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("主窗口状态检查 · 模拟数据").font(.headline)
                Text("真实界面与状态机；录音、识别、粘贴及保留录音均使用内存替身。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("状态", selection: $scenario) {
                        ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 190).disabled(controller.changing)
                    Button("上一个") { step(-1) }.disabled(controller.changing)
                    Button("下一个") { step(1) }.disabled(controller.changing)
                    Toggle("深色", isOn: $dark)
                    Toggle("最小宽度", isOn: $compact)
                    Spacer()
                }
                HStack {
                    Toggle("最小高度", isOn: $short)
                    Text("主界面实测：\(Int(contentSize.width)) × \(Int(contentSize.height)) 点")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("正式窗口预览") { controller.showWorkspaceWindow(compact: compact) }
                    Button("导出演示图") { controller.exportCurrentView() }
                }
                Text(controller.exportStatus).font(.caption).foregroundStyle(.secondary)
                if let error = controller.error { Text(error).foregroundStyle(.red) }
            }.padding(16)
            Divider()
            ContentView(store: controller.store).id(ObjectIdentifier(controller.store))
                .frame(height: short ? 600 : 760)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
        }
        .frame(width: compact ? 660 : 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: scenario) { _, value in Task { await controller.show(value) } }
        .onChange(of: dark) { _, value in NSApp.appearance = NSAppearance(named: value ? .darkAqua : .aqua) }
        .task {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            await controller.show(scenario)
        }
    }

    private func step(_ offset: Int) {
        let cases = Scenario.allCases
        guard let index = cases.firstIndex(of: scenario) else { return }
        scenario = cases[(index + offset + cases.count) % cases.count]
    }
}

@MainActor private struct SettingsGallery: View {
    @ObservedObject var controller: GalleryController
    @Environment(\.openWindow) private var openWindow
    @State private var dark = true
    @State private var loginFailure = false
    @State private var dictionaryFailure = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("设置检查 · 模拟登录项与内存词典").font(.headline)
                HStack {
                    Toggle("深色", isOn: $dark)
                        .onChange(of: dark) { _, value in NSApp.appearance = NSAppearance(named: value ? .darkAqua : .aqua) }
                    Toggle("登录失败", isOn: $loginFailure)
                        .onChange(of: loginFailure) { _, value in controller.loginService.fails = value }
                    Toggle("词典保存失败", isOn: $dictionaryFailure)
                        .onChange(of: dictionaryFailure) { _, value in Task { await controller.dictionaryStorage.setFailure(value) } }
                    Button("导出演示图") { controller.exportCurrentView() }
                }
                Text(controller.exportStatus).font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            PreferencesView(store: controller.store, loginItem: controller.loginItem) {
                openWindow(id: "interface-check")
            }
        }
        .onAppear { dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    }
}

@main private struct InterfaceCheck: App {
    @StateObject private var controller = GalleryController()
    var body: some Scene {
        Window("VoxInk 主窗口检查", id: "interface-check") { InterfaceGallery(controller: controller) }
            .windowResizability(.contentSize)
        Settings { SettingsGallery(controller: controller) }
            .commands {
                CommandGroup(after: .saveItem) {
                    Button("导出当前演示图") { controller.exportCurrentView() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
    }
}
