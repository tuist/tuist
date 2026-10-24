import Foundation
import SwiftUI
import UIKit
import UserNotifications

enum AtlasPushActions {
    static let orbitCompletedCategoryID = "ATLAS_ORBIT_COMPLETED"
    static let openConversationID = "ATLAS_OPEN_CONVERSATION"

    static var orbitCompletedCategory: UNNotificationCategory {
        let open = UNNotificationAction(
            identifier: openConversationID, title: "Open conversation", options: [.foreground, .authenticationRequired]
        )
        return UNNotificationCategory(
            identifier: orbitCompletedCategoryID, actions: [open], intentIdentifiers: [], options: []
        )
    }
}

/// Push data is only a navigation hint. AtlasNavigation validates the origin and destination again.
enum AtlasPushPayload {
    static func destination(_ payload: [AnyHashable: Any]) -> URL? {
        guard let version = payload["schema_version"], String(describing: version) == "1",
              let value = payload["url"] as? String, value.utf8.count <= 2048,
              let url = URL(string: value), url.scheme == "dev.tuist.atlas", url.host == "navigate" else { return nil }
        return url
    }

    static func destination(
        _ payload: [AnyHashable: Any], actionIdentifier: String, categoryIdentifier: String
    ) -> URL? {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier
            || (actionIdentifier == AtlasPushActions.openConversationID
                && categoryIdentifier == AtlasPushActions.orbitCompletedCategoryID) else { return nil }
        return destination(payload)
    }
}

@MainActor
final class AtlasPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    @Published var token: String?
    @Published var destination: URL?
    @Published var registrationFailed = false

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([AtlasPushActions.orbitCompletedCategory])
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        registrationFailed = false
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {
        registrationFailed = true
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let url = AtlasPushPayload.destination(
            content.userInfo, actionIdentifier: response.actionIdentifier, categoryIdentifier: content.categoryIdentifier
        )
        Task { @MainActor in
            if let url { self.destination = url }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Foreground views already show current state. Do not interrupt editing with banners.
        completionHandler([])
    }
}

struct AtlasPushRegistration: Codable {
    var installationID: String
    var origin: String
    var enabled: Bool
}

struct AtlasPushRegistrationStore {
    var keychain: any AtlasKeychainAccess = AtlasSystemKeychain()

    func load(origin: String) throws -> AtlasPushRegistration? {
        guard let value = try AtlasSecureStorage.load(key(origin), keychain: keychain) else { return nil }
        let saved = try JSONDecoder().decode(AtlasPushRegistration.self, from: Data(value.utf8))
        guard saved.origin == origin else { throw CocoaError(.coderReadCorrupt) }
        return saved
    }

    func save(_ value: AtlasPushRegistration) throws {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else { throw CocoaError(.coderInvalidValue) }
        try AtlasSecureStorage.save(key(value.origin), value: json, keychain: keychain)
    }

    func delete(origin: String) throws {
        try AtlasSecureStorage.delete(key(origin), keychain: keychain)
    }

    func disableForSessionEnd(origin: String) {
        do {
            if var saved = try load(origin: origin) {
                saved.enabled = false
                try save(saved)
            }
        } catch {
            // Corrupt push bookkeeping must not prevent deletion of the OAuth session.
            try? delete(origin: origin)
        }
    }

    private func key(_ origin: String) -> String { "push-registration:" + origin }
}

@MainActor
final class AtlasPushNotifications: ObservableObject {
    typealias Request = ([String: Any]) async throws -> Data
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var request: Request?
    private var server: URL?
    private var token: String?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var generation = UUID()
    private let store: AtlasPushRegistrationStore

    init(store: AtlasPushRegistrationStore = AtlasPushRegistrationStore()) {
        self.store = store
    }

    func configure(server: URL?, request: Request?) async {
        await acquire()
        defer { release() }
        generation = UUID()
        let identity = generation
        self.server = server
        self.request = request
        enabled = false
        message = nil
        guard let server, let request else { return }
        do {
            if let saved = try store.load(origin: server.absoluteString) {
                if saved.enabled {
                    enabled = true
                } else {
                    _ = try await request(["action": "unregister", "installation_id": saved.installationID])
                    guard generation == identity else { return }
                    try store.delete(origin: saved.origin)
                }
            }
        } catch {
            if generation == identity { message = "Could not reconcile notification registration. Try again when connected." }
        }
        if enabled, generation == identity { UIApplication.shared.registerForRemoteNotifications() }
    }

