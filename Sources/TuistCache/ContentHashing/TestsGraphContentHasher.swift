import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph

protocol TestsGraphContentHashing {
    func contentHashes(graphTraverser: GraphTraversing) throws -> [ValueGraphTarget: String]
}

/// `TestsGraphContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
final class TestsGraphContentHasher: TestsGraphContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    init(targetContentHasher: TargetContentHashing = TargetContentHasher(contentHasher: ContentHasher())) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - TestsGraphContentHashing

    func contentHashes(graphTraverser: GraphTraversing) throws -> [ValueGraphTarget: String] {
        var visitedNodes: [ValueGraphTarget: Bool] = [:]
        let hashableTargets = graphTraverser.allTargets()
            .compactMap { target -> ValueGraphTarget? in
                if self.isCacheable(
                    target,
                    graphTraverser: graphTraverser,
                    visited: &visitedNodes
                ) {
                    return target
                }
                return nil
            }
        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(
                for: $0,
                cacheOutputType: .none
            )
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Helpers

    private func isCacheable(
        _ target: ValueGraphTarget,
        graphTraverser: GraphTraversing,
        visited: inout [ValueGraphTarget: Bool]
    ) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        // UI tests depend on the device they are run on
        // This can be done in the future if we hash the ID of the device
        // But currently we consider these targets non-hashable
        let noXCUITestDependency = target.target.product != .uiTests
        let allTargetDependenciesAreHasheable = graphTraverser
            .directTargetDependencies(
                path: target.path,
                name: target.target.name
            )
            .allSatisfy {
                isCacheable(
                    $0,
                    graphTraverser: graphTraverser,
                    visited: &visited
                )
            }
        let cacheable = noXCUITestDependency && allTargetDependenciesAreHasheable
        visited[target] = cacheable
        return cacheable
    }
}
