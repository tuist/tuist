import Foundation
import TSCBasic

/// Tasks plugin model
public struct PluginTasks: Equatable {
    /// Name of the plugin.
    public let name: String
    /// Path to `Tasks` directory where all tasks are located.
    public let path: AbsolutePath

    public init(
        name: String,
        path: AbsolutePath
    ) {
        self.name = name
        self.path = path
    }
}
