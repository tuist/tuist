import Foundation

public protocol PlistTypesProtocol {}

public enum Entitlements: PlistTypesProtocol, Codable, Equatable {
    /// The path to an existing Info.plist file.
    case file(path: Path)

    /// A dictionary with the Info.plist content. Tuist generates the Info.plist file at the generation time.
    case dictionary([String: Plist.Value])

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

public enum Plist {
    /// It represents the values of the Plist file dictionary.
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
public enum InfoPlist: PlistTypesProtocol, Codable, Equatable {
    /// The path to an existing Info.plist file.
    case file(path: Path)

    /// A dictionary with the Info.plist content. Tuist generates the Info.plist file at the generation time.
    case dictionary([String: Plist.Value])

    /// Generate an Info.plist file with the default content for the target product extended with the values in the given dictionary.
    case extendingDefault(with: [String: Plist.Value])

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

// MARK: - Plist.Value - ExpressibleByStringInterpolation

extension Plist.Value: ExpressibleByStringInterpolation {
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

// MARK: - Plist.Value - ExpressibleByFloatLiteral

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

// MARK: - InfoPlist.Value - ExpressibleByArrayLiteral

extension Plist.Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Plist.Value...) {
        self = .array(elements)
    }
}

// MARK: - InfoPlist API compatibility
extension InfoPlist {
    @available(*, deprecated, message: "InfoPlist.Value was renamed to Plist.Value")
    public typealias Value = Plist.Value
}
