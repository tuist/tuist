import Foundation
import TSCBasic

/// A model representing a custom `ProjectDescription` helper.
public struct CustomProjectDescriptionHelpers: Equatable {
    /// The name of the helper module.
    public let name: String
    /// The path to `Plugin` manifest for this helper.
    public let path: AbsolutePath

    /// Creates a `CustomProjectDescriptionHelpers`.
    /// - Parameters:
    ///   - name: The name of the helper module.
    ///   - path: The path to `Plugin` manifest for this helper.
    public init(
        name: String,
        path: AbsolutePath
    ) {
        self.name = name
        self.path = path
    }
}
