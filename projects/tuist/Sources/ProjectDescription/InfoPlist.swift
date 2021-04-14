import Foundation

public enum InfoPlist: Codable, Equatable {
    public indirect enum Value: Codable, Equatable {
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
                var container = encoder.singleValueContainer()
                try container.encode(value)
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
                } else if let value: [Value] = try? singleValueContainer.decode([Value].self) {
                    self = .array(value)
                } else {
                    preconditionFailure("unsupported container type")
                }
            } else {
                preconditionFailure("unsupported container type")
            }
        }

        public static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case let (.string(lhsValue), .string(rhsValue)):
                return lhsValue == rhsValue
            case let (.integer(lhsValue), .integer(rhsValue)):
                return lhsValue == rhsValue
            case let (.boolean(lhsValue), .boolean(rhsValue)):
                return lhsValue == rhsValue
            case let (.dictionary(lhsValue), .dictionary(rhsValue)):
                return lhsValue == rhsValue
            case let (.array(lhsValue), .array(rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }
    }

    /// Use an existing Info.plist file.
    case file(path: Path)

    /// Generate an Info.plist file with the content in the given dictionary.
    case dictionary([String: Value])

    /// Generate an Info.plist file with the default content for the target product extended with the values in the given dictionary.
    case extendingDefault(with: [String: Value])

    /// Default value.
    public static var `default`: InfoPlist {
        .extendingDefault(with: [:])
    }

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

    public var path: Path? {
        switch self {
        case let .file(path):
            return path
        default:
            return nil
        }
    }

    // MARK: - Equatable

    public static func == (lhs: InfoPlist, rhs: InfoPlist) -> Bool {
        switch (lhs, rhs) {
        case let (.file(lhsPath), .file(rhsPath)):
            return lhsPath == rhsPath
        case let (.dictionary(lhsDictionary), .dictionary(rhsDictionary)):
            return lhsDictionary == rhsDictionary
        case let (.extendingDefault(lhsDictionary), .extendingDefault(rhsDictionary)):
            return lhsDictionary == rhsDictionary
        default:
            return false
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
        case let .extendingDefault(dictionary):
            try container.encode("extended", forKey: .type)
            try container.encode(dictionary, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "file":
            self = .file(path: try container.decode(Path.self, forKey: .value))
        case "dictionary":
            self = .dictionary(try container.decode([String: Value].self, forKey: .value))
        case "extended":
            self = .extendingDefault(with: try container.decode([String: Value].self, forKey: .value))
        default:
            preconditionFailure("unsupported type")
        }
    }
}

// MARK: - InfoPlist - ExpressibleByStringInterpolation

extension InfoPlist: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .file(path: Path(value))
    }
}

// MARK: - InfoPlist.Value - ExpressibleByStringInterpolation

extension InfoPlist.Value: ExpressibleByStringInterpolation {
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
