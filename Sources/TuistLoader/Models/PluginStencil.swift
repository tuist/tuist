import Foundation
import TSCBasic

/// Stencil plugin model
public struct PluginStencil: Equatable {
    /// Name of the plugin
    public let name: String
    /// Path to `Stencil` directory where all resource templates are located
    public let path: AbsolutePath

    public init(
        name: String,
        path: AbsolutePath
    ) {
        self.name = name
        self.path = path
    }
}
