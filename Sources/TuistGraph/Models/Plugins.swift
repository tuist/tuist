import Foundation

/// A model which contains all loaded plugin representations.
public struct Plugins: Equatable {
    /// List of the loaded custom helper plugins.
    public let projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin]

    /// Creates a `Plugins`.
    ///
    /// - Parameters:
    ///     - projectDescriptionHelpers: List of the loaded helper plugins.
    public init(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin]
    ) {
        self.projectDescriptionHelpers = projectDescriptionHelpers
    }

    /// An empty `Plugins`.
    public static let none: Plugins = .init(projectDescriptionHelpers: [])
}
