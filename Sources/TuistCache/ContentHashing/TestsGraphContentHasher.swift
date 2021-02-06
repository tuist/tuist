import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph

protocol TestsGraphContentHashing {
    func contentHashes(graph: Graph) throws -> [TargetNode: String]
}

/// `TestsGraphContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
final class TestsGraphContentHasher: TestsGraphContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    init(
        targetContentHasher: TargetContentHashing = TargetContentHasher(
            contentHasher: ContentHasher()
        )
    ) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - TestsGraphContentHashing

    func contentHashes(graph: Graph) throws -> [TargetNode: String] {
        var visitedTargets: [TargetNode: Bool] = [:]
        let hashableTargets = graph.targets
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
        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(
                for: $0,
                cacheOutputType: .none
            )
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Helpers

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
}
