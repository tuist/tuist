import XcodeGraph

/// Queries for matching against a target.
public enum TargetQuery: Codable, Hashable, Sendable {
    /// Match targets with the given name.
    case named(String)
    /// Match targets with the given metadata tag.
    case tagged(String)
    /// Match targets with the given product type.
    case product(Product)
}

extension TargetQuery: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        let tagPrefix = "tag:"
        let productPrefix = "product:"
        if value.hasPrefix(tagPrefix) {
            self = .tagged(String(value.dropFirst(tagPrefix.count)))
        } else if value.hasPrefix(productPrefix) {
            let productValue = String(value.dropFirst(productPrefix.count))
            if let product = Product.allCases.first(where: { $0.caseValue == productValue }) {
                self = .product(product)
            } else {
                self = .named(value)
            }
        } else {
            self = .named(value)
        }
    }
}
