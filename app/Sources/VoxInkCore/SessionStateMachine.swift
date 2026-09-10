import Foundation

public enum SessionPhase: String, Equatable, Sendable {
    case warming
    case ready
    case recording
    case cancelling
    case finalizing
    case transcribing
    case calibrating
    case polishing
    case targeting
    case pasting
    case restoring
    case copied
    case recoverable
    case unavailable
}

public struct SessionSnapshot: Equatable, Sendable {
    public let phase: SessionPhase
    public let sessionID: UUID?
    public let retryCount: Int
    public let pasteWasIssued: Bool

    public init(
        phase: SessionPhase,
        sessionID: UUID?,
        retryCount: Int,
        pasteWasIssued: Bool
    ) {
        self.phase = phase
        self.sessionID = sessionID
        self.retryCount = retryCount
        self.pasteWasIssued = pasteWasIssued
    }
}

public enum SessionEvent: Equatable, Sendable {
    case modelReady
    case modelUnavailable
    case toggleRecording
    case cancel(sessionID: UUID)
    case cancellationFinished(sessionID: UUID)
    case finalizationFinished(sessionID: UUID)
    case transcriptionSucceeded(sessionID: UUID)
    case transcriptionFailed(sessionID: UUID)
    case retryTranscription(sessionID: UUID)
    case abandonRecovery(sessionID: UUID)
    case calibrationFinished(sessionID: UUID, shouldPolish: Bool)
    case polishingFinished(sessionID: UUID)
    case targetResolved(sessionID: UUID, canPaste: Bool)
    case pasteIssued(sessionID: UUID)
    case sessionFinished(sessionID: UUID)
}

public enum SessionTransitionResult: Equatable, Sendable {
    case applied(SessionSnapshot)
    case ignored(SessionSnapshot)

    public var snapshot: SessionSnapshot {
        switch self {
        case .applied(let snapshot), .ignored(let snapshot):
            snapshot
        }
    }

    public var wasApplied: Bool {
        if case .applied = self {
            return true
        }
        return false
    }
}

public actor SessionStateMachine {
    private var phase: SessionPhase
    private var sessionID: UUID?
    private var retryCount = 0
    private var pasteWasIssued = false

    public init(initialPhase: SessionPhase = .warming) {
        phase = initialPhase
    }

    public func currentSnapshot() -> SessionSnapshot {
        snapshot()
    }

    @discardableResult
    public func handle(_ event: SessionEvent) -> SessionTransitionResult {
        switch event {
        case .modelReady where phase == .warming || phase == .unavailable:
            reset(to: .ready)

        case .modelUnavailable where phase == .warming || phase == .ready:
            reset(to: .unavailable)

        case .toggleRecording where phase == .ready:
            phase = .recording
            sessionID = UUID()
            retryCount = 0
            pasteWasIssued = false

        case .toggleRecording where phase == .recording:
            phase = .finalizing

        case .cancel(let id) where matches(id, phase: .recording):
            phase = .cancelling

        case .cancellationFinished(let id) where matches(id, phase: .cancelling):
            reset(to: .ready)

        case .finalizationFinished(let id) where matches(id, phase: .finalizing):
            phase = .transcribing

        case .transcriptionSucceeded(let id) where matches(id, phase: .transcribing):
            phase = .calibrating

        case .transcriptionFailed(let id) where matches(id, phase: .transcribing):
            phase = .recoverable

        case .retryTranscription(let id) where matches(id, phase: .recoverable) && retryCount == 0:
            retryCount = 1
            phase = .transcribing

        case .abandonRecovery(let id) where matches(id, phase: .recoverable):
            reset(to: .ready)

        case .calibrationFinished(let id, let shouldPolish) where matches(id, phase: .calibrating):
            phase = shouldPolish ? .polishing : .targeting

        case .polishingFinished(let id) where matches(id, phase: .polishing):
            phase = .targeting

        case .targetResolved(let id, let canPaste) where matches(id, phase: .targeting):
            phase = canPaste ? .pasting : .copied

        case .pasteIssued(let id) where matches(id, phase: .pasting) && !pasteWasIssued:
            pasteWasIssued = true
            phase = .restoring

        case .sessionFinished(let id)
            where matches(id, phases: [.cancelling, .restoring, .copied]):
            reset(to: .ready)

        default:
            return .ignored(snapshot())
        }

        return .applied(snapshot())
    }

    private func matches(_ id: UUID, phase expectedPhase: SessionPhase) -> Bool {
        sessionID == id && phase == expectedPhase
    }

    private func matches(_ id: UUID, phases expectedPhases: Set<SessionPhase>) -> Bool {
        sessionID == id && expectedPhases.contains(phase)
    }

    private func reset(to newPhase: SessionPhase) {
        phase = newPhase
        sessionID = nil
        retryCount = 0
        pasteWasIssued = false
    }

    private func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            phase: phase,
            sessionID: sessionID,
            retryCount: retryCount,
            pasteWasIssued: pasteWasIssued
        )
    }
}
