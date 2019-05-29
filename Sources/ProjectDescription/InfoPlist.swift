import Foundation

public enum InfoPlist: Codable {
    case file(path: String)
    case dictionary([String: Any])

    // MARK: - Error

    public enum CodingError: Error {
        case invalidType(String)
    }

    // MARK: - Coding keys

    enum CodingKeys: CodingKey {
        case type
        case value
    }

    // MARK: - Internal

    var path: String? {
        switch self {
        case let .file(path):
            return path
        default:
            return nil
        }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "file" {
            self = .file(path: try container.decode(String.self, forKey: .value))
        } else if type == "dictionary" {
            // Codable doesn't support encoding values of type [String: Any]
            // Until Swift supports it, we workaround it by serializing the value into a JSON string and then encoding it.
            // https://bugs.swift.org/browse/SR-7788
            let dictionaryJson = Data(base64Encoded: try container.decode(String.self, forKey: .value))!
            let dictionary = try JSONSerialization.jsonObject(with: dictionaryJson, options: []) as! [String: Any]
            self = .dictionary(dictionary)
        } else {
            throw CodingError.invalidType(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(path):
            try container.encode("file", forKey: .type)
            try container.encode(path, forKey: .value)
        case let .dictionary(dictionary):
            try container.encode("dictionary", forKey: .type)

            // Codable doesn't support encoding values of type [String: Any]
            // Until Swift supports it, we workaround it by serializing the value into a JSON string and then encoding it.
            // https://bugs.swift.org/browse/SR-7788
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
            try container.encode(data.base64EncodedString(), forKey: .value)
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
