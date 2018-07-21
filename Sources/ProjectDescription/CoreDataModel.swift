import Foundation

/// Core Data model.
public class CoreDataModel: JSONConvertible {
    /// Relative path to the model.
    let path: String

    /// Current version (with or without extension)
    let currentVersion: String

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

    /// Returns a JSON representation of the object.
    ///
    /// - Returns: JSON representation.
    func toJSON() -> JSON {
        return JSON.dictionary([
            "path": self.path.toJSON(),
            "current_version": self.currentVersion.toJSON(),
        ])
    }
}
