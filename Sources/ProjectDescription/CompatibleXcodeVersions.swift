import Foundation

/// Enum that represents all the Xcode versions that a project or set of projects is compatible with.
public enum CompatibleXcodeVersions: ExpressibleByArrayLiteral, ExpressibleByStringInterpolation, Codable, Equatable {
    /// The project supports all Xcode versions.
    case all

    case exact(Version)

    case upToNextMajor(Version)

    case upToNextMinor(Version)

    /// List of versions that are supported by the project.
    case list([CompatibleXcodeVersions])

    // MARK: - ExpressibleByArrayLiteral

    public init(arrayLiteral elements: [CompatibleXcodeVersions]) {
        self = .list(elements.map { $0 })
    }

    public init(arrayLiteral elements: CompatibleXcodeVersions...) {
        self = .list(elements.map { $0 })
    }

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    // MARK: - ExpressibleByStringInterpolation

    public init(stringLiteral value: String) {
        self = .exact("\(value)")
    }

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode("all", forKey: .type)
        case let .exact(version):
            try container.encode("exact", forKey: .type)
            try container.encode(version, forKey: .value)
        case let .upToNextMajor(version):
            try container.encode("upToNextMajor", forKey: .type)
            try container.encode(version, forKey: .value)
        case let .upToNextMinor(version):
            try container.encode("upToNextMinor", forKey: .type)
            try container.encode(version, forKey: .value)
        case let .list(versions):
            try container.encode("list", forKey: .type)
            try container.encode(versions, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "all":
            self = .all
        case "exact":
            self = .exact(try container.decode(Version.self, forKey: .value))
        case "upToNextMajor":
            self = .upToNextMajor(try container.decode(Version.self, forKey: .value))
        case "upToNextMinor":
            self = .upToNextMinor(try container.decode(Version.self, forKey: .value))
        case "list":
            self = .list(try container.decode([CompatibleXcodeVersions].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: CodingKeys.type,
                in: container,
                debugDescription: "Invalid type \(type)"
            )
        }
    }
}
