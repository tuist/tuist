import Foundation

public protocol PListTypesProtocol {}

public enum Entitlements: PListTypesProtocol, Codable, Equatable {
    /// The path to an existing Info.plist file.
    case file(path: Path)

    /// A dictionary with the Info.plist content. Tuist generates the Info.plist file at the generation time.
    case dictionary([String: PList.Value])

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

extension Entitlements: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .file(path: Path(value))
    }
}

public enum PList {
    /// It represents the values of the PList file dictionary.
    /// It ensures that the values used to define the content of the dynamically generated Info.plist files are valid
    public indirect enum Value: Codable, Equatable {
        /// It represents a string value.
        case string(String)
        /// It represents an integer value.
        case integer(Int)
        /// It represents a floating value.
        case real(Double)
        /// It represents a boolean value.
        case boolean(Bool)
        /// It represents a dictionary value.
        case dictionary([String: Value])
        /// It represents an array value.
        case array([Value])
    }
}


/// A info plist from a file, a custom dictonary or a extended defaults.
public enum InfoPlist: PListTypesProtocol, Codable, Equatable {
    /// The path to an existing Info.plist file.
    case file(path: Path)

    /// A dictionary with the Info.plist content. Tuist generates the Info.plist file at the generation time.
    case dictionary([String: PList.Value])

    /// Generate an Info.plist file with the default content for the target product extended with the values in the given dictionary.
    case extendingDefault(with: [String: PList.Value])

    /// Generate the default content for the target the InfoPlist belongs to.
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

// MARK: - PList.Value - ExpressibleByStringInterpolation

extension PList.Value: ExpressibleByStringInterpolation {
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

// MARK: - PList.Value - ExpressibleByFloatLiteral

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

// MARK: - InfoPlist.Value - ExpressibleByArrayLiteral

extension PList.Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: PList.Value...) {
        self = .array(elements)
    }
}
