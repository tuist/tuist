public struct OnDemandResourcesTags: Codable, Equatable {
    public let initialInstall: [String]?
    public let prefetchOrder: [String]?

    public init(initialInstall: [String]?, prefetchOrder: [String]?) {
        self.initialInstall = initialInstall
        self.prefetchOrder = prefetchOrder
    }
}
