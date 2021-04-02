import Foundation
import TSCBasic

/// Resource synthesizer plugin model
public struct ResourceSynthesizerPlugin: Equatable {
    /// Name of the plugin
    public let name: String
    /// Path to `ResourceTemplates` directory where all resource templates are located
    public let path: AbsolutePath
    
    public init(
        name: String,
        path: AbsolutePath
    ) {
        self.name = name
        self.path = path
    }
}

/// A model which contains all loaded plugin representations.
public struct Plugins: Equatable {
    /// List of the loaded custom helper plugins.
    public let projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin]

    /// List of paths to template definitions.
    public let templateDirectories: [AbsolutePath]
    
    /// List of paths pointing to resource templates
    public let resourceSynthesizers: [ResourceSynthesizerPlugin]

    /// Creates a `Plugins`.
    ///
    /// - Parameters:
    ///     - projectDescriptionHelpers: List of the loaded helper plugins.
    ///     - templatePaths: List of paths to the `Templates/` directory for the loaded plugins.
    ///     - resourceSynthesizers: List of the loaded resource synthesizer plugins
    public init(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin],
        templatePaths: [AbsolutePath],
        resourceSynthesizers: [ResourceSynthesizerPlugin]
    ) {
        self.projectDescriptionHelpers = projectDescriptionHelpers
        templateDirectories = templatePaths
        self.resourceSynthesizers = resourceSynthesizers
    }

    /// An empty `Plugins`.
    public static let none: Plugins = .init(
        projectDescriptionHelpers: [],
        templatePaths: [],
        resourceSynthesizers: []
    )
}
