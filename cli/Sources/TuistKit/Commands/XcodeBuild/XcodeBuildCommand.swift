import ArgumentParser
import Foundation
import Path
import TuistAutomation
import TuistCache
import TuistCore
import TuistHasher
import TuistServer
import TuistSupport
import XcodeGraph

#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

public struct XcodeBuildCommand: AsyncParsableCommand, TrackableParsableCommand,
    RecentPathRememberableCommand
{
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "xcodebuild",
            abstract:
            "tuist xcodebuild extends the xcodebuild CLI with server capabilities such as selective testing or analytics.",
            subcommands: [
                XcodeBuildTestCommand.self,
                XcodeBuildTestWithoutBuildingCommand.self,
                XcodeBuildBuildCommand.self,
                XcodeBuildBuildForTestingCommand.self,
                XcodeBuildArchiveCommand.self,
                XcodeBuildCommandReorderer.self,
            ],
            defaultSubcommand: XcodeBuildCommandReorderer.self
        )
    }

    var analyticsRequired: Bool { true }

    public init() {}
}

struct EmptySelectiveTestingGraphHasher: SelectiveTestingGraphHashing {
    func hash(graph _: Graph, additionalStrings _: [String]) async throws -> [GraphTarget: TargetContentHash] {
        [:]
    }
}

struct EmptySelectiveTestingService: SelectiveTestingServicing {
    func cachedTests(
        testableGraphTargets _: [GraphTarget],
        selectiveTestingHashes _: [GraphTarget: String], selectiveTestingCacheItems _: [CacheItem]
    ) async throws -> [TestIdentifier] {
        []
    }
}

#if canImport(TuistCacheEE)

    /// Tree-shakes testable targets which hashes have not changed from those in the tests cache directory
    /// Creates tests hash files into a `hashesCacheDirectory`
    public struct SelectiveTestingService: SelectiveTestingServicing {
        public init() {}

        public func cachedTests(
            testableGraphTargets: [GraphTarget],
            selectiveTestingHashes: [GraphTarget: String],
            selectiveTestingCacheItems: [CacheItem]
        ) async throws -> [TestIdentifier] {
            var visitedNodes: [GraphTarget: Bool] = [:]
            let cacheMap: [GraphTarget: Bool] = try await cacheMap(
                hashes: selectiveTestingHashes,
                cacheItems: selectiveTestingCacheItems
            )
            return try testableGraphTargets
                .filter {
                    isCached(
                        $0,
                        cacheMap: cacheMap,
                        visited: &visitedNodes
                    )
                }
                .map { try TestIdentifier(target: $0.target.name) }
        }

        // MARK: - Helpers

        private func cacheMap(
            hashes: [GraphTarget: String],
            cacheItems: [CacheItem]
        ) async throws -> [GraphTarget: Bool] {
            let fetchedItemHashes = Set(
                cacheItems
                    .map(\.hash)
            )

            return hashes.reduce([:]) { partialResult, item in
                var partialResult = partialResult
                partialResult[item.key] = fetchedItemHashes.contains(item.value)
                return partialResult
            }
        }

        private func isCached(
            _ target: GraphTarget,
            cacheMap: [GraphTarget: Bool],
            visited: inout [GraphTarget: Bool]
        ) -> Bool {
            if let visitedValue = visited[target] { return visitedValue }
            guard let isTargetCached = cacheMap[target] else {
                visited[target] = false
                return false
            }
            // Target is considered as cached if all its dependencies are cached and its hash is present in `testsCacheDirectory`
            // Hash of the target is saved to that directory only after a successful test run
            let isCached = isTargetCached
            visited[target] = isCached
            return isCached
        }
    }

    public struct SelectiveTestingGraphHasher: SelectiveTestingGraphHashing {
        private let graphContentHasher: GraphContentHashing

        public init(
            graphContentHasher: GraphContentHashing = GraphContentHasher(contentHasher: ContentHasher())
        ) {
            self.graphContentHasher = graphContentHasher
        }

        public func hash(
            graph: Graph,
            additionalStrings: [String]
        ) async throws -> [GraphTarget: TargetContentHash] {
            let graphTraverser = GraphTraverser(graph: graph)
            let hashableTargets = hashableTargets(graphTraverser: graphTraverser)
            return try await graphContentHasher.contentHashes(
                for: graph,
                include: hashableTargets.contains,
                destination: nil,
                additionalStrings: additionalStrings
            )
        }

        private func targetDependencies(
            _ target: GraphTarget,
            graphTraverser: GraphTraversing,
            visited: inout [GraphTarget: Bool]
        ) -> [GraphTarget] {
            if visited[target] == true { return [] }
            let targetDependencies = graphTraverser.directTargetDependencies(
                path: target.path,
                name: target.target.name
            )
            .flatMap {
                self.targetDependencies(
                    $0.graphTarget,
                    graphTraverser: graphTraverser,
                    visited: &visited
                )
            }
            visited[target] = true
            return targetDependencies + [target]
        }

        private func hashableTargets(graphTraverser: GraphTraversing) -> Set<GraphTarget> {
            var visitedTargets: [GraphTarget: Bool] = [:]
            return Set(
                graphTraverser.allTargets()
                    // UI tests depend on the device they are run on
                    // This can be done in the future if we hash the ID of the device
                    // But currently, we consider for hashing only unit tests and its dependencies
                    .filter { $0.target.product == .unitTests }
                    .flatMap { target -> [GraphTarget] in
                        let dependencies = targetDependencies(
                            target,
                            graphTraverser: graphTraverser,
                            visited: &visitedTargets
                        )
                        return dependencies
                    }
            )
        }
    }

#endif
