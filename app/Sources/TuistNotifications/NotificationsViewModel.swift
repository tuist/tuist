import Foundation
import TuistAuthentication
import TuistServer

@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var isLoading = true
    private(set) var devices: [ServerPushDevice] = []
    /// The user's choices about new previews, per account and project.
    private(set) var newPreviews = ServerNotificationPreferences(
        kind: ServerNotificationPreferences.newPreviewKind,
        accounts: []
    )

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
        newPreviews = try await preferences
        self.devices = try await devices
    }

    func setEnabledOnThisDevice(_ isEnabled: Bool) async throws {
        try await pushNotifications.setEnabledOnThisDevice(isEnabled)
        devices = try await listPushDevicesService.listPushDevices(serverURL: serverEnvironmentService.url())
    }

    func setAccountEnabled(_ enabled: Bool, accountHandle: String) async throws {
        try await update {
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

    func setProjectSetting(
        _ setting: ServerNotificationPreferences.ProjectSetting,
        accountHandle: String,
        projectHandle: String
    ) async throws {
        try await update {
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

    /// Applies the change right away, then adopts the preferences the server returns, or reverts if the request fails.
    private func update(
        _ change: (inout ServerNotificationPreferences) -> Void,
        send: (String, URL) async throws -> ServerNotificationPreferences
    ) async throws {
        let previous = newPreviews
        change(&newPreviews)
        do {
            newPreviews = try await send(newPreviews.kind, serverEnvironmentService.url())
        } catch {
            newPreviews = previous
            throw error
        }
    }
}
