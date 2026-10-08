import XCTest
import ServiceManagement
@testable import Still

final class LoginItemTests: XCTestCase {
    @MainActor func testRegistrationApprovalExternalChangeAndRemoval() async {
        var systemStatus: SMAppService.Status = .notRegistered
        var registrations = 0
        var removals = 0
        let controller = LoginItemController(
            readStatus: { systemStatus },
            register: { registrations += 1; systemStatus = .requiresApproval },
            unregister: { removals += 1; systemStatus = .notRegistered }
        )
        XCTAssertFalse(controller.isRequested)
        XCTAssertEqual(registrations, 0) // Reading settings must not register the app.
        await controller.setEnabled(true)
        XCTAssertTrue(controller.isRequested)
        XCTAssertEqual(controller.status, .requiresApproval)
        await controller.setEnabled(true)
        XCTAssertEqual(registrations, 1)
        systemStatus = .enabled; controller.refresh()
        XCTAssertEqual(controller.status, .enabled)
        await controller.setEnabled(false)
        XCTAssertFalse(controller.isRequested)
        XCTAssertEqual(removals, 1)
        systemStatus = .enabled; controller.refresh()
        XCTAssertTrue(controller.isRequested)
    }

    @MainActor func testFailurePreservesActualSystemState() async {
        var systemStatus: SMAppService.Status = .notRegistered
        let controller = LoginItemController(
            readStatus: { systemStatus },
            register: { throw CocoaError(.fileWriteNoPermission) },
            unregister: { throw CocoaError(.fileWriteNoPermission) }
        )
        await controller.setEnabled(true)
        XCTAssertFalse(controller.isRequested)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isUpdating)
        systemStatus = .enabled; controller.refresh()
        await controller.setEnabled(false)
        XCTAssertTrue(controller.isRequested)
        XCTAssertNotNil(controller.errorMessage)
    }
}
