import Foundation
@_implementationOnly import Sentry

public enum CrashManager {
    public static func start() {
        SentrySDK.start { options in
            options.dsn = "___PUBLIC_DSN___"
            options.debug = true
        }
    }
}
