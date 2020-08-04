import Foundation
import TuistSupport

/// Protocol that defines the interface to map HTTP requests and include authentication information.
/// Depending on th environment where Tuist is running (local or CI), it returns the token from the credentials store (i.e. Keychain)
/// or a environment variable.
public protocol ScaleHTTPRequestAuthenticating {
    /// Given a request, it returns a copy of it including information to authenticate requests to the scale.
    /// - Parameter request: Request to authenticate.
    /// - Returns: Mapped request.
    func authenticate(request: URLRequest) throws -> URLRequest
}

public final class ScaleHTTPRequestAuthenticator: ScaleHTTPRequestAuthenticating {
    /// Utility to check whether we are running Tuist on CI.
    let ciChecker: CIChecking

    /// Environment variables.
    let environmentVariables: () -> [String: String]

    /// Store where the credentials are stored.
    let credentialsStore: CredentialsStoring

    public convenience init() {
        self.init(ciChecker: CIChecker(),
                  environmentVariables: { ProcessInfo.processInfo.environment },
                  credentialsStore: CredentialsStore())
    }

    init(ciChecker: CIChecking,
         environmentVariables: @escaping () -> [String: String],
         credentialsStore: CredentialsStoring)
    {
        self.ciChecker = ciChecker
        self.environmentVariables = environmentVariables
        self.credentialsStore = credentialsStore
    }

    // MARK: - ScaleHTTPRequestAuthenticating

    public func authenticate(request: URLRequest) throws -> URLRequest {
        var urlComponents = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        urlComponents.path = ""
        urlComponents.queryItems = nil
        let serverURL = urlComponents.url!

        let token: String?
        if ciChecker.isCI() {
            token = environmentVariables()[Constants.EnvironmentVariables.scaleToken]
        } else {
            token = try credentialsStore.read(serverURL: serverURL)?.token
        }

        var request = request
        if request.allHTTPHeaderFields == nil {
            request.allHTTPHeaderFields = [:]
        }
        if let token = token {
            request.allHTTPHeaderFields?["Authorization"] = "Bearer \(token)"
        }

        return request
    }
}
