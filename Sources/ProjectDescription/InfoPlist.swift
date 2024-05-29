import Foundation

// MARK: - InfoPlist

/// A info plist from a file, a custom dictonary or a extended defaults.
public enum InfoPlist: Codable, Equatable, Sendable {
    /// The path to an existing Info.plist file.
    case file(path: Path)

    /// A dictionary with the Info.plist content. Tuist generates the Info.plist file at the generation time.
    case dictionary([String: Plist.Value])

    /// Generate an Info.plist file with the default content for the target product extended with the values in the given
    /// dictionary.
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
        self = .file(path: .path(value))
    }
}
