import FileSystem
import Foundation
import Mockable
import OpenAPIRuntime
import Path

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
            return "The refreshing of the access and refresh token pair for the URL \(serverURL.absoluteString) failed running the following command: \(command)"
        case let .timedOut(seconds, serverURL):
            return "The refreshing of the access and refresh token pair for the URL \(serverURL.absoluteString) failed after \(seconds) seconds."
        case .cantRefreshWithLockingAndBackground:
            return "The refreshing with background and locking configurations enabled is not a valid configuration (liley a bug)."
        }
    }
}

@Mockable
public protocol ServerAuthenticationControlling: Sendable {
    func authenticationToken(serverURL: URL) async throws
        -> AuthenticationToken?
    func refreshToken(serverURL: URL) async throws
    func refreshToken(serverURL: URL, inBackground: Bool, locking: Bool) async throws
}

public enum AuthenticationTokenStatus {
    case valid(AuthenticationToken)
    case expired
    case absent
}

public enum AuthenticationToken: CustomStringConvertible, Equatable {
    /// The token represents a user session. User sessions are typically used in
    /// local environments where the user can be guided through an interactive
    /// authentication workflow
    case user(accessToken: JWT, refreshToken: JWT)

    /// The token represents a project session. Project sessions are typically used
    /// in CI environments where limited scopes are desired for security reasons.
    case project(String)

    /// It returns the value of the token
    public var value: String {
        switch self {
        case let .user(accessToken: accessToken, refreshToken: _):
            return accessToken.token
        case let .project(token):
            return token
        }
    }

    public var description: String {
        switch self {
        case .user:
            return "tuist user token: \(value)"
        case let .project(token):
            return "tuist project token: \(token)"
        }
    }
}

public struct ServerAuthenticationController: ServerAuthenticationControlling {
    private let refreshAuthTokenService: RefreshAuthTokenServicing
    private let fileSystem: FileSysteming
    #if canImport(TuistSupport)
    private let backgroundProcessRunner: BackgroundProcessRunning
    #endif
    
