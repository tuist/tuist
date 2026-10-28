import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import UserNotifications

/// Injectable OS boundary keeps unhosted tests out of app registration and permission prompts.
@MainActor
struct AtlasPushSystem {
    var requestAuthorization: () async throws -> Bool
    var authorizationStatus: () async -> UNAuthorizationStatus
    var register: () -> Void
    var unregister: () -> Void
    var clearNotifications: () -> Void
    var environment: () -> String?

    static var current: Self {
        Self(
            requestAuthorization: {
                try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            },
            authorizationStatus: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
            register: {
                #if os(iOS)
                UIApplication.shared.registerForRemoteNotifications()
                #else
                NSApplication.shared.registerForRemoteNotifications()
                #endif
            },
            unregister: {
                #if os(iOS)
                UIApplication.shared.unregisterForRemoteNotifications()
                #else
                NSApplication.shared.unregisterForRemoteNotifications()
                #endif
            },
            clearNotifications: {
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            },
            environment: { environment(from: Bundle.main.object(forInfoDictionaryKey: "AtlasPushEnvironment") as? String) }
        )
    }

    static func environment(from stamp: String?) -> String? {
        switch stamp {
        case "development": "sandbox"
        case "production": "production"
        default: nil
        }
    }

    static var platform: String {
        #if os(iOS)
        "ios"
        #else
        "macos"
        #endif
    }

    static var settingsName: String { platform == "macos" ? "System Settings" : "iOS Settings" }
}
