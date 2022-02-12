import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol DependenciesContentHashing {
    func hash(
        graphTarget: GraphTarget,
        hashedTargets: inout [GraphHashedTarget: String],
        hashedPaths: inout [AbsolutePath: String]
    ) throws -> String
}

enum DependenciesContentHasherError: FatalError, Equatable {
    case missingTargetHash(
        sourceTargetName: String,
        dependencyProjectPath: AbsolutePath,
        dependencyTargetName: String
    )
    case missingProjectTargetHash(
        sourceProjectPath: AbsolutePath,
        sourceTargetName: String,
        dependencyProjectPath: AbsolutePath,
        dependencyTargetName: String
    )

    var description: String {
        switch self {
        case let .missingTargetHash(sourceTargetName, dependencyProjectPath, dependencyTargetName):
            return "The target '\(sourceTargetName)' depends on the target '\(dependencyTargetName)' from the same project at path \(dependencyProjectPath.pathString) whose hash hasn't been previously calculated."
        case let .missingProjectTargetHash(sourceProjectPath, sourceTargetName, dependencyProjectPath, dependencyTargetName):
            return "The target '\(sourceTargetName)' from project at path \(sourceProjectPath.pathString) depends on the target '\(dependencyTargetName)' from the project at path \(dependencyProjectPath.pathString) whose hash hasn't been previously calculated."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingTargetHash: return .bug
        case .missingProjectTargetHash: return .bug
        }
    }
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

    public func hash(
        graphTarget: GraphTarget,
        hashedTargets: inout [GraphHashedTarget: String],
        hashedPaths: inout [AbsolutePath: String]
    ) throws -> String {
        let hashes = try graphTarget.target.dependencies
            .map { try hash(graphTarget: graphTarget, dependency: $0, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths) }
        return hashes.compactMap { $0 }.joined()
    }

    // MARK: - Private

    private func hash(
        graphTarget: GraphTarget,
        dependency: TargetDependency,
        hashedTargets: inout [GraphHashedTarget: String],
        hashedPaths: inout [AbsolutePath: String]
    ) throws -> String {
        switch dependency {
        case let .target(targetName):
            guard let dependencyHash = hashedTargets[GraphHashedTarget(projectPath: graphTarget.path, targetName: targetName)]
            else {
                throw DependenciesContentHasherError.missingTargetHash(
                    sourceTargetName: graphTarget.target.name,
                    dependencyProjectPath: graphTarget.path,
                    dependencyTargetName: targetName
                )
            }
            return dependencyHash
        case let .project(targetName, projectPath):
            guard let dependencyHash = hashedTargets[GraphHashedTarget(projectPath: projectPath, targetName: targetName)] else {
                throw DependenciesContentHasherError.missingProjectTargetHash(
                    sourceProjectPath: graphTarget.path,
                    sourceTargetName: graphTarget.target.name,
                    dependencyProjectPath: projectPath,
                    dependencyTargetName: targetName
                )
            }
            return dependencyHash
        case let .framework(path), let .xcframework(path):
            return try cachedHash(path: path, hashedPaths: &hashedPaths)
        case let .library(path, publicHeaders, swiftModuleMap):
            let libraryHash = try cachedHash(path: path, hashedPaths: &hashedPaths)
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
        case .xctest:
            return try contentHasher.hash("xctest")
        }
    }

    private func cachedHash(path: AbsolutePath, hashedPaths: inout [AbsolutePath: String]) throws -> String {
        if let pathHash = hashedPaths[path] {
            return pathHash
        } else {
            let pathHash = try contentHasher.hash(path: path)
            hashedPaths[path] = pathHash
            return pathHash
        }
    }
}
