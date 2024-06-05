import Foundation
import TSCBasic

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
