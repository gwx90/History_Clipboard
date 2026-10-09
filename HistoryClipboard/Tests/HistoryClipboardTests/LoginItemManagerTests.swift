import Foundation
import ServiceManagement
import XCTest
@testable import HistoryClipboard

final class LoginItemManagerTests: XCTestCase {
    @MainActor
    private func withDefaults(_ body: @MainActor (UserDefaults) throws -> Void) throws {
        let suite = "HistoryClipboardLoginTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @MainActor
    func testDefaultRegistrationOnlyRunsOnce() throws {
        try withDefaults { defaults in
            var status: SMAppService.Status = .notRegistered
            var registrations = 0
            let manager = LoginItemManager(defaults: defaults, statusProvider: { status },
                register: { registrations += 1; status = .enabled }, unregister: { status = .notRegistered })
            manager.prepareDefaultRegistration()
            manager.prepareDefaultRegistration()
            XCTAssertEqual(registrations, 1)
            XCTAssertTrue(manager.isEnabled)
        }
    }

    @MainActor
    func testDisabledUserChoiceIsNotOverriddenOnNextLaunch() throws {
        try withDefaults { defaults in
            var status: SMAppService.Status = .enabled
            var registrations = 0
            var unregisters = 0
            let manager = LoginItemManager(defaults: defaults, statusProvider: { status }, register: { registrations += 1 },
                unregister: { unregisters += 1; status = .notRegistered })
            manager.setEnabled(false)
            let nextLaunch = LoginItemManager(defaults: defaults, statusProvider: { status },
                register: { registrations += 1 }, unregister: { })
            nextLaunch.prepareDefaultRegistration()
            XCTAssertEqual(unregisters, 1)
            XCTAssertEqual(registrations, 0)
            XCTAssertFalse(nextLaunch.isEnabled)
        }
    }

    @MainActor
    func testAwaitingApprovalDoesNotReregister() throws {
        try withDefaults { defaults in
            var registrations = 0
            let manager = LoginItemManager(defaults: defaults, statusProvider: { .requiresApproval },
                register: { registrations += 1 }, unregister: { })
            manager.prepareDefaultRegistration()
            manager.setEnabled(true)
            XCTAssertEqual(registrations, 0)
            XCTAssertTrue(manager.isEnabled)
            XCTAssertTrue(manager.statusDescription.contains("等待"))
        }
    }

    @MainActor
    func testRegistrationFailureIsVisibleAndNotRepeatedAutomatically() throws {
        try withDefaults { defaults in
            var registrations = 0
            let manager = LoginItemManager(defaults: defaults, statusProvider: { .notRegistered },
                register: { registrations += 1; throw CocoaError(.fileWriteNoPermission) }, unregister: { })
            manager.prepareDefaultRegistration()
            XCTAssertNotNil(manager.errorMessage)
            XCTAssertFalse(manager.isEnabled)
            manager.prepareDefaultRegistration()
            XCTAssertEqual(registrations, 1)
        }
    }

    @MainActor
    func testRefreshReadsSystemStatus() throws {
        try withDefaults { defaults in
            var status: SMAppService.Status = .enabled
            let manager = LoginItemManager(defaults: defaults, statusProvider: { status }, register: { }, unregister: { })
            status = .requiresApproval
            manager.refreshStatus()
            XCTAssertEqual(manager.status, .requiresApproval)
        }
    }
}
