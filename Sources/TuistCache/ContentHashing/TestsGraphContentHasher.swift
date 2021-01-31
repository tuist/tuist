import Foundation
import TSCBasic
import TuistCore
import TuistSupport

protocol TestsGraphContentHashing {
    func contentHashes(for graph: TuistCore.Graph) throws -> [TargetNode: String]
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

    func contentHashes(for graph: TuistCore.Graph) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]
        let hashableTargets = graph.targets.values.flatMap { targets -> [TargetNode] in
            targets.compactMap { target in
                if self.isCacheable(target, visited: &visitedNodes) {
                    return target
                }
                return nil
            }
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

    private func isCacheable(_ target: TargetNode, visited: inout [TargetNode: Bool]) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        // UI tests depend on the device they are run on
        // This can be done in the future if we hash the ID of the device
        // But currently we consider these targets non-hashable
        let noXCUITestDependency = target.target.product != .uiTests
        let allTargetDependenciesAreHasheable = target.targetDependencies.allSatisfy { isCacheable($0, visited: &visited) }
        let cacheable = noXCUITestDependency && allTargetDependenciesAreHasheable
        visited[target] = cacheable
        return cacheable
    }
}
