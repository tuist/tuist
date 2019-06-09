import Foundation

public enum InfoPlist: Codable {
    public indirect enum Value: Codable {
        case string(String)
        case integer(Int)
        case boolean(Bool)
        case dictionary([String: Value])
        case array([Value])

        public func encode(to encoder: Encoder) throws {
            switch self {
            case let .string(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .integer(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .boolean(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .dictionary(value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case let .array(value):
                var container = encoder.unkeyedContainer()
                try container.encode(contentsOf: value)
            }
        }

        public init(from decoder: Decoder) throws {
            if let singleValueContainer = try? decoder.singleValueContainer() {
                if let value: String = try? singleValueContainer.decode(String.self) {
                    self = .string(value)
                    return
                } else if let value: Int = try? singleValueContainer.decode(Int.self) {
                    self = .integer(value)
                    return
                } else if let value: Bool = try? singleValueContainer.decode(Bool.self) {
                    self = .boolean(value)
                    return
                } else if let value: [String: Value] = try? singleValueContainer.decode([String: Value].self) {
                    self = .dictionary(value)
                    return
                }
            }
            
            if var unkeyedContainer = try? decoder.unkeyedContainer() {
                self = try .array(unkeyedContainer.decode([Value].self))
            } else {
                preconditionFailure("unsupported container type")
            }
        }
    }

    case file(path: String)
    case dictionary([String: Value])

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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(path):
            try container.encode("file", forKey: .type)
            try container.encode(path, forKey: .value)
        case let .dictionary(dictionary):
            try container.encode("dictionary", forKey: .type)
            try container.encode(dictionary, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "file":
            self = .file(path: try container.decode(String.self, forKey: .value))
        case "dictionary":
            self = .dictionary(try container.decode([String: Value].self, forKey: .value))
        default:
            preconditionFailure("unsupported type")
        }
    }
}

// MARK: - InfoPlist - ExpressibleByStringLiteral

extension InfoPlist: ExpressibleByStringLiteral, ExpressibleByUnicodeScalarLiteral, ExpressibleByExtendedGraphemeClusterLiteral {
    public typealias UnicodeScalarLiteralType = String
    public typealias ExtendedGraphemeClusterLiteralType = String
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = .file(path: value)
    }
}

// MARK: - InfoPlist.Value - ExpressibleByStringLiteral

extension InfoPlist.Value: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - InfoPlist.Value - ExpressibleByIntegerLiteral

extension InfoPlist.Value: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

// MARK: - InfoPlist.Value - ExpressibleByBooleanLiteral

extension InfoPlist.Value: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

// MARK: - InfoPlist.Value - ExpressibleByDictionaryLiteral

extension InfoPlist.Value: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, InfoPlist.Value)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - InfoPlist.Value - ExpressibleByArrayLiteral

extension InfoPlist.Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: InfoPlist.Value...) {
        self = .array(elements)
    }
}
