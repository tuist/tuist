import Foundation

/// Core Data model.
public class CoreDataModel: Codable {
    /// Relative path to the model.
    let path: String

    /// Current version (with or without extension)
    let currentVersion: String

    public enum CodingKeys: String, CodingKey {
        case path
        case currentVersion = "current_version"
    }

    /// Initializes the build file with its attributes.
    ///
    /// - Parameters:
    ///   - path: relative path to the Core Data model.
    ///   - currentVersion: current version name (with or without the extension).
    public init(_ path: String,
                currentVersion: String) {
        self.path = path
        self.currentVersion = currentVersion
    }
}
