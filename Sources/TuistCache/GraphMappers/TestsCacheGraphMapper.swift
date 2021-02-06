import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public final class TestsCacheGraphMapper: GraphMapping {
    private let testsCacheDirectory: AbsolutePath
    private let testsGraphContentHasher: TestsGraphContentHashing
    
    /// - Parameters:
    ///     - testsCacheDirectory: Location where to save current hashes.
    /// This should be a temporary location if you don't want to save the hashes permanently.
    /// This is useful when you want to save the hashes of tests only after the tests have run successfully.
    public convenience init(
        testsCacheDirectory: AbsolutePath
    ) {
        self.init(
            testsCacheDirectory: testsCacheDirectory,
            testsGraphContentHasher: TestsGraphContentHasher()
        )
    }
    
    init(
        testsCacheDirectory: AbsolutePath,
        testsGraphContentHasher: TestsGraphContentHashing
    ) {
        self.testsCacheDirectory = testsCacheDirectory
        self.testsGraphContentHasher = testsGraphContentHasher
    }
    
    public func map(graph: Graph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        var graph = ValueGraph(graph: graph)
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let hashes = try testsGraphContentHasher.contentHashes(graphTraverser: graphTraverser)
        
        var visitedNodes: [ValueGraphTarget: Bool] = [:]
        var workspace = graph.workspace
        workspace.schemes = try workspace.schemes
            .compactMap { scheme in
                try map(
                    scheme: scheme,
                    graphTraverser: graphTraverser,
                    hashes: hashes,
                    visited: &visitedNodes
                )
            }
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

    private func testableTargets(scheme: Scheme, graphTraverser: GraphTraversing) -> [ValueGraphTarget] {
        scheme.testAction
            .map(\.targets)
            .map { testTargets in
                testTargets.compactMap { testTarget in
                    graphTraverser.target(
                        path: testTarget.target.projectPath,
                        name: testTarget.target.name
                    )
                }
            } ?? []
    }
    
    private func map(
        scheme: Scheme,
        graphTraverser: GraphTraversing,
        hashes: [ValueGraphTarget: String],
        visited: inout [ValueGraphTarget: Bool]
    ) throws -> Scheme? {
        var scheme = scheme
        guard let testAction = scheme.testAction else { return scheme }
        let cachedTestableTargets = testableTargets(
            scheme: scheme,
            graphTraverser: graphTraverser
        )
        .filter { testableTarget in
            if isCached(
                testableTarget,
                graphTraverser: graphTraverser,
                hashes: hashes,
                visited: &visited
            ) {
                logger.notice("\(testableTarget.target.name) has not changed from last successful run, skipping...")
                return true
            } else {
                return false
            }
        }
        
        scheme.testAction?.targets = testAction.targets.filter { testTarget in
            !cachedTestableTargets.contains(where: { $0.target.name == testTarget.target.name })
        }
        
        if scheme.testAction?.targets.isEmpty ?? true {
            return nil
        } else {
            return scheme
        }
    }

    // MARK: - Helpers

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
}
