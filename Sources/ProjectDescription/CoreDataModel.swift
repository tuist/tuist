import Foundation

/// A Core Data model.
public struct CoreDataModel: Codable, Equatable {
    /// Relative path to the model.
    public let path: Path

    /// Optional Current version (with or without extension)
    public let currentVersion: String?

    /// Creates a Core Data model from a path.
    ///
    /// - Parameters:
    ///   - path: relative path to the Core Data model.
    ///   - currentVersion: optional current version name (with or without the extension)
    ///   By providing nil, it will try to read it from the .xccurrentversion file.
    public init(
        _ path: Path,
        currentVersion: String? = nil
    ) {
        self.path = path
        self.currentVersion = currentVersion
    }
}
