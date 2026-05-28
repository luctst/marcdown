import Foundation
import ServiceManagement
import Testing

import MarcdownLaunchKit

// `@unchecked Sendable` is justified here: the fake is only mutated from
// main-actor test bodies, so there is no cross-actor mutation in practice.
final class FakeLaunchAtLoginBackend: LaunchAtLoginBackend, @unchecked Sendable {
    enum FakeBackendError: Error { case forced }

    var currentStatus: SMAppService.Status = .notRegistered
    var registerCallCount = 0
    var unregisterCallCount = 0
    var shouldThrowOnRegister = false
    var shouldThrowOnUnregister = false

    func register() throws {
        registerCallCount += 1
        if shouldThrowOnRegister { throw FakeBackendError.forced }
        currentStatus = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if shouldThrowOnUnregister { throw FakeBackendError.forced }
        currentStatus = .notRegistered
    }
}

@Suite("LaunchAtLoginController")
@MainActor
struct LaunchAtLoginControllerTests {
    @Test("mapStatus translates every SMAppService.Status case to the right State")
    func mapStatusTranslatesEveryCase() {
        #expect(LaunchAtLoginController.mapStatus(.enabled) == .enabled)
        #expect(LaunchAtLoginController.mapStatus(.notRegistered) == .disabled)
        #expect(LaunchAtLoginController.mapStatus(.requiresApproval) == .requiresApproval)
        #expect(LaunchAtLoginController.mapStatus(.notFound) == .unavailable)
    }

    @Test("setEnabled(true) calls register exactly once and ends in .enabled state")
    func setEnabledTrueRegistersAndEndsEnabled() {
        let fake = FakeLaunchAtLoginBackend()
        fake.currentStatus = .notRegistered
        let controller = LaunchAtLoginController(backend: fake)

        controller.setEnabled(true)

        #expect(fake.registerCallCount == 1)
        #expect(controller.state == .enabled)
    }

    @Test("setEnabled(false) calls unregister exactly once and ends in .disabled state")
    func setEnabledFalseUnregistersAndEndsDisabled() {
        let fake = FakeLaunchAtLoginBackend()
        fake.currentStatus = .enabled
        let controller = LaunchAtLoginController(backend: fake)

        controller.setEnabled(false)

        #expect(fake.unregisterCallCount == 1)
        #expect(controller.state == .disabled)
    }

    @Test("register() throwing leaves state .disabled and does not propagate")
    func registerThrowingDoesNotPropagateAndLeavesDisabled() {
        let fake = FakeLaunchAtLoginBackend()
        fake.currentStatus = .notRegistered
        fake.shouldThrowOnRegister = true
        let controller = LaunchAtLoginController(backend: fake)

        controller.setEnabled(true)

        #expect(fake.registerCallCount == 1)
        #expect(controller.state == .disabled)
    }

    @Test("registerOnFirstLaunchSilently calls register exactly once (happy path)")
    func registerOnFirstLaunchSilentlyHappyPath() {
        let fake = FakeLaunchAtLoginBackend()
        fake.currentStatus = .notRegistered
        let controller = LaunchAtLoginController(backend: fake)

        controller.registerOnFirstLaunchSilently()

        #expect(fake.registerCallCount == 1)
    }

    @Test("registerOnFirstLaunchSilently swallows backend errors")
    func registerOnFirstLaunchSilentlyThrowPath() {
        let fake = FakeLaunchAtLoginBackend()
        fake.currentStatus = .notRegistered
        fake.shouldThrowOnRegister = true
        let controller = LaunchAtLoginController(backend: fake)

        controller.registerOnFirstLaunchSilently()

        #expect(fake.registerCallCount == 1)
    }
}
