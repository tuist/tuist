import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol CloudAuthenticationControlling {
    func authenticationToken(serverURL: URL) throws -> CloudAuthenticationToken?
}

public enum CloudAuthenticationToken: CustomStringConvertible {
    /// The token represents a user session. User sessions are typically used in
    /// local environments where the user can be guided through an interactive
    /// authentication workflow
    case user(String)

    /// The token represents a project session. Project sessions are typically used
    /// in CI environments where limited scopes are desired for security reasons.
    case project(String)

    /// It returns the value of the token
    public var value: String {
        switch self {
        case let .user(token):
            return token
        case let .project(token):
            return token
        }
    }

    public var description: String {
        switch self {
        case let .user(token):
            return "tuist cloud user token: \(token)"
        case let .project(token):
            return "tuist cloud project token: \(token)"
        }
    }
}

public final class CloudAuthenticationController: CloudAuthenticationControlling {
    private let credentialsStore: CloudCredentialsStoring
    private let ciChecker: CIChecking
    private let environmentVariables: () -> [String: String]

    public init(
        credentialsStore: CloudCredentialsStoring = CloudCredentialsStore(),
        ciChecker: CIChecking = CIChecker(),
        environmentVariables: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.credentialsStore = credentialsStore
        self.ciChecker = ciChecker
        self.environmentVariables = environmentVariables
    }

    public func authenticationToken(serverURL: URL) throws -> CloudAuthenticationToken? {
        if ciChecker.isCI() {
            let environment = environmentVariables()
            return environment[Constants.EnvironmentVariables.token].map { .project($0) }
        } else {
            return (try credentialsStore.read(serverURL: serverURL)?.token).map { .user($0) }
        }
    }
}
