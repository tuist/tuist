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
    /// Names of the targets this target directly depends on (dependency-graph edges).
    public let dependencies: [String]

    public init(
        name: String,
        product: Product,
        bundleId: String,
        productName: String,
        destinations: Set<Destination>,
        binaryCacheMetadata: RunCacheTargetMetadata?,
        selectiveTestingMetadata: RunCacheTargetMetadata?,
        dependencies: [String] = []
    ) {
        self.name = name
        self.product = product
        self.bundleId = bundleId
        self.productName = productName
        self.destinations = destinations
        self.binaryCacheMetadata = binaryCacheMetadata
        self.selectiveTestingMetadata = selectiveTestingMetadata
        self.dependencies = dependencies
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        product = try container.decode(Product.self, forKey: .product)
        bundleId = try container.decode(String.self, forKey: .bundleId)
        productName = try container.decode(String.self, forKey: .productName)
        destinations = try container.decode(Set<Destination>.self, forKey: .destinations)
        binaryCacheMetadata = try container.decodeIfPresent(RunCacheTargetMetadata.self, forKey: .binaryCacheMetadata)
        selectiveTestingMetadata = try container.decodeIfPresent(RunCacheTargetMetadata.self, forKey: .selectiveTestingMetadata)
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
    }

    #if DEBUG
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
    #endif
}
