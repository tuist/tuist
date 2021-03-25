import Foundation
import TSCBasic

/// A model which contains all loaded plugin representations.
public struct Plugins: Equatable {
    /// List of the loaded custom helper plugins.
    public let projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin]

    /// List of paths to template definitions.
    public let templateDirectories: [AbsolutePath]

    /// Creates a `Plugins`.
    ///
    /// - Parameters:
    ///     - projectDescriptionHelpers: List of the loaded helper plugins.
    ///     - templatePaths: List of paths to the `Templates/` directory for the loaded plugins.
    public init(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin],
        templatePaths: [AbsolutePath]
    ) {
        self.projectDescriptionHelpers = projectDescriptionHelpers
        templateDirectories = templatePaths
    }

    /// An empty `Plugins`.
    public static let none: Plugins = .init(
        projectDescriptionHelpers: [],
        templatePaths: []
    )
}
