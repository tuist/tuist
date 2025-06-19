/// A Core Data model.
public struct CoreDataModel: Codable, Equatable, Sendable {
    /// Relative path to the model.
    public var path: Path

    /// Optional Current version (with or without extension)
    public var currentVersion: String?

    /// Creates a Core Data model from a path.
    ///
    /// - Parameters:
    ///   - path: relative path to the Core Data model.
    ///   - currentVersion: optional current version name (with or without the extension)
    ///   By providing nil, it will try to read it from the .xccurrentversion file.
    public static func coreDataModel(
        _ path: Path,
        currentVersion: String? = nil
    ) -> Self {
        self.init(
            path: path,
            currentVersion: currentVersion
        )
    }
}
