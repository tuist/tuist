import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

enum GeneratorPathsError: FatalError, Equatable {
    /// Thrown when the root directory can't be located.
    case rootDirectoryNotFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .rootDirectoryNotFound: return .abort
        }
    }

    var description: String {
        switch self {
        case let .rootDirectoryNotFound(path):
            return "Couldn't locate the root directory from path \(path.pathString). The root directory is the closest directory that contains a Tuist or a .git directory."
        }
    }
}

/// This model includes paths the manifest path can be relative to.
public struct GeneratorPaths {
    /// Path to the directory that contains the manifest being loaded.
    let manifestDirectory: AbsolutePath
    private let rootDirectoryLocator: RootDirectoryLocating

    /// Creates an instance with its attributes.
    /// - Parameter manifestDirectory: Path to the directory that contains the manifest being loaded.
    public init(
        manifestDirectory: AbsolutePath,
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.manifestDirectory = manifestDirectory
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    /// Given a project description path, it returns the absolute path of the given path.
    /// - Parameter path: Absolute path.
    func resolve(path: Path) throws -> AbsolutePath {
        switch path.type {
        case .relativeToCurrentFile:
            let callerAbsolutePath = try AbsolutePath(validating: path.callerPath!).removingLastComponent()
            return try AbsolutePath(validating: path.pathString, relativeTo: callerAbsolutePath)
        case .relativeToManifest:
            return try AbsolutePath(validating: path.pathString, relativeTo: manifestDirectory)
        case .relativeToRoot:
            guard let rootPath = rootDirectoryLocator.locate(from: try AbsolutePath(validating: manifestDirectory.pathString))
            else {
                throw GeneratorPathsError.rootDirectoryNotFound(try AbsolutePath(validating: manifestDirectory.pathString))
            }
            return try AbsolutePath(validating: path.pathString, relativeTo: rootPath)
        }
    }

    /// This method is intended to be used to get path of projects referenced from scheme.
    /// When the user doesn't specify the project, we assume they are referencing a target in the project where the scheme is being defined.
    /// - Parameters:
    ///   - projectPath: Path to the project that contains the target referenced by the scheme action.
    func resolveSchemeActionProjectPath(_ projectPath: Path?) throws -> AbsolutePath {
        if let projectPath = projectPath {
            return try resolve(path: projectPath)
        }
        return manifestDirectory
    }
}
