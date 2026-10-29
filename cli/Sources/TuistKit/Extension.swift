import TuistCore
import TuistServer
#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

public enum Extension {
    #if canImport(TuistCacheEE)
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = CacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = CacheGeneratorFactory()
    #else
        @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
        @TaskLocal public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    #endif
}
