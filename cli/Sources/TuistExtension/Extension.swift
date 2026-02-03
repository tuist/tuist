import TuistCache
import TuistCore
import TuistGenerator
import TuistHasher
import TuistServer
import XcodeGraph
#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

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

    #if canImport(TuistCacheEE)
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = CacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = CacheGeneratorFactory()
        @TaskLocal public static var selectiveTestingService: SelectiveTestingServicing = SelectiveTestingService()
        @TaskLocal public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing = SelectiveTestingGraphHasher()
    #else
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
        @TaskLocal public static var selectiveTestingService: SelectiveTestingServicing = EmptySelectiveTestingService()
        @TaskLocal public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing =
            EmptySelectiveTestingGraphHasher()
    #endif
}

#if !canImport(TuistCacheEE)
    public struct EmptySelectiveTestingGraphHasher: SelectiveTestingGraphHashing {
        public init() {}
        public func hash(graph _: Graph, additionalStrings _: [String]) async throws -> [GraphTarget: TargetContentHash] {
            [:]
        }
    }

    public struct EmptySelectiveTestingService: SelectiveTestingServicing {
        public init() {}
        public func cachedTests(
            testableGraphTargets _: [GraphTarget],
            selectiveTestingHashes _: [GraphTarget: String],
            selectiveTestingCacheItems _: [CacheItem]
        ) async throws -> [TestIdentifier] {
            []
        }
    }
#endif
