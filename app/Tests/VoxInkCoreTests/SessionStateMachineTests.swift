import Foundation
import Testing
@testable import VoxInkCore

@Test
func toggleCreatesOnlyOneActiveSession() async {
    let machine = SessionStateMachine()

    #expect((await machine.handle(.modelReady)).wasApplied)
    let recording = await machine.handle(.toggleRecording)
    let sessionID = try! #require(recording.snapshot.sessionID)
    #expect(recording.snapshot.phase == .recording)

    let finalizing = await machine.handle(.toggleRecording)
    #expect(finalizing.snapshot.phase == .finalizing)
    #expect(finalizing.snapshot.sessionID == sessionID)

    let duplicateToggle = await machine.handle(.toggleRecording)
    #expect(!duplicateToggle.wasApplied)
    #expect(duplicateToggle.snapshot.sessionID == sessionID)
}

@Test
func staleCallbackCannotAdvanceCurrentSession() async {
    let machine = SessionStateMachine(initialPhase: .ready)
    let recording = await machine.handle(.toggleRecording)
    let activeID = try! #require(recording.snapshot.sessionID)

    let staleResult = await machine.handle(.finalizationFinished(sessionID: UUID()))
    #expect(!staleResult.wasApplied)
    #expect(staleResult.snapshot.phase == .recording)
    #expect(staleResult.snapshot.sessionID == activeID)
}

@Test
func cancellationReturnsToReadyAndClearsSession() async {
    let machine = SessionStateMachine(initialPhase: .ready)
    let recording = await machine.handle(.toggleRecording)
    let sessionID = try! #require(recording.snapshot.sessionID)

    #expect((await machine.handle(.cancel(sessionID: sessionID))).snapshot.phase == .cancelling)
    let ready = await machine.handle(.cancellationFinished(sessionID: sessionID))
    #expect(ready.snapshot.phase == .ready)
    #expect(ready.snapshot.sessionID == nil)
}

@Test
func transcriptionRetryIsLimitedToOne() async {
    let machine = SessionStateMachine(initialPhase: .ready)
    let recording = await machine.handle(.toggleRecording)
    let sessionID = try! #require(recording.snapshot.sessionID)

    _ = await machine.handle(.toggleRecording)
    _ = await machine.handle(.finalizationFinished(sessionID: sessionID))
    _ = await machine.handle(.transcriptionFailed(sessionID: sessionID))

    let retry = await machine.handle(.retryTranscription(sessionID: sessionID))
    #expect(retry.wasApplied)
    #expect(retry.snapshot.retryCount == 1)
    #expect(retry.snapshot.phase == .transcribing)

    _ = await machine.handle(.transcriptionFailed(sessionID: sessionID))
    let duplicateRetry = await machine.handle(.retryTranscription(sessionID: sessionID))
    #expect(!duplicateRetry.wasApplied)
    #expect(duplicateRetry.snapshot.phase == .recoverable)
}

@Test
func pasteCanOnlyBeIssuedOncePerSession() async {
    let machine = SessionStateMachine(initialPhase: .ready)
    let recording = await machine.handle(.toggleRecording)
    let sessionID = try! #require(recording.snapshot.sessionID)

    _ = await machine.handle(.toggleRecording)
    _ = await machine.handle(.finalizationFinished(sessionID: sessionID))
    _ = await machine.handle(.transcriptionSucceeded(sessionID: sessionID))
    _ = await machine.handle(.calibrationFinished(sessionID: sessionID, shouldPolish: false))
    _ = await machine.handle(.targetResolved(sessionID: sessionID, canPaste: true))

    let issued = await machine.handle(.pasteIssued(sessionID: sessionID))
    #expect(issued.wasApplied)
    #expect(issued.snapshot.phase == .restoring)
    #expect(issued.snapshot.pasteWasIssued)

    let duplicate = await machine.handle(.pasteIssued(sessionID: sessionID))
    #expect(!duplicate.wasApplied)
    #expect(duplicate.snapshot.phase == .restoring)
    #expect(duplicate.snapshot.pasteWasIssued)
}
