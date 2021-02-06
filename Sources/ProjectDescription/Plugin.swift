import Foundation

/// A `Plugin` manifest allows for defining extensions for Tuist.
///
/// Supported plugins include:
/// - ProjectDescriptionHelpers
///     - These are plugins designed to be usable by any other manifest excluding `Config` and `Plugin`.
///     - The source files for these helpers must live under a ProjectDescriptionHelpers directory in the location where `Plugin` manifest lives.
///
public struct Plugin: Codable, Equatable {
    /// The name of the `Plugin`.
    public let name: String

    /// Creates a `Plugin`.
    /// - Parameters:
    ///     - name: The name of the plugin.
    public init(name: String) {
        self.name = name
        dumpIfNeeded(self)
    }
}
