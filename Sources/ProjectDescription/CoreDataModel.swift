import Foundation

/// Core Data model.
public struct CoreDataModel: Codable, Equatable {
    /// Relative path to the model.
    public let path: Path

    /// Current version (with or without extension)
    public let currentVersion: String?

    public enum CodingKeys: String, CodingKey {
        case path
        case currentVersion = "current_version"
    }

    /// Initializes the build file with its attributes.
    ///
    /// - Parameters:
    ///   - path: relative path to the Core Data model.
    ///   - currentVersion: current version name (with or without the extension).
    public init(_ path: Path,
                currentVersion: String? = nil) {
        self.path = path
        self.currentVersion = currentVersion
    }
}
