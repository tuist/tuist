import Foundation
import TuistCore
import TuistGraph

public protocol DependenciesContentHashing {
    func hash(dependencies: [Dependency]) throws -> String
}

/// `DependencyContentHasher`
/// is responsible for computing a hash that uniquely identifies a target dependency
public final class DependenciesContentHasher: DependenciesContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - DependenciesContentHashing

    public func hash(dependencies: [Dependency]) throws -> String {
        let hashes = dependencies.map { try? hash(dependency: $0) }
        return hashes.compactMap { $0 }.joined()
    }

    // MARK: - Private

    private func hash(dependency: Dependency) throws -> String {
        switch dependency {
        case let .target(name):
            return try contentHasher.hash("target-\(name)")
        case let .project(target, path):
            let projectHash = try contentHasher.hash(path: path)
            return try contentHasher.hash("project-\(projectHash)-\(target)")
        case let .framework(path):
            return try contentHasher.hash(path: path)
        case let .xcFramework(path):
            return try contentHasher.hash(path: path)
        case let .library(path, publicHeaders, swiftModuleMap):
            let libraryHash = try contentHasher.hash(path: path)
            let publicHeadersHash = try contentHasher.hash(path: publicHeaders)
            if let swiftModuleMap = swiftModuleMap {
                let swiftModuleHash = try contentHasher.hash(path: swiftModuleMap)
                return try contentHasher.hash("library-\(libraryHash)-\(publicHeadersHash)-\(swiftModuleHash)")
            } else {
                return try contentHasher.hash("library-\(libraryHash)-\(publicHeadersHash)")
            }
        case let .package(product):
            return try contentHasher.hash("package-\(product)")
        case let .sdk(name, status):
            return try contentHasher.hash("sdk-\(name)-\(status)")
        case let .cocoapods(path):
            let podsHash = try contentHasher.hash(path: path)
            return try contentHasher.hash("cocoapods-\(podsHash)")
        case .xctest:
            return try contentHasher.hash("xctest")
        }
    }
}
