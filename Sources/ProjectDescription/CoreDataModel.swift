import Foundation

/// Core Data model.
public struct CoreDataModel: Codable, Equatable {
    /// Relative path to the model.
    public let path: Path

    /// Optional Current version (with or without extension)
    public let currentVersion: String?

    public enum CodingKeys: String, CodingKey {
        case path
        case currentVersion = "current_version"
    }

    /// Initializes the build file with its attributes.
    ///
    /// - Parameters:
    ///   - path: relative path to the Core Data model.
    ///   - currentVersion: optional current version name (with or without the extension)
    ///   By providing nil, it will try to read it from the .xccurrentversion file.
    public init(_ path: Path,
                currentVersion: String? = nil)
    {
        self.path = path
        self.currentVersion = currentVersion
    }
}
