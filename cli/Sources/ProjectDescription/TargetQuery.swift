/// Queries for matching against a target in manifests.
public enum TargetQuery: Codable, Equatable, Sendable {
    /// Match targets with the given name.
    case named(String)
    /// Match targets with the given metadata tag.
    case tagged(String)
    /// Match targets with the given product type.
    case product(Product)

    private enum CodingKeys: String, CodingKey {
        case named
        case tagged
        case product
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .named) {
            self = .named(name)
        } else if let tag = try container.decodeIfPresent(String.self, forKey: .tagged) {
            self = .tagged(tag)
        } else if let product = try container.decodeIfPresent(Product.self, forKey: .product) {
            self = .product(product)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid TargetQuery encoding")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .named(name):
            try container.encode(name, forKey: .named)
        case let .tagged(tag):
            try container.encode(tag, forKey: .tagged)
        case let .product(product):
            try container.encode(product, forKey: .product)
        }
    }
}

extension TargetQuery: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let tagPrefix = "tag:"
        let productPrefix = "product:"
        if value.hasPrefix(tagPrefix) {
            self = .tagged(String(value.dropFirst(tagPrefix.count)))
        } else if value.hasPrefix(productPrefix) {
            let productValue = String(value.dropFirst(productPrefix.count))
            if let product = Product(rawValue: productValue) {
                self = .product(product)
            } else {
                self = .named(value)
            }
        } else {
            self = .named(value)
        }
    }
}
