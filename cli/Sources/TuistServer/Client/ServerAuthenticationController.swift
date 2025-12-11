import FileSystem
import Foundation
import Mockable
import OpenAPIRuntime
import Path
import TuistHTTP

#if canImport(TuistProcess)
    import TuistProcess
#endif

#if canImport(TuistSupport)
    import TuistSupport
#endif

public enum ServerAuthenticationControllerError: LocalizedError, Equatable {
    case failToLaunchRefreshProcess(command: String, arguments: [String], serverURL: URL)
    case timedOut(seconds: Int, serverURL: URL)
    case cantRefreshWithLockingAndBackground

    public var errorDescription: String? {
        switch self {
        case let .failToLaunchRefreshProcess(command, arguments, serverURL):
            let command = ([command] + arguments).joined(separator: " ")
            return
                "The refreshing of the access and refresh token pair for the URL \(serverURL.absoluteString) failed running the following command: \(command)"
        case let .timedOut(seconds, serverURL):
            return
                "The refreshing of the access and refresh token pair for the URL \(serverURL.absoluteString) failed after \(seconds) seconds."
        case .cantRefreshWithLockingAndBackground:
            return
                "The refreshing with background and locking configurations enabled is not a valid configuration (liley a bug)."
        }
    }
}

@Mockable
public protocol ServerAuthenticationControlling: Sendable {
    func authenticationToken(serverURL: URL) async throws -> AuthenticationToken?
    func refreshToken(serverURL: URL) async throws
    func refreshToken(serverURL: URL, inBackground: Bool, locking: Bool, forceInProcessLock: Bool)
        async throws
}

public enum AuthenticationTokenStatus {
    case valid(AuthenticationToken)
    case expired
    case absent
}

public enum AuthenticationToken: Equatable, CustomStringConvertible {
    /// The token represents a user session. User sessions are typically used in
    /// local environments where the user can be guided through an interactive
    /// authentication workflow
    case user(accessToken: JWT, refreshToken: JWT)

    /// The token represents a project session. Project sessions are typically used
    /// in CI environments where limited scopes are desired for security reasons.
    case project(String)

    /// The token represents an account session, typically obtained via OIDC from a CI provider.
    /// These tokens cannot be refreshed and are valid until expiry.
    case account(JWT)

    /// It returns the value of the token
    public var value: String {
        switch self {
        case .user(let accessToken, refreshToken: _):
            return accessToken.token
        case let .project(token):
            return token
        case let .account(accessToken):
            return accessToken.token
        }
    }

    public var description: String {
        switch self {
        case .user:
            return "User token: \(value)"
        case let .project(token):
            return "Project token: \(token)"
        case .account:
            return "Account token: \(value)"
        }
    }
}

#if canImport(TuistSupport)
    /// Actor responsible for serializing file system lock operations to prevent race conditions
    private actor FileSystemLockActor {
        private let fileSystem: FileSysteming

        init(fileSystem: FileSysteming) {
            self.fileSystem = fileSystem
        }

        func withLock<T>(
            lockfilePath: AbsolutePath,
            serverURL: URL,
            maxAttempts: Int = 10,
            retryInterval: UInt64 = 500, // Milliseconds
            action: (_ complete: () async throws -> Void) async throws -> Void,
            fetchActionResult: () async throws -> T?
        ) async throws -> T {
            return try await performLocked(
                lockfilePath: lockfilePath,
                serverURL: serverURL,
                attemptCount: 0,
                maxAttempts: maxAttempts,
                retryInterval: retryInterval,
                action: action,
                fetchActionResult: fetchActionResult
            )
        }

        private func performLocked<T>(
            lockfilePath: AbsolutePath,
            serverURL: URL,
            attemptCount: Int,
            maxAttempts: Int,
            retryInterval: UInt64,
            action: (_ complete: () async throws -> Void) async throws -> Void,
            fetchActionResult: () async throws -> T?
        ) async throws -> T {
            // Check if we already have the result
            if let result = try await fetchActionResult() {
                return result
            }

            if attemptCount >= maxAttempts {
                throw ServerAuthenticationControllerError.timedOut(
                    seconds: maxAttempts * Int(retryInterval) / 1000,
                    serverURL: serverURL
                )
            }

            let lockFileExists = try await fileSystem.exists(lockfilePath)
            let secondsSinceLastModified: Double? =
                if lockFileExists,
                let lastModificationDate = try await fileSystem
                .fileMetadata(at: lockfilePath)?.lastModificationDate {
                    Date().timeIntervalSince(lastModificationDate)
                } else {
                    nil
                }

            if !lockFileExists
                || (secondsSinceLastModified != nil && secondsSinceLastModified! > 10)
            {
                // Create directories if needed
                if !(try await fileSystem.exists(lockfilePath.parentDirectory)) {
                    try await fileSystem.makeDirectory(at: lockfilePath.parentDirectory)
                }

                // Remove stale lock file if it exists
                if try await fileSystem.exists(lockfilePath) {
                    try await fileSystem.remove(lockfilePath)
                }

                // Create lock file
                try? await fileSystem.touch(lockfilePath)

                // Perform the action
                try await action {
                    try? await fileSystem.remove(lockfilePath)
                }
            }

            // Check if result is now available
            if let result = try await fetchActionResult() {
                return result
            }

            // Wait and retry
            try await Task.sleep(nanoseconds: retryInterval * 1_000_000)

            return try await performLocked(
                lockfilePath: lockfilePath,
                serverURL: serverURL,
                attemptCount: attemptCount + 1,
                maxAttempts: maxAttempts,
                retryInterval: retryInterval,
                action: action,
                fetchActionResult: fetchActionResult
            )
        }
    }
