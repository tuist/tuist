import Foundation

struct AppPreview: Identifiable, Codable, Equatable {
    let fullHandle: String
    let displayName: String
    let bundleIdentifier: String
    let iconURL: URL

    var id: String {
        bundleIdentifier
    }
}

#if DEBUG
    extension AppPreview {
        static func test(
            fullHandle: String = "tuist/tuist",
            displayName: String = "App",
            bundleIdentifier: String = "dev.tuist.app",
            iconURL: URL =
                URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/icon.png")!
            // swiftlint:disable:this force_try
        ) -> Self {
            .init(
                fullHandle: fullHandle,
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                iconURL: iconURL
            )
        }
    }
#endif
