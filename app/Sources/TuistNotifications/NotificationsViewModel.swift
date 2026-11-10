import Foundation
import TuistAuthentication
import TuistServer

@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var isLoading = true
    /// Whether the rules loaded, so an error isn't mistaken for having none.
    private(set) var didLoad = false
    /// False when the server predates notification rules or doesn't accept this sign-in.
    private(set) var isSupported = true
    private(set) var rules: [ServerNotificationRule] = []
    private(set) var devices: [ServerPushDevice] = []
    /// `account/project` handles of the projects the user can pick for a rule, sorted.
    private(set) var projects: [String] = []
    /// The opt-in the user just asked for, shown until the change finishes.
    private(set) var pendingOptIn: Bool?
    /// Rules with a change in flight, whose controls stay disabled until it finishes.
    private(set) var rulesInFlight: Set<String> = []

    let pushNotifications: PushNotifications
    private let notificationRulesService: NotificationRulesServicing
    private let listPushDevicesService: ListPushDevicesServicing
    private let removePushDeviceService: RemovePushDeviceServicing
    private let listProjectsService: ListProjectsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    /// Condition options per project, fetched once per screen.
    private var conditionOptionsCache: [String: [String: [String]]] = [:]

    init(
        pushNotifications: PushNotifications? = nil,
        notificationRulesService: NotificationRulesServicing = NotificationRulesService(),
        listPushDevicesService: ListPushDevicesServicing = ListPushDevicesService(),
        removePushDeviceService: RemovePushDeviceServicing = RemovePushDeviceService(),
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService()
    ) {
        self.pushNotifications = pushNotifications ?? .shared
        self.notificationRulesService = notificationRulesService
        self.listPushDevicesService = listPushDevicesService
        self.removePushDeviceService = removePushDeviceService
        self.listProjectsService = listProjectsService
        self.serverEnvironmentService = serverEnvironmentService
    }

    var isOptedIn: Bool {
        pendingOptIn ?? pushNotifications.isEnabledOnThisDevice
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
        async let rules = notificationRulesService.listRules(serverURL: serverURL)
        async let devices = listPushDevicesService.listPushDevices(serverURL: serverURL)
        async let projects = listProjectsService.listProjects(serverURL: serverURL)
        do {
            self.rules = try await rules
            didLoad = true
            self.devices = try await devices
            self.projects = try await projects.map(\.fullName).sorted()
        } catch NotificationRulesServiceError.unsupported, ListPushDevicesServiceError.unsupported {
            isSupported = false
        } catch NotificationRulesServiceError.forbidden, ListPushDevicesServiceError.forbidden {
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
            // The screen may have opened offline; the rules appear now, so they need to be there.
            try await load()
        } else {
            try await reloadDevices()
        }
    }

    func removeDevice(_ device: ServerPushDevice) async throws {
        try await removePushDeviceService.removePushDevice(
            registrationID: device.registrationID,
            serverURL: serverEnvironmentService.url()
        )
        devices.removeAll { $0.registrationID == device.registrationID }
    }

    /// Saves `rule`: creates it when it has no ID yet, otherwise updates it.
    func save(_ rule: ServerNotificationRule) async throws {
        let serverURL = serverEnvironmentService.url()
        if rule.id.isEmpty {
            rules.append(try await notificationRulesService.createRule(rule, serverURL: serverURL))
        } else {
            rulesInFlight.insert(rule.id)
            defer { rulesInFlight.remove(rule.id) }
            let saved = try await notificationRulesService.updateRule(rule, serverURL: serverURL)
            if let index = rules.firstIndex(where: { $0.id == saved.id }) { rules[index] = saved }
        }
    }

    func setEnabled(_ isEnabled: Bool, rule: ServerNotificationRule) async throws {
        var rule = rule
        rule.isEnabled = isEnabled
        try await save(rule)
    }

    func delete(_ rule: ServerNotificationRule) async throws {
        rulesInFlight.insert(rule.id)
        defer { rulesInFlight.remove(rule.id) }
        try await notificationRulesService.deleteRule(id: rule.id, serverURL: serverEnvironmentService.url())
        rules.removeAll { $0.id == rule.id }
    }

    /// The values the user can pick for `condition` (`track` or `git_branch`) in `rule`'s projects, sorted. A rule
    /// for any project has no suggestions, since it would mean asking every project.
    func options(for condition: String, in rule: ServerNotificationRule) async -> [String] {
        var values = Set<String>()
        for project in rule.projects {
            if conditionOptionsCache[project] == nil {
                conditionOptionsCache[project] = try? await notificationRulesService.conditionOptions(
                    event: rule.event,
                    projectFullHandle: project,
                    serverURL: serverEnvironmentService.url()
                )
            }
            values.formUnion(conditionOptionsCache[project]?[condition] ?? [])
        }
        return values.sorted()
    }
}
