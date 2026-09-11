import AppKit
import Combine
import Foundation
import VoxInkCore

@MainActor public final class AppStore: ObservableObject {
    public enum Phase: Equatable { case ready, loading, recording, transcribing, pasting, cancelling, failed }
    @Published public private(set) var phase: Phase = .ready
    @Published public private(set) var status = "准备就绪"
    @Published public private(set) var transcript = ""
    @Published public private(set) var rawTranscript = ""
    @Published public private(set) var polishingEnabled = false
    @Published public private(set) var polishedPreview: String?
    @Published public private(set) var polishMessage = ""
    @Published public private(set) var isPolishing = false
    private let polishingService: any PolishingService
    private var polishTask: Task<Void, Never>?
    private var polishGeneration = UUID()

    public func setPolishingEnabled(_ enabled: Bool) {
        polishingEnabled = enabled
        preferences?.set(enabled, forKey: "polishingEnabled")
        discardPolish()
    }

    public func previewPolish() {
        guard polishingEnabled, canStart, !transcript.isEmpty else { return }
        discardPolish()
        let token = polishGeneration
        let source = transcript
        isPolishing = true
        polishMessage = "正在本机润色…"
        polishTask = Task { [weak self, polishingService] in
            do {
                let result = try await polishingService.polish(source)
                guard let self, self.polishGeneration == token, self.transcript == source else { return }
                self.polishedPreview = result.accepted ? result.text : nil
                self.polishMessage = result.accepted ? "润色预览，请核对后复制；原文未改动。" : "结果未通过保真检查，已保留原文。"
                self.isPolishing = false
            } catch {
                guard let self, self.polishGeneration == token else { return }
                self.polishMessage = (error as? LocalPolishingService.Failure)?.errorDescription ?? "润色未完成，原文已保留。"
                self.isPolishing = false
            }
        }
    }

    public func discardPolish() {
        polishGeneration = UUID()
        polishTask?.cancel(); polishTask = nil
        isPolishing = false
        polishedPreview = nil
        polishMessage = ""
    }

    public func copyPolishedPreview() {
        guard canStart, polishingEnabled, let polishedPreview else { return }
        polishMessage = clipboardWriter(polishedPreview) ? "已复制整理结果" : "复制失败，请重试"
    }
    @Published private(set) var sessionHistory: [SessionTranscript] = []

    func copyHistory(_ entry: SessionTranscript) -> Bool {
        guard canStart, sessionHistory.contains(where: { $0.id == entry.id }) else { return false }
        return clipboardWriter(entry.text)
    }
    @Published public private(set) var conversionWarning: String?
    @Published public private(set) var elapsed: TimeInterval = 0
    @Published public private(set) var level: Float = 0
    @Published public private(set) var shortcutTargetName: String?
    @Published public private(set) var shortcutStatus = "快捷键尚未注册"
    @Published public private(set) var fixedTextTestArmed = false
    @Published public private(set) var shortcutMode: ShortcutMode
    @Published public private(set) var shortcutCombination: ShortcutCombination
    @Published public private(set) var shortcutAvailable = false
    @Published public private(set) var cancellationShortcutAvailable = false
    @Published public private(set) var microphoneAuthorization: MicrophoneAuthorization = .notDetermined
    @Published public private(set) var pastePermissionGranted = false
    @Published public private(set) var modelState: ModelState = .notLoaded
    @Published public private(set) var modelInstallationProgress: ModelInstallationProgress?
    @Published public private(set) var setupCompleted: Bool
    @Published public private(set) var recovery: RecoveryAction?
    @Published public private(set) var retainedAudio: RetainedAudio?
    @Published public private(set) var recoveryStorageWarning: String?
    private let audioRecovery: (any AudioRecoveryStorage)?
    private let clipboardWriter: @MainActor (String) -> Bool
    private let temporaryAudioJanitor: @Sendable () throws -> Void
    private var retainedTarget: PasteTarget?
    private var transcriptAudioID: UUID?
    private var retryingAudioID: UUID?
    private var maintenanceTask: Task<Void, Never>?
    private let preferences: UserDefaults?
    private let microphoneStatus: @MainActor () -> MicrophoneAuthorization
    private var registerShortcut: ((ShortcutCombination) -> Bool)?
    private var shortcutIsHeld = false
    private var holdRecording = false
    private let service: any TranscriptionService
    private let textProcessor = DeterministicTextProcessor.shared
    public let dictionary: UserDictionaryController?
    private let pasteService: any PasteService
    private var activeTarget: PasteTarget?
    private var lastTarget: PasteTarget?
    private var pasteOutcome: PasteOutcome?
    private let recorder: any AudioRecording
    private let audioPreparer: @Sendable (URL) async throws -> URL
    private let audioCleaner: @Sendable (URL) -> Void
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var audioOperation: Task<Void, Never>?
    private var cancellationTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    public var canStart: Bool { phase == .ready || phase == .failed }
    public var canCancel: Bool { phase == .loading || phase == .recording || phase == .transcribing || phase == .pasting }
    public var canPasteAgain: Bool { canStart && lastTarget != nil && !transcript.isEmpty }
    public var canRetryAudio: Bool { canStart && retainedAudio.map { $0.expiresAt > Date() } == true }
    public var repasteTargetName: String? { lastTarget?.name }
    public var canCompleteSetup: Bool {
        canStart && microphoneAuthorization == .authorized && pastePermissionGranted && modelState == .ready && shortcutAvailable
    }
    public var canChangeShortcut: Bool { canStart && !shortcutIsHeld }
    public var shortcutInstruction: String {
        shortcutMode.instruction.replacingOccurrences(of: "⌥ Space", with: shortcutCombination.title)
    }

