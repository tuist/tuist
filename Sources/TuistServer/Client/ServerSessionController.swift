import Foundation
import Mockable

#if canImport(TuistSupport)
    import TuistSupport
#endif

/// Type of device code used for authentication.
public enum DeviceCodeType {
    case cli
    case app

    var apiValue: String {
        switch self {
        case .app:
            "app"
        case .cli:
            "cli"
        }
    }
}

public enum ServerSessionControllerError: Equatable, LocalizedError {
    case unauthenticated

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            "You are not logged in. Run 'tuist auth login'."
        }
    }
}

@Mockable
public protocol ServerSessionControlling: AnyObject {
    /// It authenticates the user for the server with the given URL.
    /// - Parameters:
    ///     - serverURL: Server URL.
    ///     - deviceCodeType: Type of device origin used for authentication.
    ///     - onOpeningBrowser: Triggered when we begin opening the browser at the given authentication url.
    ///     - onAuthWaitBegin: Custom callback when we started waiting for the authentication to finish in the browser.
    func authenticate(
        serverURL: URL,
        deviceCodeType: DeviceCodeType,
        onOpeningBrowser: @escaping (URL) async -> Void,
        onAuthWaitBegin: @escaping () async -> Void
    ) async throws

    /// - Returns: Account handle for the signed-in user for the server with the given URL. Returns nil if no user is logged in.
    func whoami(serverURL: URL) async throws -> String?

    /// - Returns: Account handle for the signed-in user for the server with the given URL. Throws if no user is logged in.
    func authenticatedHandle(serverURL: URL) async throws -> String

    /// Removes the session for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func logout(serverURL: URL) async throws
}

public final class ServerSessionController: ServerSessionControlling {
    static let port: UInt16 = 4545

    private let credentialsStore: ServerCredentialsStoring
    private let getAuthTokenService: GetAuthTokenServicing
    private let serverAuthenticationController: ServerAuthenticationControlling

    #if canImport(TuistSupport)
        private let opener: Opening
        private let uniqueIDGenerator: UniqueIDGenerating

        public convenience init() {
            let credentialsStore = ServerCredentialsStore()
            self.init(
                credentialsStore: credentialsStore,
                opener: Opener(),
                getAuthTokenService: GetAuthTokenService(),
                uniqueIDGenerator: UniqueIDGenerator(),
                serverAuthenticationController: ServerAuthenticationController(
                    credentialsStore: credentialsStore
                )
            )
        }

        init(
            credentialsStore: ServerCredentialsStoring,
            opener: Opening,
            getAuthTokenService: GetAuthTokenServicing,
            uniqueIDGenerator: UniqueIDGenerating,
            serverAuthenticationController: ServerAuthenticationControlling
        ) {
            self.credentialsStore = credentialsStore
            self.opener = opener
            self.getAuthTokenService = getAuthTokenService
            self.uniqueIDGenerator = uniqueIDGenerator
            self.serverAuthenticationController = serverAuthenticationController
        }
    #else
        public init() {
            credentialsStore = ServerCredentialsStore()
            getAuthTokenService = GetAuthTokenService()
            serverAuthenticationController = ServerAuthenticationController()
        }
    #endif

    // MARK: - ServerSessionControlling

    #if canImport(TuistSupport)
        public func authenticate(
            serverURL: URL,
            deviceCodeType: DeviceCodeType,
            onOpeningBrowser: @escaping (URL) async -> Void,
            onAuthWaitBegin: () async -> Void
        ) async throws {
            var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
            let deviceCode = uniqueIDGenerator.uniqueID()
            components.path = "/auth/device_codes/\(deviceCode)"
            components.queryItems = [
                URLQueryItem(
                    name: "type",
                    value: deviceCodeType.apiValue
                ),
            ]
            let authURL = components.url!

            await onOpeningBrowser(authURL)

            try opener.open(url: authURL)

            await onAuthWaitBegin()

            let tokens = try await getAuthTokens(
                serverURL: serverURL,
                deviceCode: deviceCode
            )
            let credentials = ServerCredentials(
                token: nil,
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken
            )
            try await credentialsStore.store(credentials: credentials, serverURL: serverURL)
        }
    #else
        public func authenticate(
            serverURL _: URL,
            deviceCodeType _: DeviceCodeType,
            onOpeningBrowser _: @escaping (URL) async -> Void,
            onAuthWaitBegin _: @escaping () async -> Void
        ) async throws {}
    #endif

    public func whoami(serverURL: URL) async throws -> String? {
        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: serverURL
        )
        else { return nil }
        switch token {
        case let .user(legacyToken: _, accessToken: accessToken, refreshToken: _):
            return accessToken?.preferredUsername
        case .project:
            return nil
        }
    }

    public func authenticatedHandle(serverURL: URL) async throws -> String {
        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: serverURL
        )
        else {
            throw ServerSessionControllerError.unauthenticated
        }
        switch token {
        case let .user(legacyToken: _, accessToken: accessToken, refreshToken: _):
            guard let username = accessToken?.preferredUsername else {
                throw ServerSessionControllerError.unauthenticated
            }
            return username
        case .project:
            throw ServerSessionControllerError.unauthenticated
        }
    }

    public func logout(serverURL: URL) async throws {
        try await credentialsStore.delete(serverURL: serverURL)
        #if canImport(TuistSupport)
            AlertController.current.success(.alert("Successfully logged out."))
        #endif
    }

    private func getAuthTokens(
        serverURL: URL,
        deviceCode: String
    ) async throws -> ServerAuthenticationTokens {
        if let token = try await getAuthTokenService.getAuthToken(
            serverURL: serverURL,
            deviceCode: deviceCode
        ) {
            return token
        } else {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await getAuthTokens(serverURL: serverURL, deviceCode: deviceCode)
        }
    }
}
