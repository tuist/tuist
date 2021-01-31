import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol TestsTargetsContentHashing {
    func contentHashes(for testsTargets: [TargetNode]) throws -> [TargetNode: String]
}

/// `TestsTargetsContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
public final class TestsTargetsContentHasher: TestsTargetsContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    public convenience init() {
        let targetContentHasher = TargetContentHasher(contentHasher: ContentHasher())
        self.init(targetContentHasher: targetContentHasher)
    }

    public init(targetContentHasher: TargetContentHashing) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - TestsTargetsContentHashing

    public func contentHashes(for testsTargets: [TargetNode]) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]
        let hashableTargets = Set(
            testsTargets.compactMap { target -> [TargetNode]? in
                return self.cacheableTargets(target, visited: &visitedNodes)
            }
            .flatMap { $0 }
        )

        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(
                for: $0,
                cacheOutputType: .none
            )
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Private

    private func cacheableTargets(_ target: TargetNode, visited: inout [TargetNode: Bool]) -> [TargetNode]? {
        if let visitedValue = visited[target] { return visitedValue ? [target] : nil }
        // UI tests depend on the device they are run on
        // This can be done in the future if we hash the ID of the device
        // But currently we consider these targets non-hashable
        let noXCUITestDependency = target.target.product != .uiTests
        let allTargetDependencies = [target.targetDependencies] + target.targetDependencies.map { cacheableTargets($0, visited: &visited) }
        let allTargetDependenciesAreHasheable = allTargetDependencies.allSatisfy { $0 != nil }
        let cacheable = noXCUITestDependency && allTargetDependenciesAreHasheable
        visited[target] = cacheable
        let allTargets = [target] + allTargetDependencies.compactMap { $0 }.flatMap { $0 }
        return cacheable ? allTargets : nil
    }
}
