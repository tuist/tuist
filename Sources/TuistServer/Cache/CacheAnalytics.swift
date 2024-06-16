import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheAnalyticsStoring: AnyObject {
    var localCacheTargetsHits: [String] { get set }
    var remoteCacheTargetsHits: [String] { get set }
    var cacheableTargets: [String] { get set }
    var testTargets: [String] { get set }
    var localTestTargetHits: [String] { get set }
    var remoteTestTargetHits: [String] { get set }
    /// Map of a relative path of a project that has a map of a target name to its hash
    var targetHashes: [GraphTarget: String] { get set }
    var graphPath: AbsolutePath? { get set }
}

public final class CacheAnalyticsStore: CacheAnalyticsStoring {
    public var localCacheTargetsHits: [String] = []
    public var remoteCacheTargetsHits: [String] = []
    public var cacheableTargets: [String] = []
    public var testTargets: [String] = []
    public var localTestTargetHits: [String] = []
    public var remoteTestTargetHits: [String] = []
    public var targetHashes: [GraphTarget: String] = [:]
    public var graphPath: AbsolutePath?

    public static let shared = CacheAnalyticsStore()
}
