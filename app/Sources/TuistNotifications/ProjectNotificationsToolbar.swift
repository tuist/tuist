import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistLogging
import TuistServer

@MainActor
@Observable
final class ProjectNotificationsViewModel {
    private(set) var preferences: ServerNotificationPreferences?
    private(set) var accountHandle = ""
    private(set) var projectHandle = ""

    private let getNotificationPreferencesService: GetNotificationPreferencesServicing
    private let updateProjectNotificationService: UpdateProjectNotificationServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        getNotificationPreferencesService: GetNotificationPreferencesServicing = GetNotificationPreferencesService(),
        updateProjectNotificationService: UpdateProjectNotificationServicing = UpdateProjectNotificationService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService()
    ) {
        self.getNotificationPreferencesService = getNotificationPreferencesService
        self.updateProjectNotificationService = updateProjectNotificationService
        self.serverEnvironmentService = serverEnvironmentService
    }

    var account: ServerNotificationPreferences.Account? {
        preferences?.account(accountHandle)
    }

    /// `nil` when the project isn't in the user's accounts, for example a public project of another organization.
    var project: ServerNotificationPreferences.Project? {
        account?.project(projectHandle)
    }

    func load(fullHandle: String) async throws {
        preferences = nil
        let components = fullHandle.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return }
        accountHandle = components[0]
        projectHandle = components[1]
        preferences = try await getNotificationPreferencesService.getNotificationPreferences(
            kind: ServerNotificationPreferences.newPreviewKind,
            serverURL: serverEnvironmentService.url()
        )
    }

    /// Applies the change right away, then adopts the preferences the server returns, or reverts if the request fails.
    func setSetting(_ setting: ServerNotificationPreferences.ProjectSetting) async throws {
        guard let previous = preferences else { return }
        preferences?.setProjectSetting(setting, accountHandle: accountHandle, projectHandle: projectHandle)
        do {
            preferences = try await updateProjectNotificationService.updateProjectNotificationPreference(
                kind: previous.kind,
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                setting: setting,
                serverURL: serverEnvironmentService.url()
            )
        } catch {
            preferences = previous
            throw error
        }
    }
}

extension View {
    /// Adds a bell to the toolbar that changes whether new previews of the project notify the user. It stays hidden
    /// when the project isn't in the user's accounts.
    public func projectNotificationsToolbar(fullHandle: String) -> some View {
        modifier(ProjectNotificationsToolbar(fullHandle: fullHandle, viewModel: ProjectNotificationsViewModel()))
    }
}

struct ProjectNotificationsToolbar: ViewModifier {
    @EnvironmentObject private var errorHandling: ErrorHandling
    let fullHandle: String
    @State var viewModel: ProjectNotificationsViewModel

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let account = viewModel.account, let project = viewModel.project {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            option(
                                .default,
                                current: project.setting,
                                title: "Follow \(account.handle)",
                                subtitle: "\(account.enabled ? "On" : "Off"), as set in your notification settings"
                            )
                            option(
                                .on,
                                current: project.setting,
                                title: "Always notify me",
                                subtitle: "Get a push for every new preview of this project"
                            )
                            option(
                                .off,
                                current: project.setting,
                                title: "Never notify me",
                                subtitle: "No pushes for this project"
                            )
                        } label: {
                            Image(systemName: project.enabled ? "bell" : "bell.slash")
                        }
                        .accessibilityLabel(project.enabled ? "Notifications on" : "Notifications off")
                    }
                }
            }
            .task(id: fullHandle) {
                do {
                    try await viewModel.load(fullHandle: fullHandle)
                } catch {
                    // The bell is secondary to the previews list, so a server without these preferences just hides it.
                    Logger.current.error("Failed to load the project's notification preference: \(error.localizedDescription)")
                }
            }
    }

    /// A checkable menu option. Its second text renders as the subtitle.
    private func option(
        _ setting: ServerNotificationPreferences.ProjectSetting,
        current: ServerNotificationPreferences.ProjectSetting,
        title: String,
        subtitle: String
    ) -> some View {
        Toggle(isOn: asyncBinding(errorHandling) { current == setting } set: { isOn in
            guard isOn else { return }
            try await viewModel.setSetting(setting)
        }) {
            Text(title)
            Text(subtitle)
        }
    }
}