#endif

// swiftlint:disable:next type_body_length
public struct ServerAuthenticationController: ServerAuthenticationControlling {
    private let refreshAuthTokenService: RefreshAuthTokenServicing
    private let fileSystem: FileSysteming
    private let cachedValueStore: CachedValueStoring
    #if canImport(TuistSupport)
        /// Shared actor instance across all ServerAuthenticationController instances
        private static let fileSystemLockActor: FileSystemLockActor = .init(
            fileSystem: FileSystem()
        )

        private let backgroundProcessRunner: BackgroundProcessRunning
    #endif

    #if canImport(TuistSupport)
        public init(
            refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService(),
            fileSystem: FileSysteming = FileSystem(),
            backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
            cachedValueStore: CachedValueStoring = CachedValueStore.current
        ) {
            self.refreshAuthTokenService = refreshAuthTokenService
            self.fileSystem = fileSystem
            self.backgroundProcessRunner = backgroundProcessRunner
            self.cachedValueStore = cachedValueStore
        }
    #else
        public init(
            refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService(),
            fileSystem: FileSysteming = FileSystem(),
            cachedValueStore: CachedValueStoring = CachedValueStore.current
        ) {
            self.refreshAuthTokenService = refreshAuthTokenService
            self.fileSystem = fileSystem
            self.cachedValueStore = cachedValueStore
        }
    #endif

    @discardableResult public func authenticationToken(serverURL: URL)
        async throws -> AuthenticationToken?
    {
        #if canImport(TuistSupport)
            if let environmentToken = try await environmentToken() {
                return environmentToken
            } else {
                return try await authenticationTokenRefreshingIfNeeded(
                    serverURL: serverURL,
                    forceRefresh: false,
                    inBackground: ServerAuthenticationConfig.current.backgroundRefresh,
                    locking: true
                )
            }
        #else
            return try await authenticationTokenRefreshingIfNeeded(
                serverURL: serverURL, forceRefresh: false,
                inBackground: ServerAuthenticationConfig.current.backgroundRefresh,
                locking: false
            )
        #endif
    }

    private func deletingCredentialsOnUnauthorizedError<T>(
        serverURL: URL, action: () async throws -> T
    ) async throws -> T {
        do {
            return try await action()
        } catch let error as RefreshAuthTokenServiceError {
            if case .unauthorized = error {
                #if canImport(TuistSupport)
                    Logger.current.debug("Deleting the credentials for \(serverURL)")
                #endif
                try? await ServerCredentialsStore.current.delete(serverURL: serverURL)
            }
            throw error
        } catch {
            throw error
        }
    }

