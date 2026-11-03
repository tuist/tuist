import Foundation

public struct Product: Equatable {
    public let sku: String
    public let name: String
    public let priceCents: Int

    public init(sku: String, name: String, priceCents: Int) {
        self.sku = sku
        self.name = name
        self.priceCents = priceCents
    }
}

public enum CatalogError: Error {
    case missingResource
    case malformed
}

public final class Catalog {
    public let products: [Product]

    public init(products: [Product]) {
        self.products = products
    }

    public convenience init(jsonData: Data) throws {
        guard let entries = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            throw CatalogError.malformed
        }
        let products = try entries.map { entry -> Product in
            guard let sku = entry["sku"] as? String,
                  let name = entry["name"] as? String,
                  let priceCents = entry["price_cents"] as? Int
            else { throw CatalogError.malformed }
            return Product(sku: sku, name: name, priceCents: priceCents)
        }
        self.init(products: products)
    }

    public static func bundled() throws -> Catalog {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "products", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try Catalog(jsonData: Data(contentsOf: url))
    }

    public func product(for sku: String) -> Product? {
        products.first { $0.sku == sku }
    }
}

private final class BundleToken {}
