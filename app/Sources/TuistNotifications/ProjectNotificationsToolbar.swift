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
    private(set) var isUpdating = false

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
        let components = fullHandle.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            preferences = nil
            return
        }
        // Keeps the bell while reloading the same project, so it doesn't flicker when the screen reappears.
        if components != [accountHandle, projectHandle] { preferences = nil }
        accountHandle = components[0]
        projectHandle = components[1]
        preferences = try await getNotificationPreferencesService.getNotificationPreferences(
            kind: ServerNotificationPreferences.newPreviewKind,
            serverURL: serverEnvironmentService.url()
        )
    }

    /// Turns the project on or off. Matching the account clears the override, so the project follows it again.
    /// Applies the change right away, then adopts the preferences the server returns, or reloads them if it fails.
    func setEnabled(_ enabled: Bool) async throws {
        guard !isUpdating, let previous = preferences, let account else { return }
        isUpdating = true
        defer { isUpdating = false }
        let setting = account.projectSetting(enabled: enabled)
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
            preferences = (try? await getNotificationPreferencesService.getNotificationPreferences(
                kind: previous.kind,
                serverURL: serverEnvironmentService.url()
            )) ?? previous
            throw error
        }
    }
}

extension View {
    /// Adds a bell to the toolbar that turns new-preview notifications for the project on or off. It stays hidden
    /// until the user turns on notifications on this device, and when the project isn't in the user's accounts.
    public func projectNotificationsToolbar(fullHandle: String) -> some View {
        modifier(ProjectNotificationsToolbar(
            fullHandle: fullHandle,
            pushNotifications: .shared,
            viewModel: ProjectNotificationsViewModel()
        ))
    }
}

struct ProjectNotificationsToolbar: ViewModifier {
    @EnvironmentObject private var errorHandling: ErrorHandling
    let fullHandle: String
    let pushNotifications: PushNotifications
    @State var viewModel: ProjectNotificationsViewModel

    func body(content: Content) -> some View {
        content
            .toolbar {
                if pushNotifications.isEnabledOnThisDevice, let project = viewModel.project {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle(
                                "Notify Me About New Previews",
                                isOn: asyncBinding(errorHandling) { project.enabled } set: { enabled in
                                    try await viewModel.setEnabled(enabled)
                                }
                            )
                            .disabled(viewModel.isUpdating)
                        } label: {
                            Image(systemName: project.enabled ? "bell" : "bell.slash")
                        }
                        .accessibilityLabel(project.enabled ? "Notifications on" : "Notifications off")
                    }
                }
            }
            // Also reloads when the tab reappears and when notifications are turned on, since Profile can change
            // the same preferences.
            .task(id: "\(fullHandle) \(pushNotifications.isEnabledOnThisDevice)") {
                // The bell is hidden while notifications are off, so there's nothing to load.
                guard pushNotifications.isEnabledOnThisDevice else { return }
                do {
                    try await viewModel.load(fullHandle: fullHandle)
                } catch {
                    // The bell is secondary to the previews list, so a server without these preferences just hides it.
                    Logger.current.error("Failed to load the project's notification preference: \(error.localizedDescription)")
                }
            }
    }
}
