import Foundation

/// A ``ServerAuthenticationControlling`` decorator that memoizes the resolved token
/// in-process, bounded by the token's own expiry.
///
/// Hot callers — chiefly the CAS compilation-cache daemon, which resolves auth on
/// every artifact request — would otherwise read the credential from the macOS
/// keychain on every call. That read goes through `securityd` and serializes under
/// concurrency, which dominated per-request latency on hosted runners (hundreds of
/// ms/op for an operation whose wire time is ~1ms). Memoizing the token collapses
/// that to a single read per token lifetime; the wrapped controller's refresh and
/// rotation logic still runs whenever the memoized entry lapses shortly before the
/// token expires.
public struct CachingServerAuthenticationController: ServerAuthenticationControlling {
    private let wrapped: ServerAuthenticationControlling
    private let cache: TokenCache

    public init(wrapping wrapped: ServerAuthenticationControlling) {
        self.wrapped = wrapped
        cache = TokenCache()
    }

    public func authenticationToken(serverURL: URL) async throws -> AuthenticationToken? {
        try await authenticationToken(serverURL: serverURL, refreshIfNeeded: true)
    }

    public func authenticationToken(
        serverURL: URL,
        refreshIfNeeded: Bool
    ) async throws -> AuthenticationToken? {
        try await cache.value(for: serverURL, refreshIfNeeded: refreshIfNeeded) {
            try await wrapped.authenticationToken(serverURL: serverURL, refreshIfNeeded: refreshIfNeeded)
        }
    }

    public func refreshToken(serverURL: URL) async throws {
        try await wrapped.refreshToken(serverURL: serverURL)
    }

    public func refreshToken(
        serverURL: URL,
        inBackground: Bool,
        locking: Bool,
        forceInProcessLock: Bool
    ) async throws {
        try await wrapped.refreshToken(
            serverURL: serverURL,
            inBackground: inBackground,
            locking: locking,
            forceInProcessLock: forceInProcessLock
        )
    }
}

/// In-memory token store with expiry and single-flight so a burst of concurrent
/// resolutions performs at most one underlying (keychain) read per key.
private actor TokenCache {
    private struct Entry {
        let token: AuthenticationToken?
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<AuthenticationToken?, any Error>] = [:]

    func value(
        for serverURL: URL,
        refreshIfNeeded: Bool,
        compute: @Sendable @escaping () async throws -> AuthenticationToken?
    ) async throws -> AuthenticationToken? {
        let key = "\(refreshIfNeeded)-\(serverURL.absoluteString)"

        if let entry = entries[key], entry.expiresAt > Date() {
            return entry.token
        }
        if let inFlight = inFlight[key] {
            return try await inFlight.value
        }

        let task = Task { try await compute() }
        inFlight[key] = task
        do {
            let token = try await task.value
            inFlight[key] = nil
            entries[key] = Entry(token: token, expiresAt: Self.expiration(for: token))
            return token
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// User/account tokens are memoized until shortly before their JWT expiry so the
    /// refresh path re-runs in time; project tokens carry no refreshable expiry so
    /// they get a short TTL; an absent result is not memoized so a fresh login is
    /// picked up on the next call.
    private static func expiration(for token: AuthenticationToken?) -> Date {
        switch token {
        case let .user(accessToken, _):
            return accessToken.expiryDate.addingTimeInterval(-60)
        case let .account(accessToken):
            return accessToken.expiryDate.addingTimeInterval(-60)
        case .project:
            return Date().addingTimeInterval(300)
        case .none:
            return Date()
        }
    }
}
