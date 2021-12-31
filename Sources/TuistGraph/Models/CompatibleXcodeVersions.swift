import Foundation
import struct ProjectDescription.Version

/// Enum that represents all the Xcode versions that a project or set of projects is compatible with.
public enum CompatibleXcodeVersions: Equatable, Hashable, ExpressibleByArrayLiteral, ExpressibleByStringInterpolation,
    CustomStringConvertible
{
    /// The project supports all Xcode versions.
    case all

    case exact(Version)

    case upToNextMajor(Version)

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
            return xCodeVersion == version || (xCodeVersion.major == version.major  && xCodeVersion >= version)
        case let .upToNextMinor(version):
            return version == xCodeVersion ||
                (version.major == xCodeVersion.major && version.minor == xCodeVersion.minor && xCodeVersion > version)
        case let .list(versions):
            return versions.contains { $0.isCompatible(versionString: versionString) }
        }
    }

    // MARK: - ExpressibleByStringInterpolation

    public init(stringLiteral value: String) {
        self = .exact(Version(stringLiteral: value))
    }

    // MARK: - ExpressibleByArrayLiteral

    public init(arrayLiteral elements: [String]) {
        self = .list(elements.map { "\($0)" })
    }

    public init(arrayLiteral elements: String...) {
        self = .list(elements.map { "\($0)" })
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .all:
            return "all"
        case let .exact(version):
            return "\(version)"
        case let .upToNextMajor(version):
            return ".upToNextMajor(\(version))"
        case let .upToNextMinor(version):
            return ".upToNextMinor(\(version))"
        case let .list(versions):
            return "\(versions.map(\.description).joined(separator: ", "))"
        }
    }
}
