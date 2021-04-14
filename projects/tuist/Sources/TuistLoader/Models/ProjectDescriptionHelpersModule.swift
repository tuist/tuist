import Foundation
import TSCBasic

/// Defines a module for a project description helper.
/// Project description helpers are modules which can be imported wherever "ProjectDescription" can be imported.
public struct ProjectDescriptionHelpersModule: Equatable, Hashable {
    /// The name of the helpers module.
    public let name: String
    /// The absolute path to the module.
    public let path: AbsolutePath

    /// Creates a ProjectDescriptionHelpersModule.
    /// - Parameters:
    ///   - name: The name of the helpers module.
    ///   - path: The absolute path to the module.
    public init(
        name: String,
        path: AbsolutePath
    ) {
        self.name = name
        self.path = path
    }
}
