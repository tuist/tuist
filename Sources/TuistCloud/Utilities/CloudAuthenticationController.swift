import Foundation
import TuistSupport

public protocol CloudAuthenticationControlling {
    func authenticationToken(serverURL: URL) throws -> String?
}

public final class CloudAuthenticationController: CloudAuthenticationControlling {
    private let credentialsStore: CredentialsStoring
    private let ciChecker: CIChecking
    private let environmentVariables: () -> [String: String]

    public init(
        credentialsStore: CredentialsStoring = CredentialsStore(),
        ciChecker: CIChecking = CIChecker(),
        environmentVariables: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.credentialsStore = credentialsStore
        self.ciChecker = ciChecker
        self.environmentVariables = environmentVariables
    }

    public func authenticationToken(serverURL: URL) throws -> String? {
        let environment = environmentVariables()
        let tokenFromEnvironment = environment[Constants.EnvironmentVariables.cloudToken]
        if ciChecker.isCI() {
            return tokenFromEnvironment
        } else {
            return try tokenFromEnvironment ?? credentialsStore.read(serverURL: serverURL)?.token
        }
    }
}
