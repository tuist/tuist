import Foundation

public enum InfoPlist: Codable {
    case file(path: String)

    // MARK: - Error

    public enum CodingError: Error {
        case invalidType(String)
    }

    // MARK: - Coding keys

    enum CodingKeys: CodingKey {
        case type
        case path
    }

    // MARK: - Internal

    var path: String {
        switch self {
        case let .file(path):
            return path
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "file" {
            self = .file(path: try container.decode(String.self, forKey: .path))
        } else {
            throw CodingError.invalidType(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(path):
            try container.encode("file", forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension InfoPlist: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral {
    public typealias UnicodeScalarLiteralType = String
    public typealias ExtendedGraphemeClusterLiteralType = String
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = .file(path: value)
    }
}
