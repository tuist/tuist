import Foundation
import TSCBasic
import TuistSupport

/// Protocol conformed by the models that are part of the manifest.
/// The protocol defines a constructor that takes the JSON representation
/// of the entity, the path to manifest' folder that should be used to generate
/// absolute paths from the relative paths, and the file handler that can be used
/// to check whether file exists in the system.
protocol GraphInitiatable {
    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    init(dictionary: JSON, projectPath: AbsolutePath) throws
}
