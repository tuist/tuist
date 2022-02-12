import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Tree-shakes testable targets which hashes have not changed from those in the tests cache directory
/// Creates tests hash files into a `hashesCacheDirectory`
public final class TestsCacheGraphMapper: GraphMapping {
    let hashesCacheDirectory: AbsolutePath
    let config: Config
    private let graphContentHasher: GraphContentHashing
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring

    /// - Parameters:
    ///     - hashesCacheDirectory: Location where to save current hashes.
    /// This should be a temporary location if you don't want to save the hashes permanently.
    /// This is useful when you want to save the hashes of tests only after the tests have run successfully.
    public convenience init(
        hashesCacheDirectory: AbsolutePath,
        config: Config
    ) {
        self.init(
            hashesCacheDirectory: hashesCacheDirectory,
            config: config,
            graphContentHasher: GraphContentHasher(contentHasher: ContentHasher()),
            cacheDirectoryProviderFactory: CacheDirectoriesProviderFactory()
        )
    }

    init(
        hashesCacheDirectory: AbsolutePath,
        config: Config,
        graphContentHasher: GraphContentHashing,
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    ) {
        self.hashesCacheDirectory = hashesCacheDirectory
        self.config = config
        self.graphContentHasher = graphContentHasher
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
    }

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)
        let hashableTargets = hashableTargets(graphTraverser: graphTraverser)
        let hashes = try graphContentHasher.contentHashes(for: graph, filter: hashableTargets.contains)
        let testsCacheDirectory = try cacheDirectoryProviderFactory.cacheDirectories(config: config).cacheDirectory(for: .tests)
        var visitedNodes: [GraphTarget: Bool] = [:]
        var workspace = graph.workspace
        let mappedSchemes = try workspace.schemes
            .map { scheme -> (Scheme, [GraphTarget]) in
                try map(
                    scheme: scheme,
                    graphTraverser: graphTraverser,
                    hashes: hashes,
                    visited: &visitedNodes,
                    testsCacheDirectory: testsCacheDirectory
                )
            }
        let schemes = mappedSchemes.map(\.0)
        let cachedTestableTargets = mappedSchemes.flatMap(\.1)
        Set(cachedTestableTargets).forEach {
            logger.notice("\($0.target.name) has not changed from last successful run, skipping...")
        }
        workspace.schemes = schemes
        var graph = graph
        graph.workspace = workspace
        return (
            graph,
            hashes.values.map {
                .file(
                    FileDescriptor(
                        path: hashesCacheDirectory.appending(component: $0)
                    )
                )
            }
        )
    }

    // MARK: - Helpers

    private func hashableTargets(graphTraverser: GraphTraversing) -> Set<GraphTarget> {
        var visitedTargets: [GraphTarget: Bool] = [:]
        return Set(
            graphTraverser.allTargets()
                // UI tests depend on the device they are run on
                // This can be done in the future if we hash the ID of the device
                // But currently, we consider for hashing only unit tests and its dependencies
                .filter { $0.target.product == .unitTests }
                .flatMap { target -> [GraphTarget] in
                    targetDependencies(
                        target,
                        graphTraverser: graphTraverser,
                        visited: &visitedTargets
                    )
                }
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
                $0,
                graphTraverser: graphTraverser,
                visited: &visited
            )
        }
        visited[target] = true
        return targetDependencies + [target]
    }

    private func testableTargets(scheme: Scheme, graphTraverser: GraphTraversing) -> [GraphTarget] {
        scheme.testAction
            .map(\.targets)
            .map { testTargets in
                testTargets.compactMap { testTarget in
                    guard let target = graphTraverser.targets[testTarget.target.projectPath]?[testTarget.target.name],
                          let project = graphTraverser.projects[testTarget.target.projectPath]
                    else { return nil }
                    return GraphTarget(
                        path: testTarget.target.projectPath,
                        target: target,
                        project: project
                    )
                }
            } ?? []
    }

    /// - Returns: Mapped scheme and cached testable targets
    private func map(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        hashes: [GraphTarget: String],
        visited: inout [GraphTarget: Bool],
        testsCacheDirectory: AbsolutePath
    ) throws -> (Scheme, [GraphTarget]) {
        var scheme = scheme
        guard let testAction = scheme.testAction else { return (scheme, []) }
        let cachedTestableTargets = testableTargets(
            scheme: scheme,
            graphTraverser: graphTraverser
        )
        .filter { testableTarget in
            isCached(
                testableTarget,
                graphTraverser: graphTraverser,
                hashes: hashes,
                visited: &visited,
                testsCacheDirectory: testsCacheDirectory
            )
        }

        scheme.testAction?.targets = testAction.targets.filter { testTarget in
            !cachedTestableTargets.contains(where: { $0.target.name == testTarget.target.name })
        }

        if let buildAction = scheme.buildAction {
            scheme.buildAction?.targets = buildAction.targets.filter { buildTarget in
                !cachedTestableTargets.contains(where: { $0.target.name == buildTarget.name })
            }
        }

        return (scheme, cachedTestableTargets)
    }

    private func isCached(
        _ target: GraphTarget,
        graphTraverser: GraphTraversing,
        hashes: [GraphTarget: String],
        visited: inout [GraphTarget: Bool],
        testsCacheDirectory: AbsolutePath
    ) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        let allTargetDependenciesAreHashed = graphTraverser.directTargetDependencies(
            path: target.path,
            name: target.target.name
        )
        .allSatisfy {
            self.isCached(
                $0,
                graphTraverser: graphTraverser,
                hashes: hashes,
                visited: &visited,
                testsCacheDirectory: testsCacheDirectory
            )
        }
        guard let hash = hashes[target] else {
            visited[target] = false
            return false
        }
        /// Target is considered as cached if all its dependencies are cached and its hash is present in `testsCacheDirectory`
        /// Hash of the target is saved to that directory only after a successful test run
        let isCached = FileHandler.shared.exists(
            testsCacheDirectory.appending(component: hash)
        ) && allTargetDependenciesAreHashed
        visited[target] = isCached
        return isCached
    }
}
