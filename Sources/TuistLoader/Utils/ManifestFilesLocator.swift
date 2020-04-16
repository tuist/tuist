import Foundation
import TSCBasic
import TuistSupport

public protocol ManifestFilesLocating: AnyObject {
    /// It locates the manifest files that are have a connection with the
    /// definitions in the current directory.
    /// - Parameter at: Directory for which the manifest files will be obtained.
    func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)]
}

public final class ManifestFilesLocator: ManifestFilesLocating {
    public init() {}

    public func locate(at: AbsolutePath) -> [(Manifest, AbsolutePath)] {
        Manifest.allCases.compactMap { manifest in
            let path = at.appending(component: manifest.fileName)
            if FileHandler.shared.exists(path) { return (manifest, path) }
            return nil
        }
    }
}
