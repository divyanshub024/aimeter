import XCTest
@testable import AIMeter

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testInitialEnabledStatusTurnsToggleOn() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let controller = makeController(service: service)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.statusMessage)
    }

    func testInitialNotRegisteredStatusTurnsToggleOff() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let controller = makeController(service: service, shouldEnableByDefault: false)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.statusMessage)
    }

    func testDefaultStartupRegistersLoginItemOnce() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let userDefaults = testUserDefaults()

        let firstController = LaunchAtLoginController(service: service, userDefaults: userDefaults)
        let secondController = LaunchAtLoginController(service: service, userDefaults: userDefaults)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(firstController.isEnabled)
        XCTAssertTrue(secondController.isEnabled)
    }

    func testManualDisableIsRespectedAfterDefaultWasApplied() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        let userDefaults = testUserDefaults()
        let controller = LaunchAtLoginController(service: service, userDefaults: userDefaults)

        controller.setEnabled(false)
        let nextController = LaunchAtLoginController(service: service, userDefaults: userDefaults)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertFalse(nextController.isEnabled)
    }

    func testTurningOnRegistersLoginItemAndRefreshesState() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let controller = makeController(service: service, shouldEnableByDefault: false)

        controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.statusMessage)
    }

    func testTurningOffUnregistersLoginItemAndRefreshesState() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.statusAfterUnregister = .notRegistered
        let controller = makeController(service: service)

        controller.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.statusMessage)
    }

    func testRegistrationFailureRefreshesStateAndShowsError() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = FakeLoginItemError.failed
        let controller = makeController(service: service, shouldEnableByDefault: false)

        controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.statusMessage, "Could not update Login Items: Fake login item failure")
    }

    func testRequiresApprovalTurnsToggleOffAndShowsApprovalMessage() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let controller = makeController(service: service)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(
            controller.statusMessage,
            "Approve AIMeter in System Settings > General > Login Items to start it at login."
        )
    }

    private func makeController(
        service: FakeLaunchAtLoginService,
        shouldEnableByDefault: Bool = true
    ) -> LaunchAtLoginController {
        LaunchAtLoginController(
            service: service,
            userDefaults: testUserDefaults(),
            shouldEnableByDefault: shouldEnableByDefault
        )
    }

    private func testUserDefaults(function: String = #function) -> UserDefaults {
        let suiteName = "\(Self.self).\(function).\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var statusAfterUnregister: LaunchAtLoginStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1

        if let registerError {
            throw registerError
        }

        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func unregister() throws {
        unregisterCallCount += 1

        if let unregisterError {
            throw unregisterError
        }

        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
    }
}

private enum FakeLoginItemError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Fake login item failure"
    }
}
