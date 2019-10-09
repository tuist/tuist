import Foundation
import Basic
import TuistCore

protocol TuistDirectoryLocating {
    
    /// Traverses the directories hierarchy up until it finds the Tuist directory alongside the TuistConfig.swift file.
    /// - Parameter path: Path to locate the Tuist directory from.
    func locate(from path: AbsolutePath) -> AbsolutePath?
}

final class TuistDirectoryLocator: TuistDirectoryLocating {
    func locate(from path: AbsolutePath) -> AbsolutePath? {
        guard let tuistConfigPath = FileHandler.shared.locateDirectoryTraversingParents(from: path, path: Manifest.tuistConfig.fileName) else {
            return nil
        }
        let rootPath = tuistConfigPath.parentDirectory
        let helpersDirectory = rootPath.appending(RelativePath(Constants.tuistFolderName))
        
        if FileHandler.shared.exists(helpersDirectory) {
            return helpersDirectory
        }
        return nil
    }
}
