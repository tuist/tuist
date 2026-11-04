import TuistLogging
import UIKit

public final class PushNotificationsAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotifications.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    public func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.current.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}
