import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol DependenciesContentHashing {
    func hash(
        graphTarget: GraphTarget,
        hashedTargets: [GraphHashedTarget: String],
        hashedPaths: [AbsolutePath: String]
    ) async throws -> DependenciesContentHash
}

public struct DependenciesContentHash {
    public let hashedPaths: [AbsolutePath: String]
    public let hash: String
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
        hashedTargets: [GraphHashedTarget: String],
        hashedPaths: [AbsolutePath: String]
    ) async throws -> DependenciesContentHash {
        let hashedTargets = hashedTargets
        var hashedPaths = hashedPaths
        var hashes: [String] = []

        for dependency in graphTarget.target.dependencies {
            let result = try await hash(
                graphTarget: graphTarget,
                dependency: dependency,
                hashedTargets: hashedTargets,
                hashedPaths: hashedPaths
            )
            hashes.append(result.hash)
            hashedPaths.merge(result.hashedPaths, uniquingKeysWith: { _, newValue in newValue })
        }
        return DependenciesContentHash(
            hashedPaths: hashedPaths,
            hash: try contentHasher.hash(hashes.sorted().compactMap { $0 }.joined())
        )
    }

    // MARK: - Private

    private func hash(
        graphTarget: GraphTarget,
        dependency: TargetDependency,
        hashedTargets: [GraphHashedTarget: String],
        hashedPaths: [AbsolutePath: String]
    ) async throws -> DependenciesContentHash {
        var hashedPaths = hashedPaths
        switch dependency {
        case let .target(targetName, _, _):
            guard let dependencyHash = hashedTargets[GraphHashedTarget(projectPath: graphTarget.path, targetName: targetName)]
            else {
                throw DependenciesContentHasherError.missingTargetHash(
                    sourceTargetName: graphTarget.target.name,
                    dependencyProjectPath: graphTarget.path,
                    dependencyTargetName: targetName
                )
            }
            return DependenciesContentHash(
                hashedPaths: hashedPaths,
                hash: dependencyHash
            )
        case let .project(targetName, projectPath, _, _):
            guard let dependencyHash = hashedTargets[GraphHashedTarget(projectPath: projectPath, targetName: targetName)] else {
                throw DependenciesContentHasherError.missingProjectTargetHash(
                    sourceProjectPath: graphTarget.path,
                    sourceTargetName: graphTarget.target.name,
                    dependencyProjectPath: projectPath,
                    dependencyTargetName: targetName
                )
            }
            return DependenciesContentHash(
                hashedPaths: hashedPaths,
                hash: dependencyHash
            )
        case let .framework(path, _, _), let .xcframework(path, _, _, _):
            if let pathHash = hashedPaths[path] {
                return DependenciesContentHash(
                    hashedPaths: hashedPaths,
                    hash: pathHash
                )
            } else {
                let pathHash = try await contentHasher.hash(path: path)
                hashedPaths[path] = pathHash
                return DependenciesContentHash(
                    hashedPaths: hashedPaths,
                    hash: pathHash
                )
            }
        case let .library(path, publicHeaders, swiftModuleMap, _):
            let libraryHash: String
            if let pathHash = hashedPaths[path] {
                libraryHash = pathHash
            } else {
                let pathHash = try await contentHasher.hash(path: path)
                hashedPaths[path] = pathHash
                libraryHash = pathHash
            }
            let publicHeadersHash = try await contentHasher.hash(path: publicHeaders)
            if let swiftModuleMap {
                let swiftModuleHash = try await contentHasher.hash(path: swiftModuleMap)
                return DependenciesContentHash(
                    hashedPaths: hashedPaths,
                    hash: try contentHasher.hash("library-\(libraryHash)-\(publicHeadersHash)-\(swiftModuleHash)")
                )
            } else {
                return DependenciesContentHash(
                    hashedPaths: hashedPaths,
                    hash: try contentHasher.hash("library-\(libraryHash)-\(publicHeadersHash)")
                )
            }
        case let .package(product, type, _):
            return DependenciesContentHash(
                hashedPaths: hashedPaths,
                hash: try contentHasher.hash("package-\(product)-\(type.rawValue)")
            )
        case let .sdk(name, status, _):
            return DependenciesContentHash(
                hashedPaths: hashedPaths,
                hash: try contentHasher.hash("sdk-\(name)-\(status)")
            )
        case .xctest:
            return DependenciesContentHash(
                hashedPaths: hashedPaths,
                hash: try contentHasher.hash("xctest")
            )
        }
    }
}
