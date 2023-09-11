import Foundation
import TSCBasic

// MARK: - Plist

public enum Plist {

    case infoPlist(InfoPlist)
    case entitlements(Entitlements)

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
}

// MARK: - Plist.Value - ExpressibleByStringLiteral

extension Plist.Value: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - Plist.Value - ExpressibleByIntegerLiteral

extension Plist.Value: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

// MARK: - Plist.Value - ExpressibleByIntegerLiteral

extension Plist.Value: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .real(value)
    }
}

// MARK: - Plist.Value - ExpressibleByBooleanLiteral

extension Plist.Value: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

// MARK: - Plist.Value - ExpressibleByDictionaryLiteral

extension Plist.Value: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Plist.Value)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Plist.Value - ExpressibleByArrayLiteral

extension Plist.Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Plist.Value...) {
        self = .array(elements)
    }
}

// MARK: - Dictionary (Plist.Value)

extension Dictionary where Value == Plist.Value {
    public func unwrappingValues() -> [Key: Any] {
        mapValues { $0.value }
    }
}

// MARK: - InfoPlist

public enum InfoPlist: Equatable, Codable {
    // Path to a user defined info.plist file (already exists on disk).
    case file(path: AbsolutePath)

    // Path to a generated info.plist file (may not exist on disk at the time of project generation).
    // Data of the generated file
    case generatedFile(path: AbsolutePath, data: Data)

    // User defined dictionary of keys/values for an info.plist file.
    case dictionary([String: Plist.Value])

    // User defined dictionary of keys/values for an info.plist file extending the default set of keys/values
    // for the target type.
    case extendingDefault(with: [String: Plist.Value])

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

// MARK: - Entitlements

public enum Entitlements: Equatable, Codable {
    // Path to a user defined info.plist file (already exists on disk).
    case file(path: AbsolutePath)

    // Path to a generated info.plist file (may not exist on disk at the time of project generation).
    // Data of the generated file
    case generatedFile(path: AbsolutePath, data: Data)

    // User defined dictionary of keys/values for an info.plist file.
    case dictionary([String: Plist.Value])

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

// MARK: - Entitlements - ExpressibleByStringLiteral

extension Entitlements: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .file(path: try! AbsolutePath(validating: value)) // swiftlint:disable:this force_try
    }
}

