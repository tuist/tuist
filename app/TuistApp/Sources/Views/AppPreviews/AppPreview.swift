import Foundation

struct AppPreview: Identifiable, Codable, Equatable {
    let fullHandle: String
    let displayName: String
    let bundleIdentifier: String

    var id: String {
        bundleIdentifier
    }
}

#if DEBUG
    extension AppPreview {
        static func test(
            fullHandle: String = "tuist/tuist",
            displayName: String = "App",
            bundleIdentifier: String = "com.tuist.app"
        ) -> Self {
            .init(
                fullHandle: fullHandle,
                displayName: displayName,
                bundleIdentifier: bundleIdentifier
            )
        }
    }
#endif
