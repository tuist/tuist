import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistRootDirectoryLocator
import TuistSupport
import TuistThreadSafe
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
    ) async throws -> [GraphTarget: TargetContentHash]
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
    ) async throws -> [GraphTarget: TargetContentHash] {
        let graphTraverser = GraphTraverser(graph: graph)
        var visitedIsHasheableNodes: [GraphTarget: Bool] = [:]
        let hashedTargets: ThreadSafe<[GraphHashedTarget: String]> = ThreadSafe([:])
        let hashedPaths: ThreadSafe<[AbsolutePath: String]> = ThreadSafe([:])

        let additionalStrings = additionalStrings

        let sortedCacheableTargets = try graphTraverser.allTargetsTopologicalSorted()
        let hashableTargets = sortedCacheableTargets.filter { target in
            isHashable(
                target,
                graphTraverser: graphTraverser,
                visited: &visitedIsHasheableNodes,
                include: include
            )
        }

        let hashes = try await concurrentContentHashes(
            hashableTargets: hashableTargets,
            graphTraverser: graphTraverser,
            hashedTargets: hashedTargets,
            hashedPaths: hashedPaths,
            destination: destination,
            additionalStrings: additionalStrings
        )
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    private func concurrentContentHashes(
        hashableTargets: [GraphTarget],
        graphTraverser: GraphTraversing,
        hashedTargets: ThreadSafe<[GraphHashedTarget: String]>,
        hashedPaths: ThreadSafe<[AbsolutePath: String]>,
        destination: SimulatorDeviceAndRuntime?,
        additionalStrings: [String]
    ) async throws -> [TargetContentHash] {
        let targetContentHasher = targetContentHasher
        let tasks = ThreadSafe<[GraphHashedTarget: Task<TargetContentHash, Error>]>([:])
        for target in hashableTargets {
            let key = GraphHashedTarget(projectPath: target.path, targetName: target.target.name)
            let directDepKeys = graphTraverser
                .directTargetDependencies(path: target.path, name: target.target.name)
                .map { GraphHashedTarget(projectPath: $0.graphTarget.path, targetName: $0.graphTarget.target.name) }
            let task = Task { () async throws -> TargetContentHash in
                for depKey in directDepKeys {
                    if let depTask = tasks.value[depKey] {
                        _ = try await depTask.value
                    }
                }
                let hash = try await targetContentHasher.contentHash(
                    for: target,
                    hashedTargets: hashedTargets.value,
                    hashedPaths: hashedPaths.value,
                    destination: destination,
                    additionalStrings: additionalStrings
                )
                hashedPaths.mutate { $0.merge(hash.hashedPaths, uniquingKeysWith: { _, new in new }) }
                hashedTargets.mutate { $0[key] = hash.hash }
                return hash
            }
            tasks.mutate { $0[key] = task }
        }
        var results: [TargetContentHash] = []
        results.reserveCapacity(hashableTargets.count)
        do {
            for target in hashableTargets {
                let key = GraphHashedTarget(projectPath: target.path, targetName: target.target.name)
                results.append(try await tasks.value[key]!.value)
            }
        } catch {
            for task in tasks.value.values {
                task.cancel()
            }
            throw error
        }
        return results
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
}
