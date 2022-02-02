import Foundation

public enum InfoPlist: Codable, Equatable {
    public indirect enum Value: Codable, Equatable {
        case string(String)
        case integer(Int)
        case real(Double)
        case boolean(Bool)
        case dictionary([String: Value])
        case array([Value])
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

    // MARK: - Internal

    public var path: Path? {
        switch self {
        case let .file(path):
            return path
        default:
            return nil
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

// MARK: - InfoPlist.Value - ExpressibleByFloatLiteral

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
