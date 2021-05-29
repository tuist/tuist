import Foundation

/// Enum that represents all the Xcode versions that a project or set of projects is compatible with.
public enum CompatibleXcodeVersions: ExpressibleByArrayLiteral, ExpressibleByStringInterpolation, Codable, Equatable {
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

    enum CodignKeys: String, CodingKey {
        case type
        case value
    }

    // MARK: - ExpressibleByStringInterpolation

    public init(stringLiteral value: String) {
        self = .list([value])
    }

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodignKeys.self)
        switch self {
        case .all:
            try container.encode("all", forKey: .type)
        case let .list(versions):
            try container.encode("list", forKey: .type)
            try container.encode(versions, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodignKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "all":
            self = .all
        case "list":
            self = .list(try container.decode([String].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: CodignKeys.type, in: container, debugDescription: "Invalid type \(type)")
        }
    }
}