    public func refreshToken(
        serverURL: URL, inBackground: Bool, locking: Bool, forceInProcessLock: Bool
    ) async throws {
        try await authenticationTokenRefreshingIfNeeded(
            serverURL: serverURL,
            forceRefresh: true,
            inBackground: inBackground,
            locking: locking,
            forceInProcessLock: forceInProcessLock
        )
    }

    public func refreshToken(serverURL: URL) async throws {
        try await authenticationTokenRefreshingIfNeeded(
            serverURL: serverURL,
            forceRefresh: true,
            inBackground: ServerAuthenticationConfig.current.backgroundRefresh,
            locking: true
        )
    }

    @discardableResult private func authenticationTokenRefreshingIfNeeded(
        serverURL: URL,
        forceRefresh: Bool,
        inBackground: Bool,
        locking: Bool,
        forceInProcessLock: Bool = false,
    ) async throws
        -> AuthenticationToken?
    {
        #if canImport(TuistSupport)
            Logger.current.debug("Refreshing authentication token for \(serverURL) if needed")
        #endif

        let fetchActionResult = { () async throws -> AuthenticationToken? in
            switch try await tokenStatus(serverURL: serverURL, forceRefresh: false) {
            case let .valid(token):
                return token
            case .expired, .absent:
                return nil
            }
        }

        switch (
            try await tokenStatus(serverURL: serverURL, forceRefresh: forceRefresh),
            inBackground,
            locking
        ) {
        case let (.valid(token), _, _):
            return token
        case (.absent, _, _):
            return nil
        case (.expired, false, true): // Foreground with locking
            if forceInProcessLock {
                return try await inProcessLockedRefresh(
                    serverURL: serverURL, forceRefresh: forceRefresh
                )
            } else {
                #if canImport(TuistSupport)
                    return try await cachedValueStore.getValue(key: lockKey(serverURL: serverURL)) {
                        let token = try await fileSystemLocked(
                            serverURL: serverURL,
                            action: { deleteLockfile in
                                _ = try await executeRefresh(
                                    serverURL: serverURL, forceRefresh: forceRefresh
                                )
                                try await deleteLockfile()
                            }, fetchActionResult: fetchActionResult
                        )
                        switch token {
                        case .project:
                            return (token, nil as Date?)
                        case let .account(accessToken):
                            return (token, accessToken.expiryDate)
                        case let .user(accessToken: _, refreshToken: refreshToken):
                            return (token, refreshToken.expiryDate)
                        }
                    }
                #else
                    return try await inProcessLockedRefresh(
                        serverURL: serverURL, forceRefresh: forceRefresh
                    )
                #endif
            }
        case (.expired, false, false): // Foreground without locking
            return try await executeRefresh(serverURL: serverURL, forceRefresh: forceRefresh)?.value
        case (.expired, true, true): // Background with locking
            #if canImport(TuistSupport)
                return try await cachedValueStore.getValue(key: lockKey(serverURL: serverURL)) {
                    let token = try await Self.fileSystemLockActor.withLock(
                        lockfilePath: lockFilePath(serverURL: serverURL),
                        serverURL: serverURL,
                        action: { _ in
                            try await spawnRefreshProcess(serverURL: serverURL)
                        },
                        fetchActionResult: fetchActionResult
                    )
                    switch token {
                    case .project:
                        return (token, nil as Date?)
                    case let .account(accessToken):
                        return (token, accessToken.expiryDate)
                    case let .user(accessToken: _, refreshToken: refreshToken):
                        return (token, refreshToken.expiryDate)
                    }
                }
            #else
                return nil
            #endif
        case (.expired, true, false): // Background without locking
            throw ServerAuthenticationControllerError.cantRefreshWithLockingAndBackground
        }
    }

    func inProcessLockedRefresh(serverURL: URL, forceRefresh: Bool) async throws
        -> AuthenticationToken?
    {
        return try await cachedValueStore.getValue(key: lockKey(serverURL: serverURL)) {
            return try await executeRefresh(serverURL: serverURL, forceRefresh: forceRefresh)
        }
    }

