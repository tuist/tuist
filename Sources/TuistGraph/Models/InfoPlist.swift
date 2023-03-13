import Foundation
import TSCBasic

public enum InfoPlist: Equatable, Codable {
    public indirect enum Value: Equatable, Codable {
        case string(String)
        case integer(Int)
        case real(Double)
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
            case let .real(double):
                return double
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
        self = .file(path: try! AbsolutePath(validating: value)) // swiftlint:disable:this force_try
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

// MARK: - InfoPlist.Value - ExpressibleByIntegerLiteral

extension InfoPlist.Value: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .real(value)
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
    public func unwrappingValues() -> [Key: Any] {
        mapValues { $0.value }
    }
}
