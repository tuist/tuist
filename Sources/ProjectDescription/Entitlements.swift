import Foundation

// MARK: - Entitlements

public enum Entitlements: Codable, Equatable {
    /// The path to an existing .entitlements file.
    case file(path: Path)

    /// A dictionary with the entitlements content. Tuist generates the .entitlements file at the generation time.
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

// MARK: - Entitlements - ExpressibleByStringInterpolation

extension Entitlements: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .file(path: Path(value))
    }
}
