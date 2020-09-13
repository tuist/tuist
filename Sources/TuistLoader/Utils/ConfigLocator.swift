import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol ConfigLocating {
    ///  It traverses up the directory hierarchy until it finds a `Config.swift` file inside `tuist` dictionary
    /// - Parameter path: Path from where to do the lookup.
    func locate(at path: AbsolutePath) -> AbsolutePath?
}

public final class ConfigLocator: ConfigLocating {
    let rootDirectoryLocator: RootDirectoryLocating

    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func locate(at path: AbsolutePath) -> AbsolutePath? {
        let manfiestPath = path.appending(components: Constants.tuistDirectoryName, Manifest.config.fileName(path))

        if FileHandler.shared.exists(manfiestPath) {
            return manfiestPath
        } else if path != .root {
            return locate(at: path.parentDirectory)
        } else {
            return nil
        }
    }
}
