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
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) throws -> [GraphTarget: String]
}

public final class CacheGraphContentHasher: CacheGraphContentHashing {
    private let graphContentHasher: GraphContentHashing
    private let cacheProfileContentHasher: CacheProfileContentHashing
    private let contentHasher: ContentHashing
    private let xcodeBuildController: XcodeBuildControlling
    private static let cachableProducts: Set<Product> = [.framework, .staticFramework, .bundle]

    public convenience init(
        contentHasher: ContentHashing = ContentHasher(),
        xcodeBuildController: XcodeBuildControlling
    ) {
        self.init(
            graphContentHasher: GraphContentHasher(contentHasher: contentHasher),
            cacheProfileContentHasher: CacheProfileContentHasher(contentHasher: contentHasher),
            contentHasher: contentHasher,
            xcodeBuildController: xcodeBuildController
        )
    }

    public init(
        graphContentHasher: GraphContentHashing,
        cacheProfileContentHasher: CacheProfileContentHashing,
        contentHasher: ContentHashing,
        xcodeBuildController: XcodeBuildControlling
    ) {
        self.graphContentHasher = graphContentHasher
        self.cacheProfileContentHasher = cacheProfileContentHasher
        self.contentHasher = contentHasher
        self.xcodeBuildController = xcodeBuildController
    }

    public func contentHashes(
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType
    ) throws -> [GraphTarget: String] {
        let graphTraverser = GraphTraverser(graph: graph)
        return try graphContentHasher.contentHashes(
            for: graph,
            filter: { filterHashTarget($0, graphTraverser: graphTraverser) },
            additionalStrings: [
                cacheProfileContentHasher.hash(cacheProfile: cacheProfile),
                cacheOutputType.description,
                xcodeBuildController.version().toBlocking().single().value,
                Constants.version,
            ]
        )
    }

    private func filterHashTarget(
        _ target: GraphTarget,
        graphTraverser: GraphTraversing
    ) -> Bool {
        let product = target.target.product
        let isCachableProduct = CacheGraphContentHasher.cachableProducts.contains(product)
        let noXCTestDependency = !graphTraverser.dependsOnXCTest(
            path: target.path,
            name: target.target.name
        )

        return isCachableProduct && noXCTestDependency
    }
}