    public init(
        polishingService: any PolishingService = LocalPolishingService(),
        service: any TranscriptionService = QwenTranscriptionService(),
        pasteService: any PasteService = PasteCoordinator(),
        recorder: any AudioRecording = AudioCapture(),
        preferences: UserDefaults? = .standard,
        microphoneStatus: @escaping @MainActor () -> MicrophoneAuthorization = MicrophoneAuthorization.current,
        audioPreparer: @escaping @Sendable (URL) async throws -> URL = { url in
            try await Task.detached { try AudioFilePreparation.prepare(url: url) }.value
        },
        audioCleaner: @escaping @Sendable (URL) -> Void = AudioFilePreparation.cleanup,
        audioRecovery: (any AudioRecoveryStorage)? = nil,
        temporaryAudioJanitor: @escaping @Sendable () throws -> Void = {},
        dictionary: UserDictionaryController? = nil,
        clipboardWriter: @escaping @MainActor (String) -> Bool = { text in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.service = service
        self.polishingService = polishingService
        self.pasteService = pasteService
        self.recorder = recorder
        self.preferences = preferences
        self.polishingEnabled = preferences?.bool(forKey: "polishingEnabled") ?? false
        self.microphoneStatus = microphoneStatus
        self.setupCompleted = preferences?.bool(forKey: "setupCompleted") ?? false
        self.shortcutMode = preferences?.string(forKey: "shortcutMode").flatMap(ShortcutMode.init(rawValue:)) ?? .holdToTalk
        self.shortcutCombination = preferences?.string(forKey: "shortcutCombination").flatMap(ShortcutCombination.init(rawValue:)) ?? .optionSpace
        self.audioPreparer = audioPreparer
        self.audioCleaner = audioCleaner
        self.audioRecovery = audioRecovery
        self.clipboardWriter = clipboardWriter
        self.temporaryAudioJanitor = temporaryAudioJanitor
        self.dictionary = dictionary
    }

    public func prepareForUse() {
        guard canStart else { return }
        let token = UUID(); generation = token
        phase = .loading; status = "正在检查未完成录音…"
        let task = Task {
            await dictionary?.load()
            guard generation == token else { return }
            do { try await Task.detached { [temporaryAudioJanitor] in try temporaryAudioJanitor() }.value }
            catch {
                guard generation == token else { return }
                recoveryStorageWarning = "过期临时录音未能清理，请检查磁盘访问权限。"
            }
            guard generation == token else { return }
            do {
                let record = try await audioRecovery?.latest()
                guard generation == token else { return }
                retainedAudio = record
            } catch {
                guard generation == token else { return }
                recoveryStorageWarning = "未能检查保留录音，请检查磁盘空间与访问权限。"
            }
            phase = .ready
            startRecoveryMaintenance()
            warmUp()
        }
        operation = task; audioOperation = task
    }

    private func startRecoveryMaintenance() {
        maintenanceTask?.cancel()
        guard audioRecovery != nil else { return }
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await self?.removeExpiredAudio()
                guard let janitor = self?.temporaryAudioJanitor else { return }
                do { try await Task.detached { try janitor() }.value }
                catch { self?.recoveryStorageWarning = "过期临时录音未能清理，请检查磁盘访问权限。" }
            }
        }
    }

    func removeExpiredAudio() async {
        guard let record = retainedAudio, record.expiresAt <= Date() else { return }
        if retryingAudioID == record.id { await cancel(); return }
        // Block new operations until deletion finishes; retry never extends the deadline.
        let previousPhase = phase
        let blockedIdle = canStart
        let token = generation
        if blockedIdle { phase = .loading }
        await discardAudio(record.id)
        if blockedIdle, generation == token, phase == .loading { phase = previousPhase }
    }

    @discardableResult private func discardAudio(_ id: UUID) async -> Bool {
        do {
            try await audioRecovery?.discard(id)
            if retainedAudio?.id == id { retainedAudio = nil; retainedTarget = nil }
            if transcriptAudioID == id { transcriptAudioID = nil }
            recoveryStorageWarning = nil
            return true
        } catch {
            recoveryStorageWarning = "保留录音未能删除，请检查磁盘访问权限后再次删除。"
            return false
        }
    }

    public func deleteRetainedAudio() {
        guard canStart, let record = retainedAudio else { return }
        let token = UUID(); generation = token
        phase = .loading; status = "正在删除保留录音…"
        let task = Task {
            let deleted = await discardAudio(record.id)
            guard generation == token else { return }
            phase = deleted ? .ready : .failed
            status = deleted ? "保留录音已删除" : "录音删除失败，请重试"
        }
        operation = task; audioOperation = task
    }

    public func retryRetainedAudio() {
        guard canRetryAudio, let record = retainedAudio else { return }
        let token = UUID(); generation = token
        let target = retainedTarget
        activeTarget = nil; lastTarget = nil; pasteOutcome = nil
        retryingAudioID = record.id
        phase = .transcribing; status = "正在重试识别…"
        let task = Task {
            defer { if retryingAudioID == record.id { retryingAudioID = nil } }
            await service.cancel()
            guard generation == token, !Task.isCancelled else { return }
            modelState = .notLoaded
            let retention = await recognize(record.url, token: token)
            guard generation == token else { return }
            if retention == .transcript, phase == .ready {
                transcriptAudioID = record.id; lastTarget = target
                status = "重试识别完成，请复制或手动重新粘贴"
            } else if retention == .discard { await discardAudio(record.id) }
        }
        operation = task; audioOperation = task
    }

    public func shutdown() async {
        discardPolish()
        maintenanceTask?.cancel(); maintenanceTask = nil
        if canCancel || phase == .cancelling {
            let keepPrevious = retryingAudioID == nil && phase != .transcribing && phase != .recording && phase != .pasting
            await cancel(preserveRetainedAudio: keepPrevious)
        }
        else { await service.cancel() }
        await dictionary?.waitForPendingChanges()
    }

    public func refreshPermissions() {
        microphoneAuthorization = microphoneStatus()
        pastePermissionGranted = pasteService.accessibilityGranted
    }

    public func completeSetup() {
        guard canCompleteSetup else { return }
        setupCompleted = true
        preferences?.set(true, forKey: "setupCompleted")
    }

    public func showSetup() {
        setupCompleted = false
        preferences?.set(false, forKey: "setupCompleted")
        refreshPermissions()
    }

    public func requestMicrophonePermission() {
        guard canStart else { return }
        let token = UUID(); generation = token
        phase = .loading; recovery = nil; status = "正在检查麦克风权限…"
        operation = Task {
            guard generation == token, !Task.isCancelled else { return }
            let allowed = await recorder.requestPermission()
            guard generation == token else { return }
            refreshPermissions()
            if allowed { phase = .ready; status = "麦克风已允许，按快捷键或点击录音时才会采集声音。" }
            else { fail("麦克风尚未允许，请在系统设置中开启。", recovery: .microphone) }
        }
    }

    public func openSystemSettings() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            status = "无法打开系统设置，请从苹果菜单手动打开。"
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }

    public func warmUp() { prepareModel(allowDownload: false) }
    public func installModel() { prepareModel(allowDownload: true) }

    private func prepareModel(allowDownload: Bool) {
        guard canStart else { return }
        pasteOutcome = nil; recovery = nil
        let token = UUID(); generation = token
        phase = .loading; modelState = .loading; status = "正在校验并加载本地模型…"
        modelInstallationProgress = nil
        let report: @Sendable (ModelInstallationProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.phase == .loading else { return }
                self.modelInstallationProgress = progress
                self.status = progress.title
            }
        }
        operation = Task {
            guard generation == token, !Task.isCancelled else { return }
            do {
                try await service.prepare(allowDownload: allowDownload, progress: report)
                guard generation == token else { return }
                modelInstallationProgress = nil
                modelState = .ready; phase = .ready; status = "准备就绪 · 本地模型已加载"
            } catch let error as ModelInstallationError {
                guard generation == token else { return }
                failModelInstallation(error)
            } catch {
                guard generation == token else { return }
                modelInstallationProgress = nil
                modelState = allowDownload ? .needsDownload : .failed
                fail(allowDownload ? "模型安装未完成，请检查网络与可用磁盘空间后继续。已保留下载进度。" : "模型加载失败，请检查本地模型后重试。",
                    recovery: allowDownload ? .installModel : .reloadModel)
            }
        }
    }

    public func beginRecording() { holdRecording = false; beginRecording(target: nil) }

    private func beginRecording(target: PasteTarget?) {
        guard canStart else { return }
        activeTarget = target; lastTarget = nil; pasteOutcome = nil; recovery = nil
        shortcutTargetName = target?.name
        let token = UUID(); generation = token
        phase = .loading; status = "正在检查麦克风权限…"
        operation = Task {
            guard generation == token, !Task.isCancelled else { return }
            let allowed = await recorder.requestPermission()
            guard generation == token else { return }
            microphoneAuthorization = allowed ? .authorized : microphoneStatus()
            guard allowed else { fail("请在系统设置 → 隐私与安全 → 麦克风中允许语落 VoxInk。", recovery: .microphone); return }
            do {
                try recorder.start()
                elapsed = 0; level = 0
                phase = .recording
                status = holdRecording ? "正在录音 · 松开快捷键后识别并写入"
                    : (target != nil ? "正在录音 · 再按快捷键结束并写入" : "正在录音 · 最长 60 秒")
                meterTask = Task {
                    while !Task.isCancelled, generation == token, phase == .recording {
                        let sample = recorder.sample()
                        elapsed = sample.elapsed; level = sample.level
                        if elapsed >= 60 || !recorder.isRecording { finishRecording(); return }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            } catch { fail("无法开始录音，请检查麦克风是否可用。", recovery: .recordAgain) }
        }
    }

    public func finishRecording() {
        guard phase == .recording else { return }
        holdRecording = false
        meterTask?.cancel(); meterTask = nil
        do {
            let url = try recorder.stop()
            let token = generation
            phase = .transcribing; status = "正在识别…"
            let task = Task {
                guard generation == token, !Task.isCancelled else { audioCleaner(url); return }
                await transcribePrepared(url)
            }
            operation = task
            audioOperation = task
        } catch { recorder.cancel(); fail("录音未保存成功，请重试。", recovery: .recordAgain) }
    }

    public func importAudio(_ url: URL) {
        guard canStart else { return }
        activeTarget = nil; lastTarget = nil; shortcutTargetName = nil; pasteOutcome = nil; recovery = nil
        let token = UUID(); generation = token
        phase = .loading; status = "正在准备音频…"
        let task = Task {
            guard generation == token, !Task.isCancelled else { return }
            do {
                let prepared = try await audioPreparer(url)
                guard generation == token else { audioCleaner(prepared); return }
                await transcribePrepared(prepared)
            } catch {
                guard generation == token else { return }
                fail("音频无法读取或超过 60 秒，请选择有效的短音频。", recovery: .chooseAudio)
            }
        }
        operation = task
        audioOperation = task
    }

    func transcribePrepared(_ url: URL) async {
        let token = generation
        defer { audioCleaner(url) }
        phase = .transcribing
        if let previous = retainedAudio {
            let deleted = await discardAudio(previous.id)
            guard generation == token else { return }
            guard deleted else {
                fail("请先删除上一条保留录音，再开始新的识别。", recovery: .recordAgain)
                return
            }
        }
        transcriptAudioID = nil
        let target = activeTarget
        let retention = await recognize(url, token: token)
        guard retention != .discard, generation == token, let audioRecovery else { return }
        let finalPhase = phase
        let finalStatus = status
        phase = .transcribing
        do {
            let record = try await audioRecovery.save(url)
            guard generation == token, !Task.isCancelled else {
                if !(await discardAudio(record.id)) { retainedAudio = record }
                return
            }
            retainedAudio = record; retainedTarget = target
            transcriptAudioID = retention == .transcript ? record.id : nil
            recoveryStorageWarning = nil
        } catch {
            guard generation == token else { return }
            recoveryStorageWarning = "录音未能保留，无法重试；请检查磁盘空间与访问权限。"
        }
        phase = finalPhase; status = finalStatus
    }

    private enum RecognitionRetention { case discard, audio, transcript }

    // Keep unrecognized audio separate from the previous transcript.
    private func recognize(_ url: URL, token: UUID) async -> RecognitionRetention {
        let dictionarySnapshot = dictionary?.rules ?? .empty
        let dictionaryUnavailable = dictionary != nil && dictionary?.isReady != true
        phase = .transcribing; recovery = nil; status = "正在识别 · 首次使用可能需要加载模型…"
        do {
            let raw = try await service.transcribe(url: url)
            guard generation == token else { return .discard }
            modelState = .ready
            let converted = textProcessor.process(raw, dictionary: dictionarySnapshot)
            let text = converted.text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail("没有识别到文字，请重试。", recovery: .recordAgain); return .audio
            }
            rawTranscript = raw
            let warnings = [converted.warning, dictionaryUnavailable ? "词典暂不可用，本次使用基础文字规则" : nil].compactMap { $0 }
            conversionWarning = warnings.isEmpty ? nil : warnings.joined(separator: "；")
            transcript = text
            discardPolish()
            sessionHistory.insert(SessionTranscript(text: text, date: Date()), at: 0)
            if let target = activeTarget {
                lastTarget = target
                await deliver(text, to: target, token: token)
                switch pasteOutcome {
                case .sent, .sentWithCleanupFailure, .cancelledAfterSend: return .discard
                default: return .transcript
                }
            } else { phase = .ready; status = "识别完成" }
            return .transcript
        } catch let error as ModelInstallationError {
            guard generation == token else { return .discard }
            failModelInstallation(error)
        } catch QwenTranscriptionService.ServiceError.noSpeech {
            guard generation == token else { return .discard }
            activeTarget = nil
            phase = .ready
            status = "没有检测到有效音频，请检查麦克风或重新录音。未写入文字。"
            return .discard
        } catch is SpeechActivityError {
            guard generation == token else { return .discard }
            fail("语音检测暂不可用，请重试或重新录音。", recovery: .recordAgain)
        } catch QwenTranscriptionService.ServiceError.noSpeechDetected {
            guard generation == token else { return .discard }
            activeTarget = nil
            phase = .ready
            status = "没有检测到清晰语音，未写入文字。可重试或删除本次录音。"
        } catch {
            guard generation == token else { return .discard }
            modelState = .failed
            fail("识别失败。可重试识别，或重新加载模型。", recovery: .reloadModel)
        }
        return .audio
    }

    public func cancel(preserveRetainedAudio: Bool = false) async {
        if let cancellationTask {
            await cancellationTask.value
            return
        }
        let preparingModel = phase == .loading && modelState == .loading
        let pendingModelOperation = preparingModel ? operation : nil
        generation = UUID()
        holdRecording = false
        pasteService.cancel()
        let pendingAudioOperation = audioOperation
        operation?.cancel(); operation = nil
        audioOperation = nil
        meterTask?.cancel(); meterTask = nil
        recorder.cancel(); level = 0
        phase = .cancelling; recovery = nil; status = "正在取消…"
        let task = Task { [service] in
            await service.cancel()
            await pendingModelOperation?.value
            await pendingAudioOperation?.value
        }
        cancellationTask = task
        await task.value
        if !preserveRetainedAudio, let record = retainedAudio { await discardAudio(record.id) }
        modelState = .notLoaded
        modelInstallationProgress = nil
        cancellationTask = nil
        activeTarget = nil
        switch pasteOutcome {
        case .failed(let message):
            recovery = .checkTarget
            phase = .failed
            status = message
        case .sentWithCleanupFailure(let message):
            recovery = .inspectClipboard
            phase = .failed
            status = message
        case .sent, .cancelledAfterSend:
            phase = .ready
            status = "粘贴按键已发出；取消未撤回文字，剪贴板清理已结束"
        case .cancelledBeforeSend, nil:
            phase = .ready
            status = preparingModel ? "已取消模型准备，可稍后继续。" : "已取消 · 未发出粘贴"
        }
    }

    public func copyResult() {
        guard canStart, !transcript.isEmpty else { return }
        guard clipboardWriter(transcript) else { status = "复制失败，请重试"; return }
        status = "已复制"
        guard let id = transcriptAudioID else { return }
        let token = UUID(); generation = token
        phase = .loading
        let task = Task {
            await discardAudio(id)
            guard generation == token else { return }
            phase = .ready
        }
        operation = task; audioOperation = task
    }

    private func fail(_ message: String, recovery: RecoveryAction) {
        self.recovery = recovery; phase = .failed; status = message
    }

    private func failModelInstallation(_ error: ModelInstallationError) {
        modelInstallationProgress = nil
        let needsInspection = error == .invalidManifest || error == .unsafePath
        modelState = needsInspection ? .failed : .needsDownload
        fail(error.localizedDescription, recovery: needsInspection ? .checkInstallation : .installModel)
    }

    public func setShortcutStatus(_ message: String) { shortcutStatus = message }
    public func setCancellationShortcutAvailable(_ available: Bool) { cancellationShortcutAvailable = available }

    public func configureShortcutRegistration(_ registration: @escaping (ShortcutCombination) -> Bool) {
        registerShortcut = registration
        shortcutAvailable = registration(shortcutCombination)
        shortcutStatus = shortcutAvailable ? "\(shortcutCombination.title) 已就绪" : "快捷键注册失败，请在设置中选择其他组合"
    }

    public func setShortcutCombination(_ combination: ShortcutCombination) {
        guard canChangeShortcut, let registerShortcut else { return }
        guard registerShortcut(combination) else {
            shortcutStatus = shortcutAvailable
                ? "\(combination.title) 不可用，仍使用 \(shortcutCombination.title)"
                : "\(combination.title) 不可用，请选择其他组合"
            return
        }
        shortcutCombination = combination
        shortcutAvailable = true
        shortcutStatus = "\(combination.title) 已就绪"
        preferences?.set(combination.rawValue, forKey: "shortcutCombination")
    }

    public func setShortcutMode(_ mode: ShortcutMode) {
        guard canChangeShortcut else { return }
        shortcutMode = mode
        preferences?.set(mode.rawValue, forKey: "shortcutMode")
    }

    public func handleShortcutPressed() {
        guard !shortcutIsHeld else { return }
        shortcutIsHeld = true
        if fixedTextTestArmed { handleGlobalShortcut(); return }
        if shortcutMode == .holdToTalk {
            guard canStart else { return }
            holdRecording = true
        }
        handleGlobalShortcut()
        if phase == .failed { holdRecording = false }
    }

    public func handleShortcutReleased() {
        shortcutIsHeld = false
        guard holdRecording else { return }
        if phase == .recording, recorder.sample().elapsed >= 0.2 {
            finishRecording()
        } else if phase == .loading || phase == .recording {
            // Invalidate pending permission work so a quick release cannot start a late recording.
            generation = UUID()
            operation?.cancel(); operation = nil
            meterTask?.cancel(); meterTask = nil
            recorder.cancel()
            holdRecording = false; activeTarget = nil; level = 0
            phase = .ready; status = "按住时间过短，未识别或写入文字"
        }
    }

    public func requestPastePermission() {
        guard canStart else { return }
        status = pasteService.requestAccessibility()
            ? "辅助功能已允许，可切换到输入框按 \(shortcutCombination.title)"
            : "请在系统设置 → 隐私与安全性 → 辅助功能中允许语落 VoxInk"
        refreshPermissions()
    }

    public func armFixedTextTest() {
        guard canStart else { return }
        fixedTextTestArmed.toggle()
        recovery = nil
        status = fixedTextTestArmed ? "固定文字测试已就绪：切换到输入框按 \(shortcutCombination.title)" : "已关闭固定文字测试"
    }

    public func scheduleFixedTextTest(after delay: Duration = .seconds(3)) {
        guard canStart else { return }
        let token = UUID(); generation = token
        fixedTextTestArmed = false; pasteOutcome = nil; recovery = nil
        activeTarget = nil; lastTarget = nil; shortcutTargetName = nil
        phase = .loading; status = "请切换到输入框，3 秒后写入固定测试文字…"
        operation = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            guard generation == token, !Task.isCancelled else { return }
            phase = .ready
            fixedTextTestArmed = true
            handleGlobalShortcut()
        }
    }

    public func handleGlobalShortcut() {
        if phase == .recording { finishRecording(); return }
        guard canStart else { return }
        guard let target = pasteService.captureTarget() else {
            fail("请先切换到目标应用的输入框，再按 \(shortcutCombination.title)", recovery: .checkTarget)
            return
        }
        shortcutTargetName = target.name
        pastePermissionGranted = pasteService.accessibilityGranted
        guard pastePermissionGranted else {
            fail("文字写入需要辅助功能权限，请在语落窗口点击“允许文字写入”", recovery: .pastePermission)
            return
        }
        if fixedTextTestArmed {
            fixedTextTestArmed = false
            let token = UUID(); generation = token
            activeTarget = target; lastTarget = target; pasteOutcome = nil; recovery = nil
            transcriptAudioID = nil
            transcript = "语落固定文字测试：中文、English、123。"
            rawTranscript = transcript; conversionWarning = nil
            phase = .pasting; status = "正在准备写入 \(target.name)…"
            let text = transcript
            let task = Task {
                guard generation == token, !Task.isCancelled else { return }
                await deliver(text, to: target, token: token)
            }
            operation = task; audioOperation = task
        } else { beginRecording(target: target) }
    }

    public func pasteAgain() {
        guard canPasteAgain, let target = lastTarget else { return }
        let token = UUID(); generation = token
        activeTarget = target; shortcutTargetName = target.name; pasteOutcome = nil; recovery = nil
        phase = .pasting; status = "正在准备写入 \(target.name)…"
        let text = transcript
        let task = Task {
            guard generation == token, !Task.isCancelled else { return }
            await deliver(text, to: target, token: token)
        }
        operation = task; audioOperation = task
    }

    private func deliver(_ text: String, to target: PasteTarget, token: UUID) async {
        phase = .pasting; status = "正在写入 \(target.name) 并清理剪贴板…"
        let outcome = await pasteService.paste(text: text, to: target, sessionID: token)
        pasteOutcome = outcome
        guard generation == token else { return }
        switch outcome {
        case .sent, .sentWithCleanupFailure, .cancelledAfterSend:
            if let id = transcriptAudioID { await discardAudio(id) }
            guard generation == token else { return }
        default: break
        }
        activeTarget = nil
        switch outcome {
        case .failed: phase = .failed; recovery = .checkTarget
        case .sentWithCleanupFailure: phase = .failed; recovery = .inspectClipboard
        default: phase = .ready; recovery = nil
        }
        status = outcome.message
    }
}
