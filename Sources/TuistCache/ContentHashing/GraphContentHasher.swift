import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol GraphContentHashing {
    func contentHashes(graphTraverser: GraphTraversing, cacheOutputType: CacheOutputType) throws -> [ValueGraphTarget: String]
}

/// `GraphContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
public final class GraphContentHasher: GraphContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing) {
        let targetContentHasher = TargetContentHasher(contentHasher: contentHasher)
        self.init(contentHasher: contentHasher, targetContentHasher: targetContentHasher)
    }

    public init(contentHasher _: ContentHashing, targetContentHasher: TargetContentHashing) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - GraphContentHashing

    public func contentHashes(graphTraverser: GraphTraversing, cacheOutputType: CacheOutputType) throws -> [ValueGraphTarget: String] {
        let hashableTargets = graphTraverser.allTargets().compactMap { (target: ValueGraphTarget) -> ValueGraphTarget? in
            let isCacheable = target.target.product == .framework || target.target.product == .staticFramework
            if isCacheable {
                return target
            }
            return nil
        }
        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(for: $0, cacheOutputType: cacheOutputType)
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }
}
