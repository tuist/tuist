import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol CacheGraphContentHashing {
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - cacheProfile: Cache profile currently being used
    ///     - cacheOutputType: Output type of cache -> makes a different hash for a different output type
    func contentHashes(
        for graph: ValueGraph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) throws -> [ValueGraphTarget: String]
}

public final class CacheGraphContentHasher: CacheGraphContentHashing {
    private let graphContentHasher: GraphContentHashing
    private let cacheProfileContentHasher: CacheProfileContentHashing
    private let contentHasher: ContentHashing

    public convenience init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.init(
            graphContentHasher: GraphContentHasher(contentHasher: contentHasher),
            cacheProfileContentHasher: CacheProfileContentHasher(contentHasher: contentHasher),
            contentHasher: contentHasher
        )
    }

    public init(
        graphContentHasher: GraphContentHashing,
        cacheProfileContentHasher: CacheProfileContentHashing,
        contentHasher: ContentHashing
    ) {
        self.graphContentHasher = graphContentHasher
        self.cacheProfileContentHasher = cacheProfileContentHasher
        self.contentHasher = contentHasher
    }

    public func contentHashes(
        for graph: ValueGraph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) throws -> [ValueGraphTarget: String] {
        let graphTraverser = ValueGraphTraverser(graph: graph)
        return try graphContentHasher.contentHashes(
            for: graph,
            filter: { filterHashTarget($0, graphTraverser: graphTraverser) },
            additionalStrings: [
                cacheProfileContentHasher.hash(cacheProfile: cacheProfile),
                cacheOutputType.description,
            ]
        )
    }

    private func filterHashTarget(
        _ target: ValueGraphTarget,
        graphTraverser: GraphTraversing
    ) -> Bool {
        let isFramework = target.target.product == .framework || target.target.product == .staticFramework
        let noXCTestDependency = !graphTraverser.dependsOnXCTest(path: target.path, name: target.target.name)
        return isFramework && noXCTestDependency
    }
}
