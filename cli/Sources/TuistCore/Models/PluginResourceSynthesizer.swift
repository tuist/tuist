import Foundation
import Path

/// Resource synthesizer plugin model
public struct PluginResourceSynthesizer: Equatable {
    /// Name of the plugin
    public let name: String
    /// Path to `ResourceSynthesizers` directory where all resource templates are located
    public let path: AbsolutePath

    public init(
        name: String,
        path: AbsolutePath
    ) {
        self.name = name
        self.path = path
    }
}

#if DEBUG
    extension PluginResourceSynthesizer {
        public static func test(
            name: String = "Plugin",
            path: AbsolutePath = try! AbsolutePath(validating: "/test") // swiftlint:disable:this force_try
        ) -> Self {
            .init(
                name: name,
                path: path
            )
        }
    }
#endif
