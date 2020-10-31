import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol ManifestFilesLocating: AnyObject {
    /// It locates the manifest files that are have a connection with the
    /// definitions in the current directory.
    /// - Parameter locatingPath: Directory for which the manifest files will be obtained.
    func locateProjectManifests(at locatingPath: AbsolutePath) -> [(Manifest, AbsolutePath)]

    /// It locates all manifest files under the root project folder
    /// - Parameter locatingPath: Directory for which the **project** manifest files will
    ///                 be obtained
    func locateAllProjectManifests(at locatingPath: AbsolutePath) -> [(Manifest, AbsolutePath)]

    /// It traverses up the directory hierarchy until it finds a `Config.swift` file.
    /// - Parameter locatingPath: Path from where to do the lookup.
    func locateConfig(at locatingPath: AbsolutePath) -> AbsolutePath?

    /// It traverses up the directory hierarchy until it finds a `Dependencies.swift` file.
    /// - Parameter locatingPath: Path from where to do the lookup.
    func locateDependencies(at locatingPath: AbsolutePath) -> AbsolutePath?

    /// It traverses up the directory hierarchy until it finds a `Setup.swift` file.
    /// - Parameter locatingPath: Path from where to do the lookup.
    func locateSetup(at locatingPath: AbsolutePath) -> AbsolutePath?
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

    public func locateAllProjectManifests(at locatingPath: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        guard let rootPath = rootDirectoryLocator.locate(from: locatingPath) else { return locateProjectManifests(at: locatingPath) }
        let projectsPaths = FileHandler.shared.glob(rootPath, glob: "**/\(Manifest.project.fileName(locatingPath))").map { (Manifest.project, $0) }
        let workspacesPaths = FileHandler.shared.glob(rootPath, glob: "**/\(Manifest.workspace.fileName(locatingPath))").map { (Manifest.workspace, $0) }
        return projectsPaths + workspacesPaths
    }

    public func locateConfig(at locatingPath: AbsolutePath) -> AbsolutePath? {
        let subPath = RelativePath("\(Constants.tuistDirectoryName)/\(Manifest.config.fileName(locatingPath))")
        return traverseAndLocate(at: locatingPath, appending: subPath)
    }

    public func locateDependencies(at locatingPath: AbsolutePath) -> AbsolutePath? {
        let subPath = RelativePath("\(Constants.tuistDirectoryName)/\(Manifest.dependencies.fileName(locatingPath))")
        return traverseAndLocate(at: locatingPath, appending: subPath)
    }

    public func locateSetup(at locatingPath: AbsolutePath) -> AbsolutePath? {
        let subPath = RelativePath(Manifest.setup.fileName(locatingPath))
        return traverseAndLocate(at: locatingPath, appending: subPath)
    }

    // MARK: - Helpers

    private func traverseAndLocate(at locatingPath: AbsolutePath, appending subpath: RelativePath) -> AbsolutePath? {
        let manifestPath = locatingPath.appending(subpath)

        if FileHandler.shared.exists(manifestPath) {
            return manifestPath
        } else if locatingPath != .root {
            return traverseAndLocate(at: locatingPath.parentDirectory, appending: subpath)
        } else {
            return nil
        }
    }
}
