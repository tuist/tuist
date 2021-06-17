import Foundation
import TuistSupport

public enum LabSessionControllerError: FatalError, Equatable {
    case missingParameters
    case authenticationError(String)
    case invalidParameters([String])

    /// Error description.
    public var description: String {
        switch self {
        case let .authenticationError(error):
            return error
        case .missingParameters:
            return "The result from the authentication contains no parameters. We expect an account and token."
        case let .invalidParameters(parameters):
            return "The result from the authentication contains invalid parameters: \(parameters.joined(separator: ", ")). We expect an account and token."
        }
    }

    /// Error type.
    public var type: ErrorType {
        switch self {
        case .authenticationError: return .abort
        case .invalidParameters: return .abort
        case .missingParameters: return .abort
        }
    }
}

public protocol LabSessionControlling: AnyObject {
    /// It authenticates the user for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func authenticate(serverURL: URL) throws

    /// Prints the session for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func printSession(serverURL: URL) throws

    /// Removes the session for the server with the given URL.
    /// - Parameter serverURL: Server URL.
    func logout(serverURL: URL) throws
}

public final class LabSessionController: LabSessionControlling {
    static let port: UInt16 = 4545

    /// Credentials store.
    private let credentialsStore: CredentialsStoring

    /// HTTP redirect listener.
    private let httpRedirectListener: HTTPRedirectListening

    /// Utility to check whether we are running Tuist on CI.
    let ciChecker: CIChecking

    /// Utility to send the user to a web page to authenticate.
    let opener: Opening

    public convenience init() {
        self.init(
            credentialsStore: CredentialsStore(),
            httpRedirectListener: HTTPRedirectListener(),
            ciChecker: CIChecker(),
            opener: Opener()
        )
    }

    init(credentialsStore: CredentialsStoring,
         httpRedirectListener: HTTPRedirectListening,
         ciChecker: CIChecking,
         opener: Opening)
    {
        self.credentialsStore = credentialsStore
        self.httpRedirectListener = httpRedirectListener
        self.ciChecker = ciChecker
        self.opener = opener
    }

    // MARK: - LabSessionControlling

    public func authenticate(serverURL: URL) throws {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/auth"
        components.queryItems = nil
        let authURL = components.url!

        logger.notice("Opening \(authURL.absoluteString) to start the authentication flow")
        try opener.open(url: authURL)

        let logoURL = serverURL.appendingPathComponent("redirect-logo.svg")
        let redirectMessage = "Switch back to your terminal to continue the authentication."
        let result = httpRedirectListener.listen(
            port: LabSessionController.port,
            path: "auth",
            redirectMessage: redirectMessage,
            logoURL: logoURL
        )
        switch result {
        case let .failure(error): throw error
        case let .success(parameters):
            guard let parameters = parameters else {
                throw LabSessionControllerError.missingParameters
            }
            if let error = parameters["error"] {
                throw LabSessionControllerError.authenticationError(error)
            } else if let token = parameters["token"], let account = parameters["account"] {
                logger.notice("Successfully authenticated. Storing credentials...")
                let credentials = Credentials(token: token, account: account)
                try credentialsStore.store(credentials: credentials, serverURL: serverURL)
                logger.notice("Credentials stored successfully", metadata: .success)
            } else {
                throw LabSessionControllerError.invalidParameters(Array(parameters.keys))
            }
        }
    }

    public func printSession(serverURL: URL) throws {
        if let credentials = try credentialsStore.read(serverURL: serverURL) {
            let output = """
            These are the credentials for the server with URL \(serverURL.absoluteString):
            - Account: \(credentials.account)
            - Token: \(credentials.token)
            """
            logger.notice("\(output)")
        } else {
            logger.notice("There are no sessions for the server with URL \(serverURL.absoluteString)")
        }
    }

    public func logout(serverURL: URL) throws {
        logger.notice("Removing session for server with URL \(serverURL.absoluteString)")
        try credentialsStore.delete(serverURL: serverURL)
        logger.notice("Session deleted successfully", metadata: .success)
    }
}
