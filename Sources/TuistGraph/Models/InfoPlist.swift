import Foundation
import TSCBasic

public enum InfoPlist: Equatable, Codable {
    public indirect enum Value: Equatable, Codable {
        case string(String)
        case integer(Int)
        case boolean(Bool)
        case dictionary([String: Value])
        case array([Value])

        public var value: Any {
            switch self {
            case let .array(array):
                return array.map(\.value)
            case let .boolean(boolean):
                return boolean
            case let .dictionary(dictionary):
                return dictionary.mapValues { $0.value }
            case let .integer(integer):
                return integer
            case let .string(string):
                return string
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

    // Path to a user defined info.plist file (already exists on disk).
    case file(path: AbsolutePath)

    // Path to a generated info.plist file (may not exist on disk at the time of project generation).
    // Data of the generated file
    case generatedFile(path: AbsolutePath, data: Data)

    // User defined dictionary of keys/values for an info.plist file.
    case dictionary([String: Value])

    // User defined dictionary of keys/values for an info.plist file extending the default set of keys/values
    // for the target type.
    case extendingDefault(with: [String: Value])

    // MARK: - Public

    public var path: AbsolutePath? {
        switch self {
        case let .file(path), let .generatedFile(path: path, data: _):
            return path
        default:
            return nil
        }
    }
}

// MARK: - InfoPlist - ExpressibleByStringLiteral

extension InfoPlist: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .file(path: AbsolutePath(value))
    }
}

// MARK: - InfoPlist - Codable

extension InfoPlist {
    private enum Kind: String, Codable {
        case file
        case generatedFile
        case dictionary
        case extendingDefault
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case data
        case dictionary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .file:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .file(path: path)
        case .generatedFile:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let data = try container.decode(Data.self, forKey: .data)
            self = .generatedFile(path: path, data: data)
        case .dictionary:
            let directory = try container.decode([String: Value].self, forKey: .dictionary)
            self = .dictionary(directory)
        case .extendingDefault:
            let directory = try container.decode([String: Value].self, forKey: .dictionary)
            self = .extendingDefault(with: directory)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(path):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(path, forKey: .path)
        case let .generatedFile(path, data):
            try container.encode(Kind.generatedFile, forKey: .kind)
            try container.encode(data, forKey: .data)
            try container.encode(path, forKey: .path)
        case let .dictionary(dictionary):
            try container.encode(Kind.dictionary, forKey: .kind)
            try container.encode(dictionary, forKey: .dictionary)
        case let .extendingDefault(dictionary):
            try container.encode(Kind.extendingDefault, forKey: .kind)
            try container.encode(dictionary, forKey: .dictionary)
        }
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

// MARK: - InfoPlist.Value - Codable

extension InfoPlist.Value {
    private enum Kind: String, Codable {
        case string
        case integer
        case boolean
        case dictionary
        case array
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case string
        case integer
        case boolean
        case dictionary
        case array
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .string:
            let string = try container.decode(String.self, forKey: .string)
            self = .string(string)
        case .integer:
            let integer = try container.decode(Int.self, forKey: .integer)
            self = .integer(integer)
        case .boolean:
            let boolean = try container.decode(Bool.self, forKey: .boolean)
            self = .boolean(boolean)
        case .array:
            let array = try container.decode([Value].self, forKey: .array)
            self = .array(array)
        case .dictionary:
            let dictionary = try container.decode([String: Value].self, forKey: .dictionary)
            self = .dictionary(dictionary)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(string):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(string, forKey: .string)
        case let .integer(integer):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(integer, forKey: .integer)
        case let .boolean(boolean):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(boolean, forKey: .boolean)
        case let .array(array):
            try container.encode(Kind.array, forKey: .kind)
            try container.encode(array, forKey: .array)
        case let .dictionary(dictionary):
            try container.encode(Kind.dictionary, forKey: .kind)
            try container.encode(dictionary, forKey: .dictionary)
        }
    }
}

// MARK: - Dictionary (InfoPlist.Value)

extension Dictionary where Value == InfoPlist.Value {
    public func unwrappingValues() -> [Key: Any] {
        mapValues { $0.value }
    }
}
