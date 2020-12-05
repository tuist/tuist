import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Saving `.*.version` files installed using `carthage`.
/// https://github.com/Carthage/Carthage/blob/master/Documentation/VersionFile.md
public protocol CarthageVersionFilesInteracting {
    /// Saves `.*.version` files installed using `carthage`.
    /// - Parameters:
    ///   - carthageBuildDirectory: The path to the directory that contains the `Carthage/Build/` directory.
    ///   - dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func copyVersionFiles(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws
}

public final class CarthageVersionFilesInteractor: CarthageVersionFilesInteracting {
    private let fileHandler: FileHandling

    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }
    
    public func copyVersionFiles(carthageBuildDirectory: AbsolutePath, dependenciesDirectory: AbsolutePath) throws {
        let derivedDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.derivedDirectoryName)
            .appending(component: "Carthage")
        
        if fileHandler.exists(carthageBuildDirectory) {
            try fileHandler
                .contentsOfDirectory(carthageBuildDirectory)
                .filter { $0.extension == "version" }
                .forEach {
                    try copyFile(from: $0, to: derivedDirectory.appending(component: $0.basename))
                }
        }
    }
    
    // MARK: - Helpers

    private func copyFile(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.replace(toPath, with: fromPath)
        } else {
            try fileHandler.copy(from: fromPath, to: toPath)
        }
    }
}
