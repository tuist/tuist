import Foundation

/// The signed-in user's choices for one notification kind: one per account they belong to, with optional
/// per-project overrides.
public struct ServerNotificationPreferences: Equatable, Sendable {
    /// `new_preview` notifies about new previews of the user's projects.
    public static let newPreviewKind = "new_preview"

    public struct Account: Equatable, Hashable, Identifiable, Sendable {
        public let handle: String
        public var enabled: Bool
        public var projects: [Project]

        public var id: String { handle }

        public init(handle: String, enabled: Bool, projects: [Project]) {
            self.handle = handle
            self.enabled = enabled
            self.projects = projects
        }
    }

    public struct Project: Equatable, Hashable, Identifiable, Sendable {
        /// The project name, without the account.
        public let handle: String
        public var setting: ProjectSetting
        /// The effective value, which follows the account when `setting` is `.default`.
        public var enabled: Bool

        public var id: String { handle }

        public init(handle: String, setting: ProjectSetting, enabled: Bool) {
            self.handle = handle
            self.setting = setting
            self.enabled = enabled
        }
    }

    public enum ProjectSetting: String, CaseIterable, Sendable {
        /// Follows the account's choice.
        case `default`
        case on
        case off

        init(_ rawValue: String) {
            self = Self(rawValue: rawValue) ?? .default
        }
    }

    public let kind: String
    public var accounts: [Account]

    public init(kind: String, accounts: [Account]) {
        self.kind = kind
        self.accounts = accounts
    }

    init(_ preferences: Operations.getNotificationPreferences.Output.Ok.Body.jsonPayload) {
        self.init(kind: preferences.kind, accounts: preferences.accounts.map { account in
            Account(handle: account.handle, enabled: account.enabled, projects: account.projects.map { project in
                Project(handle: project.handle, setting: .init(project.setting.rawValue), enabled: project.enabled)
            })
        })
    }

    init(_ preferences: Operations.updateAccountNotificationPreference.Output.Ok.Body.jsonPayload) {
        self.init(kind: preferences.kind, accounts: preferences.accounts.map { account in
            Account(handle: account.handle, enabled: account.enabled, projects: account.projects.map { project in
                Project(handle: project.handle, setting: .init(project.setting.rawValue), enabled: project.enabled)
            })
        })
    }

    init(_ preferences: Operations.updateProjectNotificationPreference.Output.Ok.Body.jsonPayload) {
        self.init(kind: preferences.kind, accounts: preferences.accounts.map { account in
            Account(handle: account.handle, enabled: account.enabled, projects: account.projects.map { project in
                Project(handle: project.handle, setting: .init(project.setting.rawValue), enabled: project.enabled)
            })
        })
    }
}
