import Foundation
import TuistCore
import TuistGraph
import TSCBasic

public protocol DependenciesContentHashing {
    func hash(dependencies: [Dependency], sourceRootPath: AbsolutePath) throws -> String
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

    public func hash(dependencies: [Dependency], sourceRootPath: AbsolutePath) throws -> String {
        let hashes = dependencies.map { try? hash(dependency: $0, sourceRootPath: sourceRootPath) }
        return hashes.compactMap { $0 }.joined()
    }

    // MARK: - Private

    private func hash(dependency: Dependency, sourceRootPath rootPath: AbsolutePath) throws -> String {
        func relativeToRoot(_ path: AbsolutePath) -> String {
            path.relative(to: rootPath).pathString
        }

        switch dependency {
        case let .target(name):
            return try contentHasher.hash("target-\(name)")
        case let .project(target, path):
            return try contentHasher.hash(["project-", target, relativeToRoot(path)])
        case let .framework(path):
            return try contentHasher.hash("framework-\(relativeToRoot(path))")
        case let .xcFramework(path):
            return try contentHasher.hash("xcframework-\(relativeToRoot(path))")
        case let .library(path, publicHeaders, swiftModuleMap):
            return try contentHasher.hash(["library", relativeToRoot(path), relativeToRoot(publicHeaders), swiftModuleMap.map(relativeToRoot)].compactMap { $0 })
        case let .package(product):
            return try contentHasher.hash("package-\(product)")
        case let .sdk(name, status):
            return try contentHasher.hash("sdk-\(name)-\(status)")
        case let .cocoapods(path):
            return try contentHasher.hash(["cocoapods", relativeToRoot(path)])
        case .xctest:
            return try contentHasher.hash("xctest")
        }
    }
}
