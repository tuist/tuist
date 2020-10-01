import TuistCore

/// A struct that groups the configuration for caching.
struct CacheConfig {
    /// A boolean that indicates whether the cache is enabled or not.
    let cache: Bool

    /// It indicates whether the cache should work with simulator frameworks, or xcframeworks built for simulator and device.
    let cacheOutputType: CacheOutputType

    /// A static initializer that returns a config with the caching disabled.
    /// - Returns: An instance of the config.
    static func withoutCaching() -> CacheConfig {
        CacheConfig(cache: false, cacheOutputType: .framework)
    }

    /// A static initializer that returns a config with the caching enabled.
    /// - Parameter cacheOutputType: It indicates whether the cache should work with simulator frameworks, or xcframeworks built for simulator and device.
    /// - Returns: An instance of the config.
    static func withCaching(cacheOutputType: CacheOutputType = .framework) -> CacheConfig {
        CacheConfig(cache: true, cacheOutputType: cacheOutputType)
    }
}
