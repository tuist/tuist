import Foundation

/// Enum that represents all the Xcode versions that a project or set of projects is compatible with.
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

    // MARK: - Codable

    private enum Kind: String, Codable {
        case all
        case exact
        case upToNextMajor
        case upToNextMinor
        case list
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case version
        case compatibleXcodeVersions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .all:
            self = .all
        case .exact:
            let version = try container.decode(Version.self, forKey: .version)
            self = .exact(version)
        case .upToNextMajor:
            let version = try container.decode(Version.self, forKey: .version)
            self = .upToNextMajor(version)
        case .upToNextMinor:
            let version = try container.decode(Version.self, forKey: .version)
            self = .upToNextMinor(version)
        case .list:
            let compatibleXcodeVersions = try container.decode([CompatibleXcodeVersions].self, forKey: .compatibleXcodeVersions)
            self = .list(compatibleXcodeVersions)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode(Kind.all.self, forKey: .kind)
        case let .exact(version):
            try container.encode(Kind.exact.self, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .upToNextMajor(version):
            try container.encode(Kind.upToNextMajor.self, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .upToNextMinor(version):
            try container.encode(Kind.upToNextMinor.self, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .list(compatibleXcodeVersions):
            try container.encode(Kind.list.self, forKey: .kind)
            try container.encode(compatibleXcodeVersions, forKey: .compatibleXcodeVersions)
        }
    }
}
