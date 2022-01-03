import Foundation
import struct ProjectDescription.Version

/// Enum that represents all the Xcode versions that a project or set of projects is compatible with.
public enum CompatibleXcodeVersions: Equatable, Hashable, ExpressibleByArrayLiteral, ExpressibleByStringInterpolation,
    CustomStringConvertible
{
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

    public func isCompatible(versionString: String) -> Bool {
        let xCodeVersion: Version = "\(versionString)"

        switch self {
        case .all:
            return true
        case let .exact(version):
            return version == xCodeVersion
        case let .upToNextMajor(version):
            return xCodeVersion.major == version.major && xCodeVersion >= version
        case let .upToNextMinor(version):
            return version.major == xCodeVersion.major && version.minor == xCodeVersion.minor && xCodeVersion >= version
        case let .list(versions):
            return versions.contains { $0.isCompatible(versionString: versionString) }
        }
    }

    // MARK: - ExpressibleByStringInterpolation

    public init(stringLiteral value: String) {
        self = .exact(Version(stringLiteral: value))
    }

    // MARK: - ExpressibleByArrayLiteral

    public init(arrayLiteral elements: [CompatibleXcodeVersions]) {
        self = .list(elements)
    }

    public init(arrayLiteral elements: CompatibleXcodeVersions...) {
        self = .list(elements)
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .all:
            return "all"
        case let .exact(version):
            return "\(version)"
        case let .upToNextMajor(version):
            return "\(version)..<\(version.major + 1).0.0"
        case let .upToNextMinor(version):
            return "\(version)..<\(version.major).\(version.minor + 1).0"
        case let .list(versions):
            return "\(versions.map(\.description).joined(separator: " or "))"
        }
    }
}
