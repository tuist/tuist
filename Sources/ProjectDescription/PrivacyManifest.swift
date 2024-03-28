import Foundation

// MARK: - PrivacyManifest

public enum PrivacyManifest: Codable, Equatable {
    /// The path to an existing .xcprivacy file.
    case file(path: Path)

    /// A dictionary with the privacy manifest content. Tuist generates the .xcprivacy file at the generation time.
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

// MARK: - PrivacyManifest - ExpressibleByStringInterpolation

extension PrivacyManifest: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .file(path: .path(value))
    }
}
