import Foundation

/// Options of compatibles Xcode versions.
public enum CompatibleXcodeVersions: ExpressibleByArrayLiteral, ExpressibleByStringInterpolation, Codable, Equatable {
    /// The project supports all Xcode versions.
    case all

    /// The project supports only a specific Xcode version.
    case exact(Version)

    /// The project supports all Xcode versions from the specified version up to but not including the next major version.
    case upToNextMajor(Version)

    /// The project supports all Xcode versions from the specified version up to but not including the next minor version.
    case upToNextMinor(Version)

    /// List of versions that are supported by the project.
    case list([CompatibleXcodeVersions])

    // MARK: - ExpressibleByArrayLiteral

    public init(arrayLiteral elements: [CompatibleXcodeVersions]) {
        self = .list(elements)
    }

    public init(arrayLiteral elements: CompatibleXcodeVersions...) {
        self = .list(elements)
    }

    // MARK: - ExpressibleByStringInterpolation

    public init(stringLiteral value: String) {
        self = .exact(Version(stringLiteral: value))
    }
}
