import TuistCache
import TuistCore
import TuistExtension
import TuistGenerator
import TuistHasher
import TuistServer
import XcodeGraph
#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

public enum TuistKitExtension {
    #if canImport(TuistCacheEE)
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = CacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = CacheGeneratorFactory()
        @TaskLocal public static var cacheService: TuistExtension.CacheServicing = CacheService()
        @TaskLocal public static var selectiveTestingService: SelectiveTestingServicing = SelectiveTestingService()
        @TaskLocal public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing = SelectiveTestingGraphHasher()
    #else
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
        @TaskLocal public static var cacheService: TuistExtension.CacheServicing = TuistExtension.EmptyCacheService()
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
