import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Saving and loading `Cartfile.resolved` file.
public protocol CartfileResolvedInteracting {
    /// Saves `Cartfile.resolved`.
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - temporaryDirectoryPath: Folder where dependencies are being installed.
    func save(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws
    
    /// Loads `Cartfile.resolved` if exist.
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be installed.
    ///   - temporaryDirectoryPath: Folder where dependencies are being installed.
    func loadIfExist(from path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws
}

public final class CartfileResolvedInteractor: CartfileResolvedInteracting {
    private let fileHandler: FileHandling
    
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }
    
    public func save(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        let fromPath = cartfileResolvedTemoraryPath(at: temporaryDirectoryPath)
        let toPath = cartfileResolvedSavingPath(at: path)
        try copyFile(from: fromPath, to: toPath)
    }
    
    public func loadIfExist(from path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        let fromPath = cartfileResolvedSavingPath(at: path)
        
        if fileHandler.exists(fromPath) {
            let toPath = cartfileResolvedTemoraryPath(at: temporaryDirectoryPath)
            try copyFile(from: fromPath, to: toPath)
        }
    }
    
    // MARK: - Helpers
    
    private func cartfileResolvedSavingPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
    }
    
    private func cartfileResolvedTemoraryPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
    }
    
    private func copyFile(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())
        
        if fileHandler.exists(toPath) {
            try fileHandler.replace(toPath, with: fromPath)
        } else {
            try fileHandler.copy(from: fromPath, to: toPath)
        }
    }
}
