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

    public func enablingOptionalAuthentication() -> Self {
        .init(
            backgroundRefresh: backgroundRefresh,
            optionalAuthentication: true
        )
    }

    public static func withOptionalAuthentication<T>(
        _ isEnabled: Bool,
        _ operation: () async throws -> T
    ) async throws -> T {
        guard isEnabled else {
            return try await operation()
        }

        return try await $current.withValue(current.enablingOptionalAuthentication()) {
            try await operation()
        }
    }
}
