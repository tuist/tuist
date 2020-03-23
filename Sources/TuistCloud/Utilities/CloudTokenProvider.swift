import Foundation
import TuistSupport

/// Protocol that defines the interface to get the token that should be used to authenticate requests.
/// Depending on th environment where Tuist is running (local or CI), it returns the token from the credentials store (i.e. Keychain)
/// or a environment variable.
public protocol CloudTokenProviding {
    /// Returns the token that should be used to authenticate cloud operations.
    /// If it's running locally, it returns the user's token, otherwise, it reads the token
    /// from a environment variable.
    /// - Parameter serverURL: The URL that we are authenticating against (without the path).
    func read(serverURL: URL) throws -> String?
}

public final class CloudTokenProvider: CloudTokenProviding {
    /// Utility to check whether we are running Tuist on CI.
    let ciChecker: CIChecking

    /// Environment variables.
    let environmentVariables: () -> [String: String]

    /// Store where the credentials are stored.
    let credentialsStore: CredentialsStoring

    public convenience init() {
        self.init(ciChecker: CIChecker(),
                  environmentVariables: ProcessInfo.processInfo.environment,
                  credentialsStore: CredentialsStore())
    }

    init(ciChecker: CIChecking,
         environmentVariables: @escaping @autoclosure () -> [String: String],
         credentialsStore: CredentialsStoring) {
        self.ciChecker = ciChecker
        self.environmentVariables = environmentVariables
        self.credentialsStore = credentialsStore
    }

    // MARK: - CloudTokenProviding

    public func read(serverURL: URL) throws -> String? {
        if ciChecker.isCI() {
            return environmentVariables()[Constants.EnvironmentVariables.cloudToken]
        } else {
            return try credentialsStore.read(serverURL: serverURL)?.token
        }
    }
}
