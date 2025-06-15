import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport

/// This model includes paths the manifest path can be relative to.
public struct GeneratorPaths {
    /// Path to the directory that contains the manifest being loaded.
    let manifestDirectory: AbsolutePath
    private let rootDirectory: AbsolutePath

    /// Creates an instance with its attributes.
    /// - Parameter manifestDirectory: Path to the directory that contains the manifest being loaded.
    public init(
        manifestDirectory: AbsolutePath,
        rootDirectory: AbsolutePath
    ) {
        self.manifestDirectory = manifestDirectory
        self.rootDirectory = rootDirectory
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
            return try AbsolutePath(validating: path.pathString, relativeTo: rootDirectory)
        }
    }

    /// This method is intended to be used to get path of projects referenced from scheme.
    /// When the user doesn't specify the project, we assume they are referencing a target in the project where the scheme is
    /// being defined.
    /// - Parameters:
    ///   - projectPath: Path to the project that contains the target referenced by the scheme action.
    func resolveSchemeActionProjectPath(_ projectPath: Path?) throws -> AbsolutePath {
        if let projectPath {
            return try resolve(path: projectPath)
        }
        return manifestDirectory
    }
}
