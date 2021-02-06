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

    init(
        targetContentHasher: TargetContentHashing = TargetContentHasher(
            contentHasher: ContentHasher()
        )
    ) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - TestsGraphContentHashing

    func contentHashes(graphTraverser: GraphTraversing) throws -> [ValueGraphTarget: String] {
        var visitedTargets: [ValueGraphTarget: Bool] = [:]
        let hashableTargets = graphTraverser.allTargets()
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
        _ target: ValueGraphTarget,
        graphTraverser: GraphTraversing,
        visited: inout [ValueGraphTarget: Bool]
    ) -> [ValueGraphTarget] {
        if visited[target] == true { return [] }
        let targetDependencies = graphTraverser
            .directTargetDependencies(
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
}
