import FileSystem
import Foundation
import Noora
import Path
import TuistCAS
import TuistConfigLoader
import TuistEnvironment
import TuistREAPI
import TuistServer

public protocol BazelCredentialHelperCommandServicing {
    func run(
        helperCommand: String,
        directory: String?
    ) async throws
}

public struct BazelCredentialHelperCommandService: BazelCredentialHelperCommandServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let configLoader: ConfigLoading
    private let cacheURLStore: CacheURLStoring
    private let fileSystem: FileSysteming
    private let date: () -> Date

    /// How far before a token's real expiry Bazel is asked to come back for a fresh
    /// credential. Bazel caches the credential we return until `expires` and only
    /// re-invokes this helper lazily, on the first request issued after that
    /// timestamp. Bringing the reported expiry forward — and refreshing proactively
    /// once the token is within this window — guarantees Bazel always rotates to a
    /// fresh token before the current one is rejected by the server, covering
    /// in-flight requests and clock skew between the developer machine and the cache.
    private static let expirySafetyMargin: TimeInterval = 60

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        configLoader: ConfigLoading = ConfigLoader(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        fileSystem: FileSysteming = FileSystem(),
        date: @escaping () -> Date = { Date() }
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.configLoader = configLoader
        self.cacheURLStore = cacheURLStore
        self.fileSystem = fileSystem
        self.date = date
    }

    public func run(
        helperCommand: String,
        directory: String?
    ) async throws {
        let response = try await credentials(helperCommand: helperCommand, directory: directory)
        try Noora.current.json(response)
        await refreshBazelrcEndpoint(directory: directory)
    }

    /// Points `.bazelrc.tuist` at wherever the account's cache is now.
    ///
    /// Bazel reads the file once at startup and nothing in a build re-resolves,
    /// so a cache placed in another region would otherwise strand the file:
    /// the region it names serves for a drain window, is torn down, and its
    /// hostname leaves DNS. This helper is the only Tuist code a build runs, so
    /// it is the only thing positioned to notice. Bazel re-invokes it lazily on
    /// the first request after the credential it returned expires, which makes
    /// the token lifetime the refresh interval — no timer needed, and no work
    /// on a build that is already authenticated.
    ///
    /// Written after the credential has been emitted, so resolving never
    /// delays the answer Bazel is waiting on, and best-effort throughout: an
    /// endpoint that cannot be resolved says nothing about where the cache
    /// went, and a build should not fail because its `.bazelrc` could not be
    /// tidied. The rewrite lands on the next build, since this one read the
    /// file before we ran.
    private func refreshBazelrcEndpoint(directory: String?) async {
        do {
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
            let bazelrcPath = directoryPath.appending(component: BazelrcFile.name)
            guard try await fileSystem.exists(bazelrcPath) else { return }

            let config = try await configLoader.loadConfig(path: directoryPath)
            guard let fullHandle = config.fullHandle else { return }
            let accountHandle = String(fullHandle.split(separator: "/")[0])
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
            guard let host = cacheURL.host else { return }
            let endpoint = GRPCEndpoint(host: host, explicitPort: cacheURL.port, isTLS: cacheURL.scheme != "http")

            let contents = try await fileSystem.readTextFile(at: bazelrcPath)
            guard let rewritten = BazelrcFile.replacingRemoteCache(in: contents, with: endpoint) else { return }

            try await fileSystem.writeText(
                rewritten,
                at: bazelrcPath,
                encoding: .utf8,
                options: Set([.overwrite])
            )
        } catch {
            // Best-effort by design; see above.
        }
    }

    func credentials(
        helperCommand: String,
        directory: String?
    ) async throws -> BazelCredentialHelperResponse {
        guard helperCommand == "get" else {
            throw BazelCredentialHelperCommandServiceError.unsupportedCommand(helperCommand)
        }

        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard var token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL)
        else {
            throw BazelCredentialHelperCommandServiceError.notAuthenticated
        }

        // If a refreshable user token is already within the safety margin of expiring,
        // refresh it now so Bazel caches a token with a full lifetime ahead of it
        // rather than one about to be rejected mid-build. Project tokens never expire
        // and account tokens cannot be refreshed, so they are returned as-is.
        if case let .user(accessToken, _) = token,
           accessToken.expiryDate.timeIntervalSince(date()) <= Self.expirySafetyMargin
        {
            do {
                try await serverAuthenticationController.refreshToken(serverURL: serverURL)
                if let refreshedToken = try await serverAuthenticationController
                    .authenticationToken(serverURL: serverURL)
                {
                    token = refreshedToken
                }
            } catch {
                // Best effort: if the proactive refresh fails (e.g. a transient network
                // error) fall back to the token we already have, which remains valid for
                // up to the safety margin.
            }
        }

        let expiryDate: Date? = switch token {
        case let .user(accessToken: accessToken, refreshToken: _):
            accessToken.expiryDate.addingTimeInterval(-Self.expirySafetyMargin)
        case let .account(accessToken):
            accessToken.expiryDate
        case .project:
            nil
        }

        return BazelCredentialHelperResponse(
            headers: ["Authorization": ["Bearer \(token.value)"]],
            expires: expiryDate.map { ISO8601DateFormatter().string(from: $0) }
        )
    }
}

struct BazelCredentialHelperResponse: Codable, Equatable {
    let headers: [String: [String]]
    let expires: String?
}

public enum BazelCredentialHelperCommandServiceError: LocalizedError, Equatable {
    case unsupportedCommand(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case let .unsupportedCommand(command):
            return "The credential helper command '\(command)' is not supported. Only 'get' is supported."
        case .notAuthenticated:
            return
                "You are not authenticated. Refer to the documentation for authentication options: https://tuist.dev/en/docs/guides/server/authentication"
        }
    }
}
