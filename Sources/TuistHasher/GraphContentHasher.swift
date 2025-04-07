import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol GraphContentHashing {
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - filter: If `true`, `TargetNode` is hashed, otherwise it is skipped
    ///     - additionalStrings: Additional strings to be used when hashing graph
    func contentHashes(
        for graph: Graph,
        include: @escaping (GraphTarget) -> Bool,
        destination: SimulatorDeviceAndRuntime?,
        additionalStrings: [String]
    ) async throws -> [GraphTarget: String]
}

/// `GraphContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
public struct GraphContentHasher: GraphContentHashing {
    private let contentHasher: ContentHashing
    private let targetContentHasher: TargetContentHashing
    private let fileSystem: FileSysteming
    private let rootDirectoryLocator: RootDirectoryLocating

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        let targetContentHasher = TargetContentHasher(contentHasher: contentHasher)
        self.init(
            contentHasher: contentHasher,
            targetContentHasher: targetContentHasher
        )
    }

    public init(
        contentHasher: ContentHashing,
        targetContentHasher: TargetContentHashing,
        fileSystem: FileSysteming = FileSystem(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.contentHasher = contentHasher
        self.targetContentHasher = targetContentHasher
        self.fileSystem = fileSystem
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    // MARK: - GraphContentHashing

    public func contentHashes(
        for graph: Graph,
        include: (GraphTarget) -> Bool,
        destination: SimulatorDeviceAndRuntime?,
        additionalStrings: [String]
    ) async throws -> [GraphTarget: String] {
        let graphTraverser = GraphTraverser(graph: graph)
        var visitedIsHasheableNodes: [GraphTarget: Bool] = [:]
        let hashedTargets: ThreadSafe<[GraphHashedTarget: String]> = ThreadSafe([:])
        let hashedPaths: ThreadSafe<[AbsolutePath: String]> = ThreadSafe([:])

        var additionalStrings = additionalStrings

        if let lockFileHash = try await lockFileHash(for: graph) {
            additionalStrings.append(lockFileHash)
        }

        let sortedCacheableTargets = try graphTraverser.allTargetsTopologicalSorted()
        let hashableTargets = sortedCacheableTargets.compactMap { target -> GraphTarget? in
            if isHashable(
                target,
                graphTraverser: graphTraverser,
                visited: &visitedIsHasheableNodes,
                include: include
            ) {
                return target
            } else {
                return nil
            }
        }

        let hashes = try await hashableTargets.serialMap { (target: GraphTarget) async throws -> String in
            let hash = try await targetContentHasher.contentHash(
                for: target,
                hashedTargets: hashedTargets.value,
                hashedPaths: hashedPaths.value,
                destination: destination,
                additionalStrings: additionalStrings
            )
            hashedPaths.mutate { $0 = hash.hashedPaths }
            hashedTargets.mutate {
                $0[
                    GraphHashedTarget(
                        projectPath: target.path,
                        targetName: target.target.name
                    )
                ] = hash.hash
            }
            return hash.hash
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Private

    private func isHashable(
        _ target: GraphTarget,
        graphTraverser: GraphTraversing,
        visited: inout [GraphTarget: Bool],
        include: (GraphTarget) -> Bool
    ) -> Bool {
        guard include(target) else {
            visited[target] = false
            return false
        }
        if let visitedValue = visited[target] { return visitedValue }
        let allTargetDependenciesAreHashable = graphTraverser.directTargetDependencies(
            path: target.path,
            name: target.target.name
        )
        .allSatisfy {
            isHashable(
                $0.graphTarget,
                graphTraverser: graphTraverser,
                visited: &visited,
                include: include
            )
        }
        visited[target] = allTargetDependenciesAreHashable
        return allTargetDependenciesAreHashable
    }

    private func lockFileHash(
        for graph: Graph
    ) async throws -> String? {
        if let lockFilePath = try await rootDirectoryLocator.locate(from: graph.path)
            .map({ $0.appending(component: ".package.resolved") }),
            try await fileSystem.exists(lockFilePath)
        {
            return try await contentHasher.hash(
                path: lockFilePath
            )
        }
        if let workspacePath = try await fileSystem.glob(directory: graph.path, include: ["*.xcworkspace"]).collect().first {
            let lockFilePath = workspacePath.appending(components: "xcshareddata", "swiftpm", "Package.resolved")
            if try await fileSystem.exists(lockFilePath) {
                return try await contentHasher.hash(path: lockFilePath)
            }
        } else if let projectPath = try await fileSystem.glob(directory: graph.path, include: ["*.xcodeproj"]).collect().first {
            let lockFilePath = projectPath.appending(
                components: [
                    "project.xcworkspace",
                    "xcshareddata",
                    "swiftpm",
                    "Package.resolved",
                ]
            )
            if try await fileSystem.exists(lockFilePath) {
                return try await contentHasher.hash(path: lockFilePath)
            }
        }
        return nil
    }
}
