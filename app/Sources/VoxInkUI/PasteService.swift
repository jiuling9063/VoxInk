import VoxInkCore
import Foundation

@MainActor public protocol PasteService: AnyObject {
    var accessibilityGranted: Bool { get }
    func requestAccessibility() -> Bool
    func captureTarget() -> PasteTarget?
    func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome
    func cancel()
}

extension PasteCoordinator: PasteService {}
