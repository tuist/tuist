import Foundation

public protocol HashCacheServicing {
    func run(
        path: String?,
        configuration: String?
    ) async throws
}

public protocol CacheServicing {
    func run(
        path: String?,
        configuration: String?,
        targetsToBinaryCache: Set<String>,
        externalOnly: Bool,
        generateOnly: Bool
    ) async throws
}

public struct EmptyHashCacheService: HashCacheServicing {
    public init() {}
    public func run(
        path _: String?,
        configuration _: String?
    ) async throws {}
}

public struct EmptyCacheService: CacheServicing {
    public init() {}
    public func run(
        path _: String?,
        configuration _: String?,
        targetsToBinaryCache _: Set<String>,
        externalOnly _: Bool,
        generateOnly _: Bool
    ) async throws {
        print(
            "Caching is currently not opensourced. Please, report issues with caching on GitHub and the Tuist team will take a look."
        )
    }
}

public enum Extension {
    @TaskLocal public static var hashCacheService: HashCacheServicing = EmptyHashCacheService()
    @TaskLocal public static var cacheService: CacheServicing = EmptyCacheService()
}