    #if canImport(TuistSupport)
        func fileSystemLocked<T>(
            serverURL: URL,
            attemptCount: Int = 0,
            action: (_ complete: () async throws -> Void) async throws -> Void,
            fetchActionResult: () async throws -> T?
        ) async throws -> T {
            let lockfilePath = lockFilePath(serverURL: serverURL)
            let maxAttempts = 30
            let retryInterval: UInt64 = 500 // Miliseconds
            if let result = try await fetchActionResult() { return result }

            if attemptCount >= maxAttempts {
                throw ServerAuthenticationControllerError.timedOut(
                    seconds: maxAttempts * Int(retryInterval) / 1000,
                    serverURL: serverURL
                )
            }

            let lockFileExists = try await fileSystem.exists(lockfilePath)
            let secondsSinceLastModified: Double? =
                if lockFileExists,
                let lastModificationDate = try await fileSystem
                .fileMetadata(at: lockfilePath)?.lastModificationDate {
                    Date().timeIntervalSince(lastModificationDate)
                } else {
                    nil
                }

            if !lockFileExists
                || (secondsSinceLastModified != nil && secondsSinceLastModified! > 10)
            {
                if !(try await fileSystem.exists(lockfilePath.parentDirectory)) {
                    try await fileSystem.makeDirectory(at: lockfilePath.parentDirectory)
                }
                if try await fileSystem.exists(lockfilePath) {
                    try await fileSystem.remove(lockfilePath)
                }

                try? await fileSystem.touch(lockfilePath)

                try await action {
                    // When the action runs in the foreground, the action can use this closure
                    // to notify that the action has been completed and therefore the lockfile
                    // can be deleted.
                    // In the background, the lockfile is deleted by the background task.
                    try? await fileSystem.remove(lockfilePath)
                }
            }

            // In the case of actions running in the foreground, the result
            // will be available right after the action completion
            if let result = try await fetchActionResult() { return result }

            try await Task.sleep(nanoseconds: retryInterval * 1_000_000)

            return try await fileSystemLocked(
                serverURL: serverURL,
                attemptCount: attemptCount + 1,
                action: action,
                fetchActionResult: fetchActionResult
            )
        }

        func spawnRefreshProcess(serverURL: URL) async throws {
            try backgroundProcessRunner.runInBackground(
                [Environment.current.currentExecutablePath()?.pathString ?? ""] + [
                    "auth",
                    "refresh-token",
                    serverURL.absoluteString,
                ], environment: ProcessInfo.processInfo.environment
            )
        }
    #endif

    func tokenStatus(serverURL: URL, forceRefresh: Bool) async throws -> AuthenticationTokenStatus {
        guard let token = try await fetchTokenFromStore(serverURL: serverURL) else {
            return .absent
        }

        switch token {
        case .project:
            return .valid(token)
        case let .account(accessToken):
            let now = Date.now()
            let expiresIn = accessToken.expiryDate.timeIntervalSince(now)
            if expiresIn < 30 { return .expired }
            return .valid(token)
        case let .user(
            accessToken, refreshToken
        ):
            // We consider a token to be expired if the expiration date is in the past or 30 seconds from now
            let now = Date.now()
            let expiresIn = accessToken.expiryDate
                .timeIntervalSince(now)
            let refresh = expiresIn < 30 || forceRefresh
            if refresh { return .expired }
            return .valid(
                .user(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
            )
        }
    }

    func executeRefresh(serverURL: URL, forceRefresh: Bool) async throws -> (
        value: AuthenticationToken, expiresAt: Date?
    )? {
        return try await deletingCredentialsOnUnauthorizedError(serverURL: serverURL) {
            guard let token = try await fetchTokenFromStore(serverURL: serverURL) else {
                return nil
            }

            let upToDateToken: AuthenticationToken
            var expiresAt: Date?

            switch token {
            case .project:
                upToDateToken = token
            case let .account(accessToken):
                upToDateToken = token
                expiresAt = accessToken.expiryDate
            case let .user(
                accessToken, refreshToken
            ):
                // We consider a token to be expired if the expiration date is in the past or 30 seconds from now
                let now = Date.now()
                let expiresIn = accessToken.expiryDate
                    .timeIntervalSince(now)
                let refresh = expiresIn < 30 || forceRefresh

                #if canImport(TuistSupport)
                    if refresh {
                        Logger.current.debug(
                            "Access token expires in less than \(expiresIn) seconds. Renewing..."
                        )
                    } else {
                        Logger.current.debug(
                            "Access token expires in \(expiresIn) seconds and it is still valid"
                        )
                    }
                #endif
                if refresh {
                    #if canImport(TuistSupport)
                        Logger.current.debug("Refreshing access token for \(serverURL)")
                    #endif
                    let tokens = try await refreshTokens(
                        serverURL: serverURL, refreshToken: refreshToken
                    )
                    #if canImport(TuistSupport)
                        Logger.current.debug("Access token refreshed for \(serverURL)")
                    #endif
                    upToDateToken = .user(
                        accessToken: try JWT.parse(tokens.accessToken),
                        refreshToken: try JWT.parse(tokens.refreshToken)
                    )
                    expiresAt = try JWT.parse(tokens.accessToken)
                        .expiryDate
                } else {
                    upToDateToken = .user(
                        accessToken: accessToken,
                        refreshToken: refreshToken
                    )
                    expiresAt = accessToken.expiryDate
                }
            }
            return (value: upToDateToken, expiresAt: expiresAt)
        }
    }

    #if canImport(TuistSupport)
        private func lockFilePath(serverURL: URL) -> AbsolutePath {
            let key = lockKey(serverURL: serverURL)
            // Use a sanitized version of the key for the filename
            let sanitizedKey = key.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: " ", with: "_")

            return Environment.current.stateDirectory
                .appending(component: "auth-locks")
                .appending(component: "\(sanitizedKey).lock")
        }
    #endif

