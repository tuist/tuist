public struct ServerAuthenticationConfig {
    @TaskLocal public static var current: ServerAuthenticationConfig = .init(backgroundRefresh: false)
    public let backgroundRefresh: Bool
    public let optionalAuthentication: Bool

    public init(
        backgroundRefresh: Bool = false,
        optionalAuthentication: Bool = false
    ) {
        self.backgroundRefresh = backgroundRefresh
        self.optionalAuthentication = optionalAuthentication
    }
}
