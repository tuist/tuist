import XcodeGraph

/// A simplified version of `Target` to store in `CommandEvent`.
public struct RunTarget: Codable, Hashable {
    public let name: String
    public let product: Product
    public let bundleId: String
    public let productName: String
    public let destinations: Set<Destination>
    public let binaryCacheMetadata: RunCacheTargetMetadata?
    public let selectiveTestingMetadata: RunCacheTargetMetadata?

    public init(
        name: String,
        product: Product,
        bundleId: String,
        productName: String,
        destinations: Set<Destination>,
        binaryCacheMetadata: RunCacheTargetMetadata?,
        selectiveTestingMetadata: RunCacheTargetMetadata?
    ) {
        self.name = name
        self.product = product
        self.bundleId = bundleId
        self.productName = productName
        self.destinations = destinations
        self.binaryCacheMetadata = binaryCacheMetadata
        self.selectiveTestingMetadata = selectiveTestingMetadata
    }
}

#if DEBUG
    extension RunTarget {
        public static func test(
            name: String = "Target",
            product: Product = .framework,
            bundleId: String = "io.tuist.Target",
            productName: String = "Target",
            destinations: Set<Destination> = [.iPhone],
            binaryCacheMetadata: RunCacheTargetMetadata? = nil,
            selectiveTestingMetdata: RunCacheTargetMetadata? = nil
        ) -> Self {
            Self(
                name: name,
                product: product,
                bundleId: bundleId,
                productName: productName,
                destinations: destinations,
                binaryCacheMetadata: binaryCacheMetadata,
                selectiveTestingMetadata: selectiveTestingMetdata
            )
        }
    }
#endif