    func enable() async {
        await acquire()
        defer { release() }
        guard let server, let request else { return }
        guard environment != nil else {
            message = "Push notifications are not configured in this signed build."
            return
        }
        let identity = generation
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard generation == identity else { return }
            guard granted else {
                message = "Allow notifications for Atlas in iOS Settings to enable alerts."
                return
            }
            if let old = try store.load(origin: server.absoluteString), !old.enabled {
                _ = try await request(["action": "unregister", "installation_id": old.installationID])
                guard generation == identity else { return }
                try store.delete(origin: old.origin)
            }
            if try store.load(origin: server.absoluteString) == nil {
                try store.save(AtlasPushRegistration(
                    installationID: UUID().uuidString.lowercased(), origin: server.absoluteString, enabled: true
                ))
            }
            enabled = true
            message = nil
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            if generation == identity { message = "Could not enable notifications. Try again." }
        }
    }

    func refresh(token: String? = nil) async {
        if let token { self.token = token } else if enabled { UIApplication.shared.registerForRemoteNotifications() }
        await acquire()
        defer { release() }
        guard enabled, let server, let request, let environment,
              let saved = try? store.load(origin: server.absoluteString), saved.enabled else { return }
        let identity = generation
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard generation == identity else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            await disableLocked()
            return
        }
        guard let token = self.token else {
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        await sync(saved, request: request, token: token, environment: environment, identity: identity)
    }

    func disable() async {
        await acquire()
        defer { release() }
        await disableLocked()
    }

    func signOut() async { await disable() }

    func prepareForSessionEnd(origin: String? = nil) {
        generation = UUID()
        enabled = false
        if let origin = origin ?? server?.absoluteString { store.disableForSessionEnd(origin: origin) }
        request = nil
        server = nil
        token = nil
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func registrationFailed() {
        if enabled { message = "iOS could not register for notifications. Check your connection and signed build." }
    }

    private func disableLocked() async {
        enabled = false
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        guard let server else { return }
        let identity = generation
        do {
            guard var saved = try store.load(origin: server.absoluteString) else { return }
            saved.enabled = false
            // Persist cleanup before networking: an offline sign-out must not inherit opt-in on the next account.
            try store.save(saved)
            guard let request else { return }
            _ = try await request(["action": "unregister", "installation_id": saved.installationID])
            guard generation == identity else { return }
            try store.delete(origin: saved.origin)
            message = nil
        } catch {
            if generation == identity { message = "Notifications are off locally. Server cleanup will retry at your next sign-in." }
        }
    }

    private func sync(
        _ saved: AtlasPushRegistration, request: Request, token: String, environment: String, identity: UUID
    ) async {
        do {
            _ = try await request(registrationAction(saved, token: token, environment: environment))
            guard generation == identity else { return }
            message = nil
        } catch let failure as AtlasAuthenticationError where failure.kind == "conflict" {
            guard generation == identity else { return }
            await renew(saved, request: request, token: token, environment: environment, identity: identity)
        } catch {
            if generation == identity { message = "Could not sync notifications. Atlas will retry when you return." }
        }
    }

    private func renew(
        _ saved: AtlasPushRegistration, request: Request, token: String, environment: String, identity: UUID
    ) async {
        do {
            _ = try await request(["action": "unregister", "installation_id": saved.installationID])
            guard generation == identity else { return }
            let replacement = AtlasPushRegistration(installationID: UUID().uuidString.lowercased(), origin: saved.origin, enabled: true)
            try store.save(replacement)
            _ = try await request(registrationAction(replacement, token: token, environment: environment))
            guard generation == identity else { return }
            message = nil
        } catch {
            if generation == identity { message = "Could not renew notification registration. Atlas will retry when you return." }
        }
    }

    private func registrationAction(_ saved: AtlasPushRegistration, token: String, environment: String) -> [String: Any] {
        ["action": "register", "installation_id": saved.installationID, "platform": "ios", "token": token, "environment": environment]
    }

    private var environment: String? {
        switch Bundle.main.object(forInfoDictionaryKey: "AtlasPushEnvironment") as? String {
        case "development": "sandbox"
        case "production": "production"
        default: nil
        }
    }

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

struct AtlasPushSettingsView: View {
    @ObservedObject var notifications: AtlasPushNotifications

    var body: some View {
        Section {
            Toggle("Push notifications", isOn: Binding(
                get: { notifications.enabled },
                set: { enabled in Task { if enabled { await notifications.enable() } else { await notifications.disable() } } }
            )).disabled(notifications.busy)
            if let message = notifications.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } footer: {
            Text("Get notified when Pip finishes. Alerts include the thread title and a short reply preview. "
                 + "Control lock-screen previews in iOS Settings.")
        }
    }
}
