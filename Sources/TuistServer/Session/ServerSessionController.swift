import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol ServerSessionControlling: AnyObject {
    /// It authenticates the user for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func authenticate(serverURL: URL) async throws

    /// Prints the session for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func printSession(serverURL: URL) throws

    /// Removes the session for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func logout(serverURL: URL) async throws
}

public final class ServerSessionController: ServerSessionControlling {
    static let port: UInt16 = 4545

    private let credentialsStore: ServerCredentialsStoring
    private let ciChecker: CIChecking
    private let opener: Opening
    private let getAuthTokenService: GetAuthTokenServicing
    private let uniqueIDGenerator: UniqueIDGenerating
    private let serverAuthenticationController: ServerAuthenticationControlling

    public convenience init() {
        let credentialsStore = ServerCredentialsStore()
        self.init(
            credentialsStore: credentialsStore,
            ciChecker: CIChecker(),
            opener: Opener(),
            getAuthTokenService: GetAuthTokenService(),
            uniqueIDGenerator: UniqueIDGenerator(),
            serverAuthenticationController: ServerAuthenticationController(credentialsStore: credentialsStore)
        )
    }

    init(
        credentialsStore: ServerCredentialsStoring,
        ciChecker: CIChecking,
        opener: Opening,
        getAuthTokenService: GetAuthTokenServicing,
        uniqueIDGenerator: UniqueIDGenerating,
        serverAuthenticationController: ServerAuthenticationControlling
    ) {
        self.credentialsStore = credentialsStore
        self.ciChecker = ciChecker
        self.opener = opener
        self.getAuthTokenService = getAuthTokenService
        self.uniqueIDGenerator = uniqueIDGenerator
        self.serverAuthenticationController = serverAuthenticationController
    }

    // MARK: - ServerSessionControlling

    public func authenticate(serverURL: URL) async throws {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        let deviceCode = uniqueIDGenerator.uniqueID()
        components.path = "/auth/cli/\(deviceCode)"
        components.queryItems = nil
        let authURL = components.url!

        logger.notice("Opening \(authURL.absoluteString) to start the authentication flow")
        try opener.open(url: authURL)

        if Environment.shared.shouldOutputBeColoured {
            logger.notice("Press \("CTRL + C".cyan()) once to cancel the process.", metadata: .pretty)
        } else {
            logger.notice("Press CTRL + C once to cancel the process.")
        }

        let tokens = try await getAuthTokens(
            serverURL: serverURL,
            deviceCode: deviceCode
        )
        let credentials = ServerCredentials(
            token: nil,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken
        )
        try credentialsStore.store(credentials: credentials, serverURL: serverURL)
        logger.notice("Credentials stored successfully", metadata: .success)
    }

    public func printSession(serverURL: URL) throws {
        if let token = try serverAuthenticationController.authenticationToken(serverURL: serverURL) {
            switch token {
            case let .user(legacyToken: legacyToken, accessToken: accessToken, refreshToken: _):
                logger.notice("""
                Requests against \(serverURL.absoluteString) will be authenticated as a user using the following token:
                \(accessToken?.token ?? legacyToken!)
                """)
            case let .project(projectToken):
                logger.notice("""
                Requests against \(serverURL.absoluteString) will be authenticated as a project using the following token:
                \(projectToken)
                """)
            }
        } else {
            logger.notice("There are no sessions for the server with URL \(serverURL.absoluteString)")
        }
    }

    public func logout(serverURL: URL) async throws {
        logger.notice("Removing session for server with URL \(serverURL.absoluteString)")
        try await credentialsStore.delete(serverURL: serverURL)
        logger.notice("Session deleted successfully", metadata: .success)
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