    private func lockKey(serverURL: URL) -> String {
        "token_\(serverURL.absoluteString)"
    }

    private func fetchTokenFromStore(serverURL: URL) async throws -> AuthenticationToken? {
        let credentials: ServerCredentials? = try await ServerCredentialsStore.current.read(
            serverURL: serverURL
        )
        return try credentials.map {
            let accessToken = try JWT.parse($0.accessToken)
            if accessToken.type == "account" {
                return .account(accessToken)
            } else {
                return .user(
                    accessToken: accessToken,
                    refreshToken: try JWT.parse($0.refreshToken!)
                )
            }
        }
    }

    private func environmentToken() async throws -> AuthenticationToken? {
        #if canImport(TuistSupport)
            if let configToken = Environment.current.tuistVariables[
                Constants.EnvironmentVariables.token
            ] {
                return .project(configToken)
            } else if let deprecatedToken = Environment.current.tuistVariables[
                Constants.EnvironmentVariables.deprecatedToken
            ] {
                AlertController.current
                    .warning(
                        .alert(
                            "Use `TUIST_TOKEN` environment variable instead of `TUIST_CONFIG_TOKEN` to authenticate on the CI"
                        )
                    )
                return .project(deprecatedToken)
            } else if let deprecatedCloudToken = Environment.current.tuistVariables[
                "TUIST_CONFIG_CLOUD_TOKEN"
            ] {
                AlertController.current
                    .warning(
                        .alert(
                            "Use `TUIST_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
                        )
                    )
                return .project(deprecatedCloudToken)
            } else {
                return nil
            }
        #else
            return nil
        #endif
    }

    func isTuistDevURL(_ serverURL: URL) -> Bool {
        // URL fails if one of the URLs has a trailing slash and the other not.
        return serverURL.absoluteString.hasPrefix("https://tuist.dev")
    }

    private func refreshTokens(
        serverURL: URL,
        refreshToken: JWT
    ) async throws -> ServerAuthenticationTokens {
        do {
            let newTokens = try await RetryProvider()
                .runWithRetries {
                    return try await refreshAuthTokenService.refreshTokens(
                        serverURL: serverURL,
                        refreshToken: refreshToken.token
                    )
                }
            try await ServerCredentialsStore.current
                .store(
                    credentials: ServerCredentials(
                        accessToken: newTokens.accessToken,
                        refreshToken: newTokens.refreshToken
                    ),
                    serverURL: serverURL
                )
            return newTokens
        } catch let error as ClientError {
            let underlyingError = error.underlyingError as NSError
            switch URLError.Code(rawValue: underlyingError.code) {
            case .notConnectedToInternet:
                throw error
            default:
                throw ClientAuthenticationError.notAuthenticated
            }
        } catch let error as RefreshAuthTokenServiceError {
            throw error
        } catch {
            throw ClientAuthenticationError.notAuthenticated
        }
    }
}
