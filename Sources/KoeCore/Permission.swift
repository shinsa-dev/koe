/// What Koe asks macOS for, in the order the setup window shows it.
public enum Permission: String, CaseIterable, Sendable {
    /// To hear you. Without it there is no session.
    case microphone
    /// To take screenshots and record clips while you talk.
    case screenRecording
    /// To paste the bundle for you when a session ends. Optional: you can paste yourself.
    case accessibility

    public var isRequired: Bool {
        switch self {
        case .microphone, .screenRecording: true
        case .accessibility: false
        }
    }
}

public enum PermissionStatus: Sendable, Equatable {
    case granted
    /// Never asked: the system prompt can still be shown.
    case notDetermined
    /// Refused or restricted: only System Settings can change it now.
    case denied
}

/// Where setup stands for a set of statuses, and what the setup window offers next.
public struct SetupChecklist: Sendable, Equatable {
    public let statuses: [Permission: PermissionStatus]

    public init(statuses: [Permission: PermissionStatus]) {
        self.statuses = statuses
    }

    public func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    /// Koe can start a session once every required permission is granted.
    public var isReady: Bool {
        Permission.allCases.filter(\.isRequired).allSatisfy { status(of: $0) == .granted }
    }

    /// The first permission still to grant, required ones first, so the window can highlight one step at a time.
    public var nextStep: Permission? {
        let open = Permission.allCases.filter { status(of: $0) != .granted }
        return open.first(where: \.isRequired) ?? open.first
    }

    /// How a row's button reads: the system prompt while it can still be shown, System Settings once refused.
    public func action(for permission: Permission) -> SetupAction {
        switch status(of: permission) {
        case .granted: .none
        case .notDetermined: .request
        case .denied: .openSettings
        }
    }
}

public enum SetupAction: Sendable, Equatable {
    case none
    case request
    case openSettings
}
