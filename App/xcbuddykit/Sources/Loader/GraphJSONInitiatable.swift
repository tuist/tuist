import Basic
import Foundation

/// The objects that conform this protocol are nodes that can be initialized
/// with its JSON representation, the project path, and the graph loader context.
protocol GraphJSONInitiatable {
    /// Default constructor.
    ///
    /// - Parameters:
    ///   - json: json representation of the object that is going to be initialized.
    ///   - projectPath: path to the folder where the project's definition that contains this object is.
    ///   - context: graph loader context.
    /// - Throws: an error when the object cannot be initialized
    init(json: JSON,
         projectPath: AbsolutePath,
         context: GraphLoaderContexting) throws
}
