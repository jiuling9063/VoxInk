import Testing
@testable import VoxInkUI

@MainActor private final class LoginServiceStub: LoginItemService {
    enum Failure: Error { case registration }
    var state: LoginItemState = .disabled
    var fail = false
    var requiresApproval = false
    var enables = 0
    var disables = 0
    func enable() throws {
        enables += 1
        if fail { throw Failure.registration }
        state = requiresApproval ? .requiresApproval : .enabled
    }
    func disable() async throws {
        disables += 1
        if fail { throw Failure.registration }
        state = .disabled
    }
    func openSettings() {}
}

@MainActor struct LoginItemControllerTests {
    @Test func readsSystemStateWithoutRegisteringOnInitialization() {
        let service = LoginServiceStub(); service.state = .enabled
        let controller = LoginItemController(service: service)
        #expect(controller.state == .enabled)
        #expect(service.enables == 0)
    }
    @Test func failedRegistrationDoesNotShowEnabled() async {
        let service = LoginServiceStub(); service.fail = true
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        #expect(controller.state == .disabled)
        #expect(controller.errorMessage != nil)
        #expect(!controller.isUpdating)
    }
    @Test func approvalIsDistinctAndDisablingUnregisters() async {
        let service = LoginServiceStub(); service.requiresApproval = true
        let controller = LoginItemController(service: service)
        await controller.setEnabled(true)
        #expect(controller.state == .requiresApproval)
        #expect(controller.errorMessage == nil)
        await controller.setEnabled(false)
        #expect(service.disables == 1)
        #expect(controller.state == .disabled)
    }
    @Test func refreshReflectsExternalChanges() {
        let service = LoginServiceStub()
        let controller = LoginItemController(service: service)
        service.state = .requiresApproval
        controller.refresh()
        #expect(controller.state == .requiresApproval)
    }
}
