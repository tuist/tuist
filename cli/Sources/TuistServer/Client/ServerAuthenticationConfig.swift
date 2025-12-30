public struct ServerAuthenticationConfig {
    @TaskLocal public static var current: ServerAuthenticationConfig = .init(backgroundRefresh: false)
    public let backgroundRefresh: Bool

    public init(backgroundRefresh: Bool = false) {
        self.backgroundRefresh = backgroundRefresh
    }
}
