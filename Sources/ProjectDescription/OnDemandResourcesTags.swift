/// On-demand resources tags associated with Initial Install and Prefetched Order categories
public struct OnDemandResourcesTags: Codable, Equatable, Sendable {
    /// Initial install tags associated with on demand resources
    public let initialInstall: [String]?
    /// Prefetched tag order associated with on demand resources
    public let prefetchOrder: [String]?

    /// Returns OnDemandResourcesTags.
    /// - Parameter initialInstall: An array of strings that lists the tags assosiated with the Initial install tags category.
    /// - Parameter prefetchOrder: An array of strings that lists the tags associated with the Prefetch tag order category.
    /// - Returns: OnDemandResourcesTags.
    public static func tags(initialInstall: [String]?, prefetchOrder: [String]?) -> Self {
        OnDemandResourcesTags(initialInstall: initialInstall, prefetchOrder: prefetchOrder)
    }
}
