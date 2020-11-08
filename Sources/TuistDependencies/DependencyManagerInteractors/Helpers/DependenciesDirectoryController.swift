import Foundation
import TSCBasic
import TuistSupport

public protocol DependenciesDirectoryControlling {
    func saveCartfileResolvedFile(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws
    func saveCarthageFrameworks(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath, names: [String]) throws
    
    func loadCartfileResolvedFile(from path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws
}

#warning("TODO: add unit tests")
public final class DependenciesDirectoryController: DependenciesDirectoryControlling {
    private let fileHandler: FileHandling!
    
    public init(fileHandler: FileHandling = FileHandler.shared) {
        self.fileHandler = fileHandler
    }
    
    public func saveCartfileResolvedFile(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        let fromPath = temporaryDirectoryPath.appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        let toPath = buildCartfileResolvedPath(at: path)
        try copyFile(from: fromPath, to: toPath)
    }
    
    public func saveCarthageFrameworks(at path: AbsolutePath, temporaryDirectoryPath: AbsolutePath, names: [String]) throws {
        let decoder = JSONDecoder()
        
        try names.forEach { name in
            let versionFilePath = temporaryDirectoryPath.appending(components: "Carthage", "Build", ".\(name).version")
            let versionFileData = try fileHandler.readFile(versionFilePath)
            let versionFile = try decoder.decode(CarthageVersion.self, from: versionFileData)
            
            if let iOS = versionFile.iOS {
                try iOS
                    .map {$0.name}
                    .forEach { name in
                        let fromPath = temporaryDirectoryPath.appending(components: "Carthage", "Build", "iOS", "\(name).framework")
                        let toPath = buildFrameworkPath(at: path, name: name, platform: .iOS)
                        try copyDirectory(from: fromPath, to: toPath)
                    }
            }
            
            if let macOS = versionFile.macOS {
                try macOS
                    .map {$0.name}
                    .forEach { name in
                        let fromPath = temporaryDirectoryPath.appending(components: "Carthage", "Build", "Mac", "\(name).framework")
                        let toPath = buildFrameworkPath(at: path, name: name, platform: .macOS)
                        try copyDirectory(from: fromPath, to: toPath)
                    }
            }
            
            if let tvOS = versionFile.tvOS {
                try tvOS
                    .map {$0.name}
                    .forEach { name in
                        let fromPath = temporaryDirectoryPath.appending(components: "Carthage", "Build", "tvOS", "\(name).framework")
                        let toPath = buildFrameworkPath(at: path, name: name, platform: .tvOS)
                        try copyDirectory(from: fromPath, to: toPath)
                    }
            }
            
            if let watchOS = versionFile.watchOS {
                try watchOS
                    .map {$0.name}
                    .forEach { name in
                        let fromPath = temporaryDirectoryPath.appending(components: "Carthage", "Build", "watchOS", "\(name).framework")
                        let toPath = buildFrameworkPath(at: path, name: name, platform: .watchOS)
                        try copyDirectory(from: fromPath, to: toPath)
                    }
            }
        }
    }
    
    public func loadCartfileResolvedFile(from path: AbsolutePath, temporaryDirectoryPath: AbsolutePath) throws {
        let fromPath = buildCartfileResolvedPath(at: path)
        if fileHandler.exists(fromPath) {
            let toPath = temporaryDirectoryPath.appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
            try fileHandler.copy(from: fromPath, to: toPath)
        }
    }
    
    // MARK: - Paths builders
    
    private func buildDependenciesDirectoryPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(components:  Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)
    }
    
    private func buildCartfileResolvedPath(at path: AbsolutePath) -> AbsolutePath {
        buildDependenciesDirectoryPath(at: path)
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
    }
    
    private func buildFrameworkPath(at path: AbsolutePath, name: String, platform: Platform) -> AbsolutePath {
        buildDependenciesDirectoryPath(at: path)
            .appending(component: name)
            .appending(component: platform.rawValue)
            .appending(component: "\(name).framework")
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
    
    private func copyDirectory(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())
        
        if fileHandler.exists(toPath) {
            try fileHandler.delete(toPath)
        }
        
        try fileHandler.copy(from: fromPath, to: toPath)
    }
}

// MARK: - Models

extension DependenciesDirectoryController {
    struct CarthageVersion: Decodable {
        enum CodingKeys: String, CodingKey {
            case commitish
            case iOS
            case macOS = "Mac"
            case tvOS
            case watchOS
        }
        
        let commitish: String
        let iOS: [CarthageVersionDependency]?
        let macOS: [CarthageVersionDependency]?
        let tvOS: [CarthageVersionDependency]?
        let watchOS: [CarthageVersionDependency]?
    }
    
    struct CarthageVersionDependency: Decodable {
        let hash: String
        let name: String
        let linking: String
        let swiftToolchainVersion: String
    }
    
    enum Platform: String {
        case iOS
        case macOS
        case watchOS
        case tvOS
    }
}
