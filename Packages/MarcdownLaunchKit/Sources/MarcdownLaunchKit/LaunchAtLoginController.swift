import Foundation
import Observation
import ServiceManagement

/// Observable controller for the "Launch at Login" preference, backed by `SMAppService`.
@MainActor
@Observable
public final class LaunchAtLoginController {
    public enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    public private(set) var state: State
    private let backend: any LaunchAtLoginBackend

    public init(backend: any LaunchAtLoginBackend = SMAppServiceBackend()) {
        self.backend = backend
        self.state = Self.mapStatus(backend.currentStatus)
    }

    public func refresh() {
        state = Self.mapStatus(backend.currentStatus)
    }

    public func setEnabled(_ on: Bool) {
        if on {
            try? backend.register()
        } else {
            try? backend.unregister()
        }
        refresh()
    }

    public func registerOnFirstLaunchSilently() {
        try? backend.register()
    }

    public static func mapStatus(_ status: SMAppService.Status) -> State {
        switch status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}

public protocol LaunchAtLoginBackend {
    var currentStatus: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

public struct SMAppServiceBackend: LaunchAtLoginBackend {
    public init() {}

    public var currentStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
