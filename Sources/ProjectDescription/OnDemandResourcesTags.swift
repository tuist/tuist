/// On-demand resources tags associated with Initial Install and Prefetched Order categories
public struct OnDemandResourcesTags: Codable, Equatable {
    /// Initial install tags associated with on demand resources
    public let initialInstall: [String]?
    /// Prefetched tag order associated with on demand resources
    public let prefetchOrder: [String]?

    public init(initialInstall: [String]?, prefetchOrder: [String]?) {
        self.initialInstall = initialInstall
        self.prefetchOrder = prefetchOrder
    }
}
