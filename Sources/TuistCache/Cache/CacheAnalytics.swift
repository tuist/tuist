import Foundation
import TuistSupport

public enum CacheAnalytics {
    @Atomic
    public static var localCacheTargetsHits: Set<String> = []
    @Atomic
    public static var remoteCacheTargetsHits: Set<String> = []
    @Atomic
    public static var cacheableTargets: [String] = []
}
