import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol SetupLocating {
    /// It traverses up the directory hierarchy until it finds a Setup.swift file.
    /// - Parameter path: Path from where to do the lookup.
    func locate(at path: AbsolutePath) -> AbsolutePath?
}

public final class SetupLocator: SetupLocating {
    let rootDirectoryLocator: RootDirectoryLocating
    
    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }
    
    public func locate(at path: AbsolutePath) -> AbsolutePath? {
        let manfiestPath = path.appending(component: Manifest.setup.fileName(path))
        
        if FileHandler.shared.exists(manfiestPath) {
            return manfiestPath
        } else if path != .root {
            return locate(at: path.parentDirectory)
        } else {
            return nil
        }
    }
}
