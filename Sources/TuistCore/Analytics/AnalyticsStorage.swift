import Foundation
import Path
import ServiceContextModule
import XcodeGraph

/// Storage for analytics metadata, such as binary cache.
public final class AnalyticsStorage {
    public init() {}

    /// A unique ID associated with a specific run
    public var runId = UUID().uuidString
    /// Graph associated with the current run
    public var graph: Graph?
    /// Binar cache-specific analytics
    public var binaryCacheAnalytics: BinaryCacheAnalytics?
    /// Selective testing-specific analytics
    public var selectiveTestAnalytics: SelectiveTestsAnalytics?
    /// Preview ID associated with the current run
    public var previewId: String?
}

private enum AnalyticsStorageContextKey: ServiceContextKey {
    typealias Value = AnalyticsStorage
}

extension ServiceContext {
    public var analyticsStorage: AnalyticsStorage? {
        get {
            self[AnalyticsStorageContextKey.self]
        } set {
            self[AnalyticsStorageContextKey.self] = newValue
        }
    }
}
