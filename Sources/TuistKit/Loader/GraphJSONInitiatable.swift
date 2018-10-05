import Basic
import Foundation
import TuistCore

/// Protocol conformed by the models that are part of the manifest.
/// The protocol defines a constructor that takes the JSON representation
/// of the entity, the path to manifest' folder that should be used to generate
/// absolute paths from the relative paths, and the file handler that can be used
/// to check whether file exists in the system.
protocol GraphJSONInitiatable {
    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - json: JSON representation of the entity. This JSON is the output of the same entity in the ProjectDescription framework.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: An error if the
    init(json: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws
}
