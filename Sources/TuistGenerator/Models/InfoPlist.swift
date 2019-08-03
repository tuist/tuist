import Basic
import Foundation
import TuistCore

public enum InfoPlist: Equatable {
    public indirect enum Value: Equatable {
        case string(String)
        case integer(Int)
        case boolean(Bool)
        case dictionary([String: Value])
        case array([Value])

        var value: Any {
            switch self {
            case let .array(array):
                return array.map { $0.value }
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

    case file(path: AbsolutePath)
    case dictionary([String: Value])
    case extendingDefault(with: [String: Value])

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

    // MARK: - Public

    public var path: AbsolutePath? {
        switch self {
        case let .file(path):
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

// MARK: - Dictionary (InfoPlist.Value)

extension Dictionary where Value == InfoPlist.Value {
    func unwrappingValues() -> [Key: Any] {
        return mapValues { $0.value }
    }
}
