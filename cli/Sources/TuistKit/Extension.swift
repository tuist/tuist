import TuistCache
import TuistHasher
import TuistServer

public enum Extension {
    @TaskLocal public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    @TaskLocal public static var cacheService: CacheServicing = EmptyCacheService()
    @TaskLocal public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
    @TaskLocal public static var selectiveTestingGraphHasher: SelectiveTestingGraphHashing = EmptySelectiveTestingGraphHasher()
    @TaskLocal public static var selectiveTestingService: SelectiveTestingServicing = EmptySelectiveTestingService()
}
