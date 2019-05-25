import Foundation

public enum InfoPlist: Codable {
    case local(path: String)

    // MARK: - Error

    public enum CodingError: Error {
        case invalidType(String)
    }

    // MARK: - Coding keys

    enum CodingKeys: CodingKey {
        case type
        case path
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "local" {
            self = .local(path: try container.decode(String.self, forKey: .path))
        } else {
            throw CodingError.invalidType(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .local(path):
            try container.encode("local", forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension InfoPlist: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .local(path: value)
    }
}
