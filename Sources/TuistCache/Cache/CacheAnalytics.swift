import Foundation

public final class CacheAnalytics {
    public static var localCacheTargetsHits: Set<String> = []
    public static var remoteCacheTargetsHits: Set<String> = []
    public static var cacheableTargets: [String] = []
}
