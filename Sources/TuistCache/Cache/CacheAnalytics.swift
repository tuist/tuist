import Foundation
import TuistSupport

public enum CacheAnalytics {
    private static let localCacheTargetsHitsLock = NSLock()
    public private(set) static var localCacheTargetsHits: Set<String> = []
    public static func addLocalCacheTargetHit(_ name: String) {
        localCacheTargetsHitsLock.lock()
        localCacheTargetsHits.insert(name)
        localCacheTargetsHitsLock.unlock()
    }

    private static let remoteCacheTargetsHitsLock = NSLock()
    public private(set) static var remoteCacheTargetsHits: Set<String> = []
    public static func addRemoteCacheTargetHit(_ name: String) {
        remoteCacheTargetsHitsLock.lock()
        remoteCacheTargetsHits.insert(name)
        remoteCacheTargetsHitsLock.unlock()
    }

    public static var cacheableTargets: [String] = []
}
