import Foundation
import TSCBasic

public protocol PListTypesProtocol {}

public enum Entitlements: PListTypesProtocol, Equatable, Codable {
    // Path to a user defined info.plist file (already exists on disk).
    case file(path: AbsolutePath)

    // Path to a generated info.plist file (may not exist on disk at the time of project generation).
    // Data of the generated file
    case generatedFile(path: AbsolutePath, data: Data)

    // User defined dictionary of keys/values for an info.plist file.
    case dictionary([String: PList.Value])

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

public enum PList {
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

public enum InfoPlist: PListTypesProtocol, Equatable, Codable {
    // Path to a user defined info.plist file (already exists on disk).
    case file(path: AbsolutePath)

    // Path to a generated info.plist file (may not exist on disk at the time of project generation).
    // Data of the generated file
    case generatedFile(path: AbsolutePath, data: Data)

    // User defined dictionary of keys/values for an info.plist file.
    case dictionary([String: PList.Value])

    // User defined dictionary of keys/values for an info.plist file extending the default set of keys/values
    // for the target type.
    case extendingDefault(with: [String: PList.Value])

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

// MARK: - PList.Value - ExpressibleByStringLiteral

extension PList.Value: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - PList.Value - ExpressibleByIntegerLiteral

extension PList.Value: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

// MARK: - PList.Value - ExpressibleByIntegerLiteral

extension PList.Value: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .real(value)
    }
}

// MARK: - PList.Value - ExpressibleByBooleanLiteral

extension PList.Value: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

// MARK: - PList.Value - ExpressibleByDictionaryLiteral

extension PList.Value: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, PList.Value)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - PList.Value - ExpressibleByArrayLiteral

extension PList.Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: PList.Value...) {
        self = .array(elements)
    }
}

// MARK: - Dictionary (PList.Value)

extension Dictionary where Value == PList.Value {
    public func unwrappingValues() -> [Key: Any] {
        mapValues { $0.value }
    }
}
