import XcodeGraph

extension Target {
    public static let cacheableProducts: [Product] = [
        .framework,
        .staticFramework,
        .bundle,
        .macro,
        .staticLibrary,
        .dynamicLibrary,
    ]
    public var isCacheable: Bool {
        return Self.cacheableProducts.contains(product)
    }
}