    #if canImport(TuistSupport)
    public init(
        refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService(),
        fileSystem: FileSysteming = FileSystem(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner()
    ) {
        self.refreshAuthTokenService = refreshAuthTokenService
        self.fileSystem = fileSystem
        self.backgroundProcessRunner = backgroundProcessRunner
    }
    #else
    public init(
        refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.refreshAuthTokenService = refreshAuthTokenService
        self.fileSystem = fileSystem
    }
    #endif
    
    func defaultInBackground() -> Bool {
#if canImport(TuistSupport)
        let environment = Environment.current
        switch environment.product {
        case .app:
            return false
        case .cli:
            return true
        case .none:
            return false
        }
#else
        return false
#endif
    }
    
    @discardableResult public func authenticationToken(serverURL: URL)
    async throws -> AuthenticationToken?
    {
#if canImport(TuistSupport)
        if Environment.current.isCI {
            return try await ciAuthenticationToken()
        } else {
            return try await authenticationTokenRefreshingIfNeeded(
                serverURL: serverURL,
                forceRefresh: false,
                inBackground: defaultInBackground(),
                locking: true
            )
        }
#else
        return try await authenticationTokenRefreshingIfNeeded(
            serverURL: serverURL, forceRefresh: false, inBackground: defaultInBackground(), locking: false
        )
#endif
    }

    public func refreshToken(serverURL: URL, inBackground: Bool, locking: Bool) async throws {
        try await authenticationTokenRefreshingIfNeeded(
            serverURL: serverURL,
            forceRefresh: true,
            inBackground: inBackground,
            locking: locking
        )
    }

    public func refreshToken(serverURL: URL) async throws {
        try await authenticationTokenRefreshingIfNeeded(
            serverURL: serverURL,
            forceRefresh: true,
            inBackground: defaultInBackground(),
            locking: true
        )
    }

    @discardableResult private func authenticationTokenRefreshingIfNeeded(
        serverURL: URL,
        forceRefresh: Bool,
        inBackground: Bool,
        locking: Bool,
        attemptCount: Int = 0
    ) async throws
        -> AuthenticationToken?
    {
        #if canImport(TuistSupport)
            Logger.current.debug("Refreshing authentication token for \(serverURL) if needed")
        #endif
        
        let fetchActionResult = { () async throws -> AuthenticationToken? in
            switch try await self.tokenStatus(serverURL: serverURL, forceRefresh: forceRefresh) {
            case .valid(let token): return token
            case .expired, .absent: return nil
            }
        }

        switch (try await tokenStatus(serverURL: serverURL, forceRefresh: forceRefresh), inBackground, locking) {
        case let (.valid(token), _, _):
            return token
        case (.absent, _, _):
            throw ServerClientAuthenticationError.notAuthenticated
        case (.expired, false, true): // Foreground with locking
            return try await locked(serverURL: serverURL, action: { deleteLockfile in
                _ = try await executeRefresh(serverURL: serverURL, forceRefresh: forceRefresh)
                try await deleteLockfile()
            }, fetchActionResult: fetchActionResult)
        case (.expired, false, false): // Foreground without locking
            return try await executeRefresh(serverURL: serverURL, forceRefresh: forceRefresh)?.value
        case (.expired, true, true): // Background with locking
            #if canImport(TuistSupport)
            return try await locked(serverURL: serverURL, action: { _deleteLockfile in
                try await spawnRefreshProcess(serverURL: serverURL)
            }, fetchActionResult: fetchActionResult)
            #else
            return nil
            #endif
        case (.expired, true, false): // Background without locking
            throw ServerAuthenticationControllerError.cantRefreshWithLockingAndBackground
        }
    }
    
    func locked<T>(serverURL: URL, attemptCount: Int = 0, action: (_ complete: () async throws -> Void) async throws -> Void,  fetchActionResult: () async throws -> T?) async throws -> T {
//        fileSystemLocked(serverURL: serverURL, action: action, fetchActionResult: <#T##() async throws -> T?#>)
#if canImport(TuistSupport)
        
        #else
        
        #endif
    }
    
    #if canImport(TuistSupport)
    func spawnRefreshProcess(serverURL: URL) async throws {
        try backgroundProcessRunner.runInBackground([Environment.current.currentExecutablePath()?.pathString ?? ""] + [
            "auth",
            "refresh-token",
            serverURL.absoluteString,
        ], environment: ProcessInfo.processInfo.environment)
    }
    
    func fileSystemLocked<T>(serverURL: URL, attemptCount: Int = 0, action: (_ complete: () async throws -> Void) async throws -> Void,  fetchActionResult: () async throws -> T?) async throws -> T {
        let lockfilePath = lockFilePath(serverURL: serverURL)
        let maxAttempts = 10
        let retryInterval: UInt64 = 500 // Miliseconds
        if let result = try await fetchActionResult() { return result }
        
        if attemptCount >= maxAttempts {
            throw ServerAuthenticationControllerError.timedOut(
                seconds: maxAttempts * Int(retryInterval) / 1000,
                serverURL: serverURL
            )
        }
        
        let lockFileExists = try await fileSystem.exists(lockfilePath)
        if !lockFileExists {
            if !(try await fileSystem.exists(lockfilePath.parentDirectory)) { try await fileSystem.makeDirectory(at: lockfilePath.parentDirectory) }
            try await fileSystem.touch(lockfilePath)
            
            try await action {
                // When the action runs in the foreground, the action can use this closure
                // to notify that the action has been completed and therefore the lockfile
                // can be deleted.
                // In the background, the lockfile is deleted by the background task.
                try await fileSystem.remove(lockfilePath)
            }
        }
        
        // In the case of actions running in the foreground, the result
        // will be available right after the action completion
        if let result = try await fetchActionResult() { return result }
       
        try await Task.sleep(nanoseconds: retryInterval * 1_000_000)
        
        return try await locked(serverURL: serverURL, attemptCount: attemptCount + 1, action: action, fetchActionResult: fetchActionResult)
    }
#endif

    func tokenStatus(serverURL: URL, forceRefresh: Bool) async throws -> AuthenticationTokenStatus {
        guard let token = try await fetchTokenFromStore(serverURL: serverURL) else {
            return .absent
        }

        switch token {
        case .project:
            return .valid(token)
        case let .user(
            accessToken: accessToken, refreshToken: refreshToken
        ):
            // We consider a token to be expired if the expiration date is in the past or 30 seconds from now
            let now = Date.now()
            let expiresIn = accessToken.expiryDate
                .timeIntervalSince(now)
            let refresh = expiresIn < 30 || forceRefresh
            if refresh { return .expired }
            return .valid(.user(
                accessToken: accessToken,
                refreshToken: refreshToken
            ))
        }
    }

    func executeRefresh(serverURL: URL, forceRefresh: Bool) async throws -> (value: AuthenticationToken, expiresAt: Date?)? {
        guard let token = try await fetchTokenFromStore(serverURL: serverURL) else {
            return nil
        }

        let upToDateToken: AuthenticationToken
        var expiresAt: Date?

        switch token {
        case .project:
            upToDateToken = token
        case let .user(
            accessToken: accessToken, refreshToken: refreshToken
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

    #if canImport(TuistSupport)
    public func lockFilePath(serverURL: URL) -> AbsolutePath {
        let key = "token_\(serverURL.absoluteString)"
        // Use a sanitized version of the key for the filename
        let sanitizedKey = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        return Environment.current.stateDirectory
            .appending(component: "auth-locks")
            .appending(component: "\(sanitizedKey).lock")
    }
    #endif

    private func fetchTokenFromStore(serverURL: URL) async throws -> AuthenticationToken? {
        let credentials: ServerCredentials? = try await ServerCredentialsStore.current.read(
            serverURL: serverURL
        )
        return try credentials.map {
            return .user(
                accessToken: try JWT.parse($0.accessToken),
                refreshToken: try JWT.parse($0.refreshToken)
            )
        }
    }

    private func ciAuthenticationToken() async throws -> AuthenticationToken? {
        #if canImport(TuistSupport)
            if let configToken = Environment.current.tuistVariables[
                Constants.EnvironmentVariables.token
            ] {
                return .project(configToken)
            } else if let deprecatedToken = Environment.current.tuistVariables[
                "TUIST_CONFIG_CLOUD_TOKEN"
            ] {
                AlertController.current
                    .warning(
                        .alert(
                            "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
                        )
                    )
                return .project(deprecatedToken)
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
                throw ServerClientAuthenticationError.notAuthenticated
            }
        } catch {
            throw ServerClientAuthenticationError.notAuthenticated
        }
    }
}
