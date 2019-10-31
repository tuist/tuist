import Basic
import Foundation
import ProjectDescription

/// This model includes paths the manifest path can be relative to.
struct GeneratorPaths {
    /// Path to the directory that contains the manifest being loaded.
    private let manifestDirectory: AbsolutePath

    /// Creates an instance with its attributes.
    /// - Parameter manifestDirectory: Path to the directory that contains the manifest being loaded.
    init(manifestDirectory: AbsolutePath) {
        self.manifestDirectory = manifestDirectory
    }

    /// Given a project description path, it returns the absolute path of the given path.
    /// - Parameter path: Absolute path.
    func resolve(path: Path) -> AbsolutePath {
        switch path.type {
        case .relativeToCurrentFile:
            let callerAbsolutePath = AbsolutePath(path.callerPath!).removingLastComponent()
            return AbsolutePath(path.pathString, relativeTo: callerAbsolutePath)
        case .relativeToManifest:
            return AbsolutePath(path.pathString, relativeTo: manifestDirectory)
        }
    }
}
