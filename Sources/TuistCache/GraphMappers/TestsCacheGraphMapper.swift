import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Tree-shakes testable targets which hashes have not changed from those in the tests cache directory
/// Creates tests hash files into a `testsCacheDirectory`
public final class TestsCacheGraphMapper: GraphMapping {
    private let testsCacheDirectory: AbsolutePath
    private let graphContentHasher: GraphContentHashing

    /// - Parameters:
    ///     - testsCacheDirectory: Location where to save current hashes.
    /// This should be a temporary location if you don't want to save the hashes permanently.
    /// This is useful when you want to save the hashes of tests only after the tests have run successfully.
    public convenience init(
        testsCacheDirectory: AbsolutePath
    ) {
        self.init(
            testsCacheDirectory: testsCacheDirectory,
            graphContentHasher: GraphContentHasher(contentHasher: ContentHasher())
        )
    }

    init(
        testsCacheDirectory: AbsolutePath,
        graphContentHasher: GraphContentHashing
    ) {
        self.testsCacheDirectory = testsCacheDirectory
        self.graphContentHasher = graphContentHasher
    }

    @available(*, deprecated, message: "This method will be deleted soon. If you need to change code here, add it to map with ValueGraph, too")
    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let hashableTargets = self.hashableTargets(graph: graph)
        let hashes = try graphContentHasher.contentHashes(for: graph, filter: hashableTargets.contains)

