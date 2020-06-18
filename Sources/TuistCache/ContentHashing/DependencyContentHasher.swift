import Foundation
import TuistCore

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

    // MARK: - HeadersContentHashing

    public func hash(dependencies: [Dependency]) throws -> String {
        // We don't need to hash the content of dependencies since they live in another target
        let hashes = dependencies.map { try? hash(dependency: $0) }
        return hashes.compactMap { $0 }.joined()
    }

    // MARK: - Private

    private func hash(dependency: Dependency) throws -> String {
        switch dependency {
        case let .target(name):
            return try contentHasher.hash("target-\(name)")
        case let .project(target, path):
            return try contentHasher.hash(["project-", target, path.pathString])
        case let .framework(path):
            return try contentHasher.hash("framework-\(path.pathString)")
        case let .xcFramework(path):
            return try contentHasher.hash("xcframework-\(path.pathString)")
        case let .library(path, publicHeaders, swiftModuleMap):
            return try contentHasher.hash(["library", path.pathString, publicHeaders.pathString, swiftModuleMap?.pathString].compactMap { $0 })
        case let .package(product):
            return try contentHasher.hash("package-\(product)")
        case let .sdk(name, status):
            return try contentHasher.hash("sdk-\(name)-\(status)")
        case let .cocoapods(path):
            return try contentHasher.hash(["cocoapods", path.pathString])
        }
    }
}
