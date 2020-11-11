import Foundation

/// A model which contains all loaded plugin representations.
public struct Plugins: Equatable {
    /// List of the loaded custom helper plugins.
    public let projectDescriptionHelpers: [CustomProjectDescriptionHelpers]

    /// Creates a `Plugins`.
    /// - Parameter projectDescriptionHelpers: List of the loaded custom helper plugins.
    public init(
        projectDescriptionHelpers: [CustomProjectDescriptionHelpers]
    ) {
        self.projectDescriptionHelpers = projectDescriptionHelpers
    }

    /// An empty `Plugins`.
    public static let none: Plugins = .init(projectDescriptionHelpers: [])
}
