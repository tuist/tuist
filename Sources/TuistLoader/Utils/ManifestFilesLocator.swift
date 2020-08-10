import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol ManifestFilesLocating: AnyObject {
    /// It locates the manifest files that are have a connection with the
    /// definitions in the current directory.
    /// - Parameter at: Directory for which the manifest files will be obtained.
    func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)]

    /// It locates all manifest files under the root project folder
    /// - Parameter at: Directory for which the **project** manifest files will
    ///                 be obtained
    func locateAll(at: AbsolutePath) -> [(Manifest, AbsolutePath)]
}

public final class ManifestFilesLocator: ManifestFilesLocating {
    /// Utility to locate the root directory of the project
    let rootDirectoryLocator: RootDirectoryLocating

    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        Manifest.allCases.compactMap { manifest in
            let path = at.appending(component: manifest.fileName(at))
            if FileHandler.shared.exists(path) { return (manifest, path) }
            return nil
        }
    }

    public func locateAll(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        guard let rootPath = rootDirectoryLocator.locate(from: at) else { return locate(at: at) }
        let projectsPaths = FileHandler.shared.glob(rootPath, glob: "**/\(Manifest.project.fileName(at))").map { (Manifest.project, $0) }
        let workspacesPaths = FileHandler.shared.glob(rootPath, glob: "**/\(Manifest.workspace.fileName(at))").map { (Manifest.workspace, $0) }
        return projectsPaths + workspacesPaths
    }
}
