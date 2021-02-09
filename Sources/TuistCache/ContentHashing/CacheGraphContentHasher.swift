import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol CacheGraphContentHashing {
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - cacheOutputType: Output type of cache -> makes a different hash for a different output type
    func contentHashes(for graph: TuistCore.Graph, cacheOutputType: CacheOutputType) throws -> [TargetNode: String]
}

public final class CacheGraphContentHasher: CacheGraphContentHashing {
    private let graphContentHasher: GraphContentHashing
    private let contentHasher: ContentHashing

    public init(
        graphContentHasher: GraphContentHashing = GraphContentHasher(contentHasher: ContentHasher()),
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.graphContentHasher = graphContentHasher
        self.contentHasher = contentHasher
    }

    public func contentHashes(
        for graph: Graph,
        cacheOutputType: CacheOutputType
    ) throws -> [TargetNode: String] {
        try graphContentHasher.contentHashes(
            for: graph,
            filter: filterHashTarget
        )
        .mapValues { hash in
            try self.contentHasher.hash([
                hash,
                cacheOutputType.description,
            ])
        }
    }

    private func filterHashTarget(_ target: TargetNode) -> Bool {
        let isFramework = target.target.product == .framework || target.target.product == .staticFramework
        let noXCTestDependency = !target.dependsOnXCTest
        return isFramework && noXCTestDependency
    }
}
