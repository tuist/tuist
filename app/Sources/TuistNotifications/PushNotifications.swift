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
/// Notifications are opt-in: nothing is registered until the user turns them on for the signed-in account.
@MainActor
@Observable
public final class PushNotifications {
    public static let shared = PushNotifications()

    public private(set) var permission: NotificationPermission = .unknown
    /// Whether the user turned on notifications on this device for the signed-in account.
    public private(set) var isEnabledOnThisDevice = false

    /// Whether this device can receive notifications right now, which also needs system permission.
    public var isActiveOnThisDevice: Bool {
        isEnabledOnThisDevice && permission == .authorized
    }

    /// The installation ID of this app for the signed-in server, used to mark "This device".
    public private(set) var installationID: String?

    @ObservationIgnored private var deviceToken: String?
    /// The last registration change. Each change waits for the previous one, so a registration can't
    /// interleave with turning notifications off or signing out.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private let registrationService: PushRegistrationService
    @ObservationIgnored private let appStorage: AppStoring
    @ObservationIgnored private let isPreview: Bool

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

    /// Refreshes the permission and, when the user opted in, the device token, which in turn refreshes the
    /// registration. Call on launch, on authentication changes, and when the app returns to the foreground:
    /// the server retires stale registrations.
    public func refresh() async {
        guard !isPreview else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permission = switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
        guard let serverURL else {
            // Sessions can also end without `signOut()`, for example when they expire or the account is deleted.
            // Forgetting the opt-in keeps the next account from being registered without asking. The server may not
            // have retired the registration yet, so the APNs token is invalidated too, as when signing out.
            _ = await enqueue { [registrationService] in
                if registrationService.forgetAll() {
                    UIApplication.shared.unregisterForRemoteNotifications()
                }
            }.result
            isEnabledOnThisDevice = false
            installationID = nil
            return
        }
        isEnabledOnThisDevice = registrationService.isEnabled(serverURL: serverURL)
        installationID = registrationService.installationID(serverURL: serverURL)
        if isActiveOnThisDevice {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Shows the system permission prompt if it hasn't been shown yet.
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

    /// Turns notifications on this device on or off. Turning them on asks for the system permission first and
    /// does nothing if it's denied. Turning them off throws if the server can't be told, and leaves them on.
    public func setEnabledOnThisDevice(_ isEnabled: Bool) async throws {
        guard let serverURL else { return }
        let sessionID = ServerAuthenticationSession.current.id
        if isEnabled {
            await requestPermission()
            guard permission == .authorized else { return }
        }
        try await enqueue { [registrationService] in
            // The session can end while the permission prompt is showing; its opt-in must not outlive it.
            guard self.serverURL == serverURL, sessionID == ServerAuthenticationSession.current.id else { return }
            try await registrationService.setEnabled(isEnabled, serverURL: serverURL)
        }.value
        guard sessionID == ServerAuthenticationSession.current.id else { return }
        isEnabledOnThisDevice = registrationService.isEnabled(serverURL: serverURL)
        installationID = registrationService.installationID(serverURL: serverURL)
        if isEnabledOnThisDevice {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Failed account transactions restore intent with a new installation, never a retired identifier.
    public func prepareForProfileChange() async -> (() async -> Void)? {
        guard let url = serverURL else { return nil }
        let wasEnabled = registrationService.isEnabled(serverURL: url)
        await signOut()
        guard wasEnabled else { return nil }
        return { [self] in
            guard serverURL == url else { return }
            do {
                try await enqueue { [registrationService] in
                    try await registrationService.setEnabled(true, serverURL: url)
                }.value
                await refresh()
            } catch {
                Logger.current.error("Could not restore notification preference: \(error.localizedDescription)")
            }
        }
    }

    /// Unregisters this device from the signed-in server. Call before signing out, while credentials are valid.
    public func signOut() async {
        guard let serverURL else { return }
        _ = await enqueue { [registrationService] in await registrationService.signOut(serverURL: serverURL) }.result
        isEnabledOnThisDevice = false
        installationID = nil
        // Invalidates the APNs token, so this device stops getting the user's notifications even if the server
        // couldn't be told, for example when signing out offline.
        if !isPreview {
            UIApplication.shared.unregisterForRemoteNotifications()
        }
    }

    private var serverURL: URL? {
        guard case .loggedIn = try? appStorage.get(AuthenticationStateKey.self) else { return nil }
        return AppServerEnvironmentService(appStorage: appStorage).url()
    }

    private func register() {
        guard !isPreview, permission == .authorized, let serverURL, let deviceToken else { return }
        let sessionID = ServerAuthenticationSession.current.id
        enqueue { [registrationService] in
            guard sessionID == ServerAuthenticationSession.current.id else { return }
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
            self.isEnabledOnThisDevice = registrationService.isEnabled(serverURL: serverURL)
            self.installationID = registrationService.installationID(serverURL: serverURL)
        }
    }

    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Error> {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            try await operation()
        }
        queue = Task { _ = await task.result }
        return task
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
