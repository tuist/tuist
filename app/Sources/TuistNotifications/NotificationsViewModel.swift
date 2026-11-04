import Foundation
import TuistAuthentication
import TuistServer

@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var isLoading = true
    /// Whether the preferences loaded, so an error isn't mistaken for having no projects.
    private(set) var didLoad = false
    /// False when the server predates notifications.
    private(set) var isSupported = true
    private(set) var devices: [ServerPushDevice] = []
    /// The user's choices about new previews, per account and project.
    private(set) var newPreviews = ServerNotificationPreferences(
        kind: ServerNotificationPreferences.newPreviewKind,
        accounts: []
    )
    /// The opt-in the user just asked for, shown until the change finishes.
    private(set) var pendingOptIn: Bool?
    /// Accounts and projects with a change in flight, whose switches stay disabled until it finishes.
    private(set) var changesInFlight: Set<String> = []
    /// Set when changes overlap or one fails, so the last one to finish reloads instead of adopting a response that
    /// may not include the others.
    private var needsReload = false
    /// The latest preferences the server returned, including responses that weren't adopted, for when a reload fails.
    private var serverPreferences: ServerNotificationPreferences?

    let pushNotifications: PushNotifications
    private let listPushDevicesService: ListPushDevicesServicing
    private let removePushDeviceService: RemovePushDeviceServicing
    private let getNotificationPreferencesService: GetNotificationPreferencesServicing
    private let updateAccountNotificationService: UpdateAccountNotificationServicing
    private let updateProjectNotificationService: UpdateProjectNotificationServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        pushNotifications: PushNotifications? = nil,
        listPushDevicesService: ListPushDevicesServicing = ListPushDevicesService(),
        removePushDeviceService: RemovePushDeviceServicing = RemovePushDeviceService(),
        getNotificationPreferencesService: GetNotificationPreferencesServicing = GetNotificationPreferencesService(),
        updateAccountNotificationService: UpdateAccountNotificationServicing = UpdateAccountNotificationService(),
        updateProjectNotificationService: UpdateProjectNotificationServicing = UpdateProjectNotificationService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService()
    ) {
        self.pushNotifications = pushNotifications ?? .shared
        self.listPushDevicesService = listPushDevicesService
        self.removePushDeviceService = removePushDeviceService
        self.getNotificationPreferencesService = getNotificationPreferencesService
        self.updateAccountNotificationService = updateAccountNotificationService
        self.updateProjectNotificationService = updateProjectNotificationService
        self.serverEnvironmentService = serverEnvironmentService
    }

    var isOptedIn: Bool {
        pendingOptIn ?? pushNotifications.isEnabledOnThisDevice
    }

    /// Accounts without projects have nothing to choose, so they aren't shown.
    var accountsWithProjects: [ServerNotificationPreferences.Account] {
        newPreviews.accounts.filter { !$0.projects.isEmpty }
    }

    /// The signed-in user's devices, with this device first.
    var sortedDevices: [ServerPushDevice] {
        let installationID = pushNotifications.installationID
        return devices.sorted { lhs, rhs in
            if (lhs.installationID == installationID) != (rhs.installationID == installationID) {
                return lhs.installationID == installationID
            }
            return lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    func isThisDevice(_ device: ServerPushDevice) -> Bool {
        device.installationID == pushNotifications.installationID
    }

    func load() async throws {
        defer { isLoading = false }
        await pushNotifications.refresh()
        let serverURL = serverEnvironmentService.url()
        async let preferences = getNotificationPreferencesService.getNotificationPreferences(
            kind: ServerNotificationPreferences.newPreviewKind,
            serverURL: serverURL
        )
        async let devices = listPushDevicesService.listPushDevices(serverURL: serverURL)
        do {
            newPreviews = try await preferences
            serverPreferences = newPreviews
            didLoad = true
            self.devices = try await devices
        } catch GetNotificationPreferencesServiceError.unsupported, ListPushDevicesServiceError.unsupported {
            isSupported = false
        } catch GetNotificationPreferencesServiceError.forbidden, ListPushDevicesServiceError.forbidden {
            // Servers only accept these requests from their own Tuist app client, which self-hosted sign-ins aren't.
            isSupported = false
        }
    }

    func reloadDevices() async throws {
        devices = try await listPushDevicesService.listPushDevices(serverURL: serverEnvironmentService.url())
    }

    func setEnabledOnThisDevice(_ isEnabled: Bool) async throws {
        guard pendingOptIn == nil else { return }
        pendingOptIn = isEnabled
        defer { pendingOptIn = nil }
        try await pushNotifications.setEnabledOnThisDevice(isEnabled)
        if isEnabled, !didLoad {
            // The screen may have opened offline; the preferences appear now, so they need to be there.
            try await load()
        } else {
            devices = try await listPushDevicesService.listPushDevices(serverURL: serverEnvironmentService.url())
        }
    }

    func setAccountEnabled(_ enabled: Bool, accountHandle: String) async throws {
        try await update(key: accountHandle) {
            $0.setAccountEnabled(enabled, accountHandle: accountHandle)
        } send: { [updateAccountNotificationService] kind, serverURL in
            try await updateAccountNotificationService.updateAccountNotificationPreference(
                kind: kind,
                accountHandle: accountHandle,
                enabled: enabled,
                serverURL: serverURL
            )
        }
    }

    /// Turns a project on or off. Matching the account clears the project's override, so it follows the account again.
    func setProjectEnabled(_ enabled: Bool, accountHandle: String, projectHandle: String) async throws {
        guard let account = newPreviews.account(accountHandle) else { return }
        let setting = account.projectSetting(enabled: enabled)
        try await update(key: "\(accountHandle)/\(projectHandle)") {
            $0.setProjectSetting(setting, accountHandle: accountHandle, projectHandle: projectHandle)
        } send: { [updateProjectNotificationService] kind, serverURL in
            try await updateProjectNotificationService.updateProjectNotificationPreference(
                kind: kind,
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                setting: setting,
                serverURL: serverURL
            )
        }
    }

    func removeDevice(_ device: ServerPushDevice) async throws {
        devices.removeAll { $0.registrationID == device.registrationID }
        do {
            try await removePushDeviceService.removePushDevice(
                registrationID: device.registrationID,
                serverURL: serverEnvironmentService.url()
            )
        } catch {
            devices = try await listPushDevicesService.listPushDevices(serverURL: serverEnvironmentService.url())
            throw error
        }
    }

    /// Applies the change right away and sends it. A change adopts the server's response only when no other change
    /// overlapped it; otherwise the last one to finish reloads, so a late response can't undo a newer change.
    private func update(
        key: String,
        _ change: (inout ServerNotificationPreferences) -> Void,
        send: (String, URL) async throws -> ServerNotificationPreferences
    ) async throws {
        guard !changesInFlight.contains(key) else { return }
        if !changesInFlight.isEmpty { needsReload = true }
        changesInFlight.insert(key)
        defer { changesInFlight.remove(key) }
        let previous = newPreviews
        change(&newPreviews)
        let serverURL = serverEnvironmentService.url()
        var failure: Error?
        var preferences: ServerNotificationPreferences?
        do {
            preferences = try await send(newPreviews.kind, serverURL)
            serverPreferences = preferences
        } catch {
            failure = error
            needsReload = true
        }
        if changesInFlight == [key], !needsReload, let preferences {
            newPreviews = preferences
        }
        // A change that starts during a reload sets `needsReload` again: if it's still in flight it reloads when it
        // finishes, and if it already finished, this reloads again so its result isn't lost.
        while needsReload, changesInFlight == [key] {
            needsReload = false
            let reloaded = try? await getNotificationPreferencesService.getNotificationPreferences(
                kind: newPreviews.kind,
                serverURL: serverURL
            )
            if let reloaded { serverPreferences = reloaded }
            if !needsReload, changesInFlight == [key] {
                newPreviews = reloaded ?? serverPreferences ?? previous
            }
        }
        if let failure { throw failure }
    }
}