        var visitedNodes: [TargetNode: Bool] = [:]
        var workspace = graph.workspace
        let mappedSchemes = try workspace.schemes
            .map { scheme -> (Scheme, [TargetNode]) in
                try map(
                    scheme: scheme,
                    graph: graph,
                    hashes: hashes,
                    visited: &visitedNodes
                )
            }
        let schemes = mappedSchemes.map(\.0)
        let cachedTestableTargets = mappedSchemes.flatMap(\.1)
        Set(cachedTestableTargets).forEach {
            logger.notice("\($0.target.name) has not changed from last successful run, skipping...")
        }
        workspace.schemes = schemes
        return (
            graph.with(
                workspace: workspace
            ),
            hashes.values.map {
                .file(
                    FileDescriptor(
                        path: testsCacheDirectory.appending(component: $0)
                    )
                )
            }
        )
    }

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let hashableTargets = self.hashableTargets(graphTraverser: graphTraverser)
        let hashes = try graphContentHasher.contentHashes(for: graph, filter: hashableTargets.contains)

        var visitedNodes: [ValueGraphTarget: Bool] = [:]
        var workspace = graph.workspace
        let mappedSchemes = try workspace.schemes
            .map { scheme -> (Scheme, [ValueGraphTarget]) in
                try map(
                    scheme: scheme,
                    graphTraverser: graphTraverser,
                    hashes: hashes,
                    visited: &visitedNodes
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
                        path: testsCacheDirectory.appending(component: $0)
                    )
                )
            }
        )
    }

    // MARK: - Helpers

    private func hashableTargets(graphTraverser: GraphTraversing) -> Set<ValueGraphTarget> {
        var visitedTargets: [ValueGraphTarget: Bool] = [:]
        return Set(
            graphTraverser.allTargets()
                // UI tests depend on the device they are run on
                // This can be done in the future if we hash the ID of the device
                // But currently, we consider for hashing only unit tests and its dependencies
                .filter { $0.target.product == .unitTests }
                .flatMap { target -> [ValueGraphTarget] in
                    targetDependencies(
                        target,
                        graphTraverser: graphTraverser,
                        visited: &visitedTargets
                    )
                }
        )
    }

    private func targetDependencies(
        _ target: ValueGraphTarget,
        graphTraverser: GraphTraversing,
        visited: inout [ValueGraphTarget: Bool]
    ) -> [ValueGraphTarget] {
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

    private func testableTargets(scheme: Scheme, graphTraverser: GraphTraversing) -> [ValueGraphTarget] {
        scheme.testAction
            .map(\.targets)
            .map { testTargets in
                testTargets.compactMap { testTarget in
                    guard
                        let target = graphTraverser.targets[testTarget.target.projectPath]?[testTarget.target.name],
                        let project = graphTraverser.projects[testTarget.target.projectPath]
                    else { return nil }
                    return ValueGraphTarget(
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
        hashes: [ValueGraphTarget: String],
        visited: inout [ValueGraphTarget: Bool]
    ) throws -> (Scheme, [ValueGraphTarget]) {
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
                visited: &visited
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
        _ target: ValueGraphTarget,
        graphTraverser: GraphTraversing,
        hashes: [ValueGraphTarget: String],
        visited: inout [ValueGraphTarget: Bool]
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
                visited: &visited
            )
        }
        guard let hash = hashes[target] else {
            visited[target] = false
            return false
        }
        /// Target is considered as cached if all its dependencies are cached and its hash is present in `testsCacheDirectory`
        /// Hash of the target is saved to that directory only after a successful test run
        let isCached = FileHandler.shared.exists(
            Environment.shared.testsCacheDirectory.appending(component: hash)
        ) && allTargetDependenciesAreHashed
        visited[target] = isCached
        return isCached
    }

    private func hashableTargets(graph: Graph) -> Set<TargetNode> {
        var visitedTargets: [TargetNode: Bool] = [:]
        return Set(
            graph.targets
                .flatMap(\.value)
                // UI tests depend on the device they are run on
                // This can be done in the future if we hash the ID of the device
                // But currently, we consider for hashing only unit tests and its dependencies
                .filter { $0.target.product == .unitTests }
                .flatMap { target -> [TargetNode] in
                    targetDependencies(
                        target,
                        visited: &visitedTargets
                    )
                }
        )
    }

    private func targetDependencies(
        _ target: TargetNode,
        visited: inout [TargetNode: Bool]
    ) -> [TargetNode] {
        if visited[target] == true { return [] }
        let targetDependencies = target.targetDependencies
            .flatMap {
                self.targetDependencies(
                    $0,
                    visited: &visited
                )
            }
        visited[target] = true
        return targetDependencies + [target]
    }

    private func testableTargets(scheme: Scheme, graph: Graph) -> [TargetNode] {
        scheme.testAction
            .map(\.targets)
            .map { testTargets in
                testTargets.compactMap { testTarget in
                    graph.target(
                        path: testTarget.target.projectPath,
                        name: testTarget.target.name
                    )
                }
            } ?? []
    }

    /// - Returns: Mapped scheme and cached testable targets
    private func map(
        scheme: Scheme,
        graph: Graph,
        hashes: [TargetNode: String],
        visited: inout [TargetNode: Bool]
    ) throws -> (Scheme, [TargetNode]) {
        var scheme = scheme
        guard let testAction = scheme.testAction else { return (scheme, []) }
        let cachedTestableTargets = testableTargets(
            scheme: scheme,
            graph: graph
        )
        .filter { testableTarget in
            isCached(
                testableTarget,
                hashes: hashes,
                visited: &visited
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
        _ target: TargetNode,
        hashes: [TargetNode: String],
        visited: inout [TargetNode: Bool]
    ) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        let allTargetDependenciesAreHashed = target.targetDependencies
            .allSatisfy {
                self.isCached(
                    $0,
                    hashes: hashes,
                    visited: &visited
                )
            }
        guard let hash = hashes[target] else {
            visited[target] = false
            return false
        }
        /// Target is considered as cached if all its dependencies are cached and its hash is present in `testsCacheDirectory`
        /// Hash of the target is saved to that directory only after a successful test run
        let isCached = FileHandler.shared.exists(
            Environment.shared.testsCacheDirectory.appending(component: hash)
        ) && allTargetDependenciesAreHashed
        visited[target] = isCached
        return isCached
    }
}
