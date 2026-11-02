import Foundation
import TuistAppStorage
import TuistAuthentication
import TuistLogging
import TuistServer
import UIKit
import UserNotifications

public enum NotificationPermission: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized
}

/// Coordinates the system notification permission, the APNs device token, and the server registration.
@MainActor
@Observable
public final class PushNotifications {
    public static let shared = PushNotifications()

    public private(set) var permission: NotificationPermission = .unknown
    public private(set) var isEnabledOnThisDevice = true

    /// Whether this device can receive notifications right now, which also needs system permission.
    public var isActiveOnThisDevice: Bool {
        isEnabledOnThisDevice && permission == .authorized
    }

    private var deviceToken: String?
    private var registrationTask: Task<Void, Never>?
    private let registrationService: PushRegistrationService
    private let appStorage: AppStoring
    private let isPreview: Bool

    init(
        registrationService: PushRegistrationService = PushRegistrationService(),
        appStorage: AppStoring = AppStorage(),
        previewPermission: NotificationPermission? = nil
    ) {
        self.registrationService = registrationService
        self.appStorage = appStorage
        isPreview = previewPermission != nil
        permission = previewPermission ?? .unknown
    }

    /// The installation ID of this app for the signed-in server, used to mark "This device".
    public var installationID: String? {
        serverURL.flatMap { registrationService.installationID(serverURL: $0) }
    }

    /// Refreshes the permission and, when allowed, the device token, which in turn refreshes the registration.
    /// Call on launch, sign-in, and when the app returns to the foreground: the server retires stale registrations.
    public func refresh() async {
        guard !isPreview else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permission = switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
        isEnabledOnThisDevice = serverURL.map { registrationService.isEnabled(serverURL: $0) } ?? true
        if permission == .authorized, serverURL != nil {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Shows the system permission prompt. Only call it in response to the user asking for notifications.
    public func requestPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            Logger.current.error("Failed to request the notification permission: \(error.localizedDescription)")
        }
        await refresh()
    }

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        self.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        register()
    }

    public func setEnabledOnThisDevice(_ isEnabled: Bool) async throws {
        guard let serverURL else { return }
        await registrationTask?.value
        try await registrationService.setEnabled(isEnabled, serverURL: serverURL)
        isEnabledOnThisDevice = isEnabled
        if isEnabled {
            register()
            await registrationTask?.value
        }
    }

    /// Unregisters this device from the signed-in server. Call before signing out, while credentials are valid.
    public func signOut() async {
        guard let serverURL else { return }
        await registrationTask?.value
        await registrationService.signOut(serverURL: serverURL)
        isEnabledOnThisDevice = true
    }

    private var serverURL: URL? {
        guard case .loggedIn = try? appStorage.get(AuthenticationStateKey.self) else { return nil }
        return AppServerEnvironmentService(appStorage: appStorage).url()
    }

    private func register() {
        guard !isPreview, permission == .authorized, let serverURL, let deviceToken else { return }
        let previousTask = registrationTask
        registrationTask = Task {
            await previousTask?.value
            do {
                try await registrationService.register(
                    token: deviceToken,
                    environment: Self.environment,
                    name: DeviceModel.name,
                    serverURL: serverURL
                )
            } catch {
                Logger.current.error("Failed to register for push notifications: \(error.localizedDescription)")
            }
            isEnabledOnThisDevice = registrationService.isEnabled(serverURL: serverURL)
        }
    }

    /// Matches the `aps-environment` entitlement: development-signed debug builds use the APNs sandbox.
    private static var environment: PushDeviceEnvironment {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }
}
