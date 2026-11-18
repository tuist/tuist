import SwiftUI
import UserNotifications
#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// The platform side of push notifications: permission, the APNs token and
/// notification taps. As in the shipping app, notifications stay off until the
/// person turns them on in Profile. The core keeps that choice per profile
/// (`push_enable`), registers the token for the active profile
/// (`push_register`) and decides where a tap leads (`open_notification`).
@MainActor
@Observable
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate {
    enum Permission { case unknown, notDetermined, denied, authorized }

    static let shared = PushNotifications()

    private(set) var permission = Permission.unknown
    /// The choice the person just made, shown until the core records it.
    private(set) var pendingEnabled: Bool?

    private var client: AppClient?
    /// A sign-out couldn't unregister on the server, which keeps sending to this
    /// device's token. APNs may hand the same token back, so this launch doesn't
    /// register again on its own; turning the switch on still does.
    private var registrationPaused = false
    private var token: String?
    /// A tap that arrived before the client booted, such as the one that launched the app.
    private var pendingTap: (url: String, account: String?, user: String?)?

    /// The APNs environment of the signing profile's push entitlement, which
    /// `ios/distribution/bundle.sh` stamps into Info.plist. Without one, this
    /// build cannot receive notifications and never asks for permission.
    static var environment: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "LuftPushEnvironment") as? String
        return value == "production" || value == "sandbox" ? value : nil
    }

    private static var platform: String {
        #if os(iOS)
            "ios"
        #else
            "macos"
        #endif
    }

    /// Called while the app finishes launching, so a tap that launched it is delivered here.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Called once the core booted: from now on taps go straight to it.
    func attach(_ client: AppClient) async {
        self.client = client
        if let tap = pendingTap {
            pendingTap = nil
            await open(url: tap.url, account: tap.account, user: tap.user)
        }
    }

    /// Whether the active profile has notifications on, counting a change in flight.
    var isEnabled: Bool {
        pendingEnabled ?? client?.view.active?.push_enabled ?? false
    }

    /// Refreshes the permission and, when the active profile has notifications
    /// on, the APNs token, which in turn refreshes the registration. Call when
    /// the active profile changes and when the app returns to the foreground.
    func refresh() async {
        guard Self.environment != nil else { return }
        permission = switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
        if permission == .authorized, client?.view.active?.push_enabled == true, !registrationPaused {
            registerWithAPNs()
        }
    }

    /// Profile's switch. Turning notifications on asks for permission first and
    /// does nothing if it's denied. Turning them off throws if the server can't
    /// be told, and leaves them on.
    func setEnabled(_ enabled: Bool) async throws {
        guard let client, pendingEnabled == nil else { return }
        pendingEnabled = enabled
        defer { pendingEnabled = nil }
        if enabled {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refresh()
            guard permission == .authorized else { return }
        }
        _ = try await client.call("push_enable", ["enabled": enabled])
        if enabled {
            registrationPaused = false
            registerWithAPNs()
            await sync()
        }
    }

    /// The token arrives in `registered(_:)`; APNs hands back the same one while it's valid.
    private func registerWithAPNs() {
        #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
        #else
            NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func registered(_ deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await sync() }
    }

    /// Registers the token for the active profile when it has notifications on.
    /// A device token reaches one sign-in at a time, so this runs again whenever
    /// the active profile changes, and on every return to the foreground to keep
    /// the registration fresh.
    func sync() async {
        guard !registrationPaused, let client, client.view.active?.push_enabled == true, let token,
              let environment = Self.environment else { return }
        var args: [String: Any] = [
            "installation_id": UUID().uuidString.lowercased(),
            "platform": Self.platform,
            "token": token,
            "environment": environment,
        ]
        #if os(iOS)
            // The device list shows the model, as the Tuist app's does.
            args["name"] = DeviceModel.name
        #endif
        _ = try? await client.call("push_register", args)
    }

    /// Signs out of the active profile. When the server couldn't be told, for
    /// example offline, it would keep notifying this device, so the device token
    /// is invalidated too, as the Tuist app does, and stays so until the next
    /// launch or until the person turns notifications on again.
    func signOut() async {
        guard let client else { return }
        await ThreadLiveActivity.shared.signOut()
        do {
            let data = try await client.call("sign_out")
            if data["push_unregister_failed"] as? Bool == true {
                #if os(iOS)
                    UIApplication.shared.unregisterForRemoteNotifications()
                #else
                    NSApplication.shared.unregisterForRemoteNotifications()
                #endif
                token = nil
                registrationPaused = true
            }
        } catch {
            client.error = error.localizedDescription
        }
    }

    private func open(url: String, account: String?, user: String?) async {
        guard let client else {
            pendingTap = (url, account, user)
            return
        }
        var args: [String: Any] = ["url": url]
        if let account { args["account"] = account }
        if let user { args["user"] = user }
        await client.perform("open_notification", args)
        #if os(macOS)
            NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        // Dismissing a notification opens nothing.
        let url = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? info["url"] as? String : nil
        let account = info["account"] as? String
        let user = info["user"] as? String
        Task { @MainActor in
            if let url { await self.open(url: url, account: account, user: user) }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let thread = notification.request.content.userInfo["thread_id"] as? String
        Task { @MainActor in
            // The open conversation already shows its reply.
            let showing = thread != nil && self.client?.view.navigation.thread_id == thread
            completionHandler(showing ? [] : [.banner, .list, .sound])
        }
    }
}

#if os(iOS)
    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            PushNotifications.shared.configure()
            // A background launch has no scene to boot the core, and a Live
            // Activity the server started needs it to register its token.
            Task { @MainActor in await AppClient.shared.start() }
            return true
        }

        func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            PushNotifications.shared.registered(deviceToken)
        }
    }
#else
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationWillFinishLaunching(_: Notification) {
            PushNotifications.shared.configure()
        }

        func application(_: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            PushNotifications.shared.registered(deviceToken)
        }
    }
#endif
