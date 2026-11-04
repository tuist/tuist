#if DEBUG
    import Foundation
    import SwiftUI
    import TuistAppStorage
    import TuistAuthentication
    import TuistErrorHandling
    import TuistServer

    public enum NotificationsDemoState: String, CaseIterable {
        case off
        case oneAccount = "one-account"
        case severalAccounts = "several-accounts"
        case denied
        case projectBell = "project-bell"
    }

    extension NotificationsView {
        /// Renders the screen with mock data, for SwiftUI previews and the `-notifications-demo <state>` launch argument.
        @MainActor
        public static func demo(_ state: NotificationsDemoState) -> some View {
            let appStorage = DemoAppStorage()
            let serverURL = AppServerEnvironmentService(appStorage: appStorage).url()
            try? appStorage.set(
                AuthenticationStateKey.self,
                value: .loggedIn(account: Account(email: "marek@tuist.dev", handle: "marek"))
            )
            try? appStorage.set(
                PushInstallationsKey.self,
                value: [serverURL.absoluteString: PushInstallation(installationID: "this-installation", isEnabled: state != .off)]
            )
            let permission: NotificationPermission = switch state {
            case .off: .notDetermined
            case .denied: .denied
            case .oneAccount, .severalAccounts, .projectBell: .authorized
            }
            let services = DemoNotificationServices(oneAccount: state == .oneAccount)
            let viewModel = NotificationsViewModel(
                pushNotifications: PushNotifications(
                    registrationService: PushRegistrationService(
                        unregisterPushDeviceService: services,
                        appStorage: appStorage
                    ),
                    appStorage: appStorage,
                    previewPermission: permission
                ),
                listPushDevicesService: services,
                removePushDeviceService: services,
                getNotificationPreferencesService: services,
                updateAccountNotificationService: services,
                updateProjectNotificationService: services,
                serverEnvironmentService: AppServerEnvironmentService(appStorage: appStorage)
            )
            return NavigationStack {
                if state == .projectBell {
                    List {
                        ForEach(["Tuist 4.216.0", "Tuist 4.215.2", "Tuist 4.215.1"], id: \.self) { name in
                            Text(name)
                        }
                    }
                    .listStyle(.plain)
                    .navigationTitle("Previews")
                    .modifier(ProjectNotificationsToolbar(
                        fullHandle: "tuist/tuist",
                        pushNotifications: viewModel.pushNotifications,
                        viewModel: ProjectNotificationsViewModel(
                            getNotificationPreferencesService: services,
                            updateProjectNotificationService: services,
                            serverEnvironmentService: AppServerEnvironmentService(appStorage: appStorage)
                        )
                    ))
                } else {
                    NotificationsView(viewModel: viewModel, userHandle: "marek")
                }
            }
            .withErrorHandling()
        }
    }

    private final class DemoAppStorage: AppStoring, @unchecked Sendable {
        private var values: [String: Data] = [:]

        func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
            guard let data = values[key.key] else { return key.defaultValue }
            return try JSONDecoder().decode(Key.Value.self, from: data)
        }

        func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
            values[key.key] = try JSONEncoder().encode(value)
        }
    }

    private actor DemoNotificationServices: ListPushDevicesServicing, RemovePushDeviceServicing,
        GetNotificationPreferencesServicing, UpdateAccountNotificationServicing,
        UpdateProjectNotificationServicing, UnregisterPushDeviceServicing
    {
        private var preferences: ServerNotificationPreferences

        init(oneAccount: Bool) {
            preferences = oneAccount ? Self.oneAccount : Self.severalAccounts
        }

        private static let oneAccount = ServerNotificationPreferences(
            kind: ServerNotificationPreferences.newPreviewKind,
            accounts: [
                .init(handle: "marek", enabled: true, projects: []),
                .init(handle: "tuist", enabled: true, projects: [
                    .init(handle: "tuist", setting: .default, enabled: true),
                    .init(handle: "android-app", setting: .off, enabled: false),
                    .init(handle: "ios-app", setting: .default, enabled: true),
                    .init(handle: "registry", setting: .default, enabled: true),
                    .init(handle: "noora", setting: .default, enabled: true),
                ]),
            ]
        )

        private static let severalAccounts = ServerNotificationPreferences(
            kind: ServerNotificationPreferences.newPreviewKind,
            accounts: [
                .init(handle: "marek", enabled: true, projects: [
                    .init(handle: "playground", setting: .default, enabled: true),
                ]),
                .init(handle: "tuist", enabled: true, projects: [
                    .init(handle: "tuist", setting: .default, enabled: true),
                    .init(handle: "ios-app", setting: .default, enabled: true),
                    .init(handle: "android-app", setting: .off, enabled: false),
                ]),
                .init(handle: "acme", enabled: false, projects: [
                    .init(handle: "shop-ios", setting: .on, enabled: true),
                    .init(handle: "web", setting: .default, enabled: false),
                ]),
            ]
        )

        func listPushDevices(serverURL _: URL) async throws -> [ServerPushDevice] {
            [
                .test(
                    registrationID: "1",
                    installationID: "this-installation",
                    name: "iPhone 17 Pro",
                    lastSeenAt: Date().addingTimeInterval(-60)
                ),
                .test(
                    registrationID: "2",
                    installationID: "ipad",
                    name: "iPad Pro 13-inch (M5)",
                    lastSeenAt: Date().addingTimeInterval(-3 * 86400)
                ),
                .test(
                    registrationID: "3",
                    installationID: "android",
                    platform: "android",
                    name: "Pixel 10 Pro",
                    lastSeenAt: Date().addingTimeInterval(-12 * 86400)
                ),
            ]
        }

        func removePushDevice(registrationID _: String, serverURL _: URL) async throws {}

        func unregisterPushDevice(installationID _: String, serverURL _: URL) async throws {}

        func getNotificationPreferences(kind _: String, serverURL _: URL) async throws -> ServerNotificationPreferences {
            preferences
        }

        func updateAccountNotificationPreference(
            kind _: String,
            accountHandle: String,
            enabled: Bool,
            serverURL _: URL
        ) async throws -> ServerNotificationPreferences {
            preferences.setAccountEnabled(enabled, accountHandle: accountHandle)
            return preferences
        }

        func updateProjectNotificationPreference(
            kind _: String,
            accountHandle: String,
            projectHandle: String,
            setting: ServerNotificationPreferences.ProjectSetting,
            serverURL _: URL
        ) async throws -> ServerNotificationPreferences {
            preferences.setProjectSetting(setting, accountHandle: accountHandle, projectHandle: projectHandle)
            return preferences
        }
    }

    #Preview("Off") { NotificationsView.demo(.off) }
    #Preview("One account") { NotificationsView.demo(.oneAccount) }
    #Preview("Several accounts") { NotificationsView.demo(.severalAccounts) }
    #Preview("Denied") { NotificationsView.demo(.denied) }
    #Preview("Project bell") { NotificationsView.demo(.projectBell) }
#endif
