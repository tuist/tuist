import TuistCache
import TuistCore
import TuistHasher
import TuistServer
#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

public enum Extension {
    #if canImport(TuistCacheEE)
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = CacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = CacheGeneratorFactory()
        @TaskLocal public static var cacheService: CacheServicing = CacheService()
        @TaskLocal public static var selectiveTestingService: SelectiveTestingServicing = SelectiveTestingService()
        @TaskLocal public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing = SelectiveTestingGraphHasher()
    #else
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
        @TaskLocal public static var cacheService: CacheServicing = EmptyCacheService()
        @TaskLocal public static var selectiveTestingService: SelectiveTestingServicing = EmptySelectiveTestingService()
        @TaskLocal public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing =
            EmptySelectiveTestingGraphHasher()
    #endif
}
