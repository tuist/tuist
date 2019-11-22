import Basic
import Foundation
import TuistSupport

protocol ManifestFilesLocating: AnyObject {
    /// It locates the manifest files that are have a connection with the
    /// definitions in the current directory.
    /// - Parameter at: Directory for which the manifest files will be obtained.
    func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)]
}

final class ManifestFilesLocator: ManifestFilesLocating {
    func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        Manifest.allCases.compactMap { manifest in
            let path = at.appending(component: manifest.fileName)
            if FileHandler.shared.exists(path) { return (manifest, path) }
            return nil
        }
    }
}
