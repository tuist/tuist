import Foundation
import TSCBasic

/// A model representing a custom `ProjectDescription` helper.
public struct ProjectDescriptionHelpersPlugin: Equatable {
    /// Possible locations for a ProjectDescriptionHelpersPlugin
    public enum Location: Equatable {
        /// A plugin local to the current file system.
        case local
        /// A plugin on a remote server.
        case remote
    }

    /// The name of the helper module.
    public let name: String
    /// The path to `Plugin` manifest for this helper.
    public let path: AbsolutePath
    /// The type of location for the plugin.
    public let location: Location

    /// Creates a `ProjectDescriptionHelpersPlugin`.
    /// - Parameters:
    ///   - name: The name of the helper module.
    ///   - path: The path to `Plugin` manifest for this helper.
    ///   - location: The type of location for the plugin.
    public init(
        name: String,
        path: AbsolutePath,
        location: Location
    ) {
        self.name = name
        self.path = path
        self.location = location
    }
}
