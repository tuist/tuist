import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol ManifestFilesLocating: AnyObject {
    /// It locates the manifest files that are have a connection with the
    /// definitions in the current directory.
    /// - Parameter at: Directory for which the manifest files will be obtained.
    func locateProjectManifests(at: AbsolutePath) -> [(Manifest, AbsolutePath)]

    /// It locates all manifest files under the root project folder
    /// - Parameter at: Directory for which the **project** manifest files will
    ///                 be obtained
    func locateAllProjectManifests(at: AbsolutePath) -> [(Manifest, AbsolutePath)]

    /// It traverses up the directory hierarchy until it finds a `Config.swift` file.
    /// - Parameter at: Path from where to do the lookup.
    func locateConfig(at: AbsolutePath) -> AbsolutePath?
    
    /// It traverses up the directory hierarchy until it finds a `Dependencies.swift` file.
    /// - Parameter at: Path from where to do the lookup.
    func locateDependencies(at: AbsolutePath) -> AbsolutePath?

    /// It traverses up the directory hierarchy until it finds a `Setup.swift` file.
    /// - Parameter at: Path from where to do the lookup.
    func locateSetup(at: AbsolutePath) -> AbsolutePath?
}

public final class ManifestFilesLocator: ManifestFilesLocating {
    /// Utility to locate the root directory of the project
    let rootDirectoryLocator: RootDirectoryLocating

    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func locateProjectManifests(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        Manifest.allCases.compactMap { manifest in
            let path = at.appending(component: manifest.fileName(at))
            if FileHandler.shared.exists(path) { return (manifest, path) }
            return nil
        }
    }

    public func locateAllProjectManifests(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        guard let rootPath = rootDirectoryLocator.locate(from: at) else { return locateProjectManifests(at: at) }
        let projectsPaths = FileHandler.shared.glob(rootPath, glob: "**/\(Manifest.project.fileName(at))").map { (Manifest.project, $0) }
        let workspacesPaths = FileHandler.shared.glob(rootPath, glob: "**/\(Manifest.workspace.fileName(at))").map { (Manifest.workspace, $0) }
        return projectsPaths + workspacesPaths
    }

    public func locateConfig(at: AbsolutePath) -> AbsolutePath? {
        let subPath = RelativePath("\(Constants.tuistDirectoryName)/\(Manifest.config.fileName(at))")
        return traverseAndLocate(at: at, appending: subPath)
    }
    
    public func locateDependencies(at: AbsolutePath) -> AbsolutePath? {
        let subPath = RelativePath("\(Constants.tuistDirectoryName)/\(Manifest.dependencies.fileName(at))")
        return traverseAndLocate(at: at, appending: subPath)
    }

    public func locateSetup(at: AbsolutePath) -> AbsolutePath? {
        let subPath = RelativePath(Manifest.setup.fileName(at))
        return traverseAndLocate(at: at, appending: subPath)
    }

    // MARK: - Helpers

    private func traverseAndLocate(at: AbsolutePath, appending subpath: RelativePath) -> AbsolutePath? {
        let manifestPath = at.appending(subpath)

        if FileHandler.shared.exists(manifestPath) {
            return manifestPath
        } else if at != .root {
            return traverseAndLocate(at: at.parentDirectory, appending: subpath)
        } else {
            return nil
        }
    }
}
