import Basic
import TuistCore

/// A component responsible for generating Xcode projects & workspaces
protocol Generating {

    /// Generate an Xcode project at a given path.
    ///
    /// - Parameters:
    ///   - path: The absolute path to the directory where an Xcode project should be generated.
    ///           (e.g. /path/to/directory)
    /// - Returns: An absolute path to the generated Xcode workspace
    ///            (e.g. /path/to/directory/project.xcodeproj)
    /// - Throws: Errors encountered during the generation process
    ///           many of which adopt `FatalError`
    /// - seealso: TuistCore.FatalError
    @discardableResult
    func generateProject(at path: AbsolutePath) throws -> AbsolutePath

    /// Generate an Xcode workspace at a given path.
    ///
    /// - Parameters:
    ///   - path: The absolute path to the directory where an Xcode project should be generated.
    ///           (e.g. /path/to/directory)
    /// - Returns: An absolute path to the generated Xcode workspace
    ///            (e.g. /path/to/directory/project.xcodeproj)
    /// - Throws: Errors encountered during the generation process
    ///           many of which adopt `FatalError`
    /// - seealso: TuistCore.FatalError
    @discardableResult
    func generateWorkspace(at path: AbsolutePath) throws -> AbsolutePath
}

enum GeneratorError: FatalError {
    
    case notImplemented
    
    public var type: ErrorType {
        switch self {
        case .notImplemented:
            return .abort
        }
    }
    
    public var description: String {
        switch self {
        case .notImplemented:
            return "This feature is not yet implemented"
        }
    }
}

/// A default implementation of `Generating`
///
/// - seealso: Generating
class Generator: Generating {
    func generateProject(at path: AbsolutePath) throws -> AbsolutePath {
        throw GeneratorError.notImplemented
    }

    func generateWorkspace(at path: AbsolutePath) throws -> AbsolutePath {
        throw GeneratorError.notImplemented
    }
}
