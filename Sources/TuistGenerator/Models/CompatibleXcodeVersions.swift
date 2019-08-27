import Foundation

/// Enum that represents all the Xcode versions that a project or set of projects is compatible with.
public enum CompatibleXcodeVersions: Equatable, Hashable, ExpressibleByArrayLiteral {
    /// The project supports all Xcode versions.
    case all

    /// List of versions that are supported by the project.
    case list([String])

    // MARK: - ExpressibleByArrayLiteral

    public init(arrayLiteral elements: [String]) {
        self = .list(elements)
    }

    public init(arrayLiteral elements: String...) {
        self = .list(elements)
    }
}
