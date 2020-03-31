import Foundation
import TuistSupport

public final class CloudSessionController {
    /// Credentials store.
    private let credentialsStore: CredentialsStoring

    /// HTTP redirect listener.
    private let httpRedirectListener: HTTPRedirectListening

    /// Utility to check whether we are running Tuist on CI.
    let ciChecker: CIChecking

    public convenience init() {
        self.init(credentialsStore: CredentialsStore(),
                  httpRedirectListener: HTTPRedirectListener(),
                  ciChecker: CIChecker())
    }

    init(credentialsStore: CredentialsStoring,
         httpRedirectListener: HTTPRedirectListening,
         ciChecker: CIChecking) {
        self.credentialsStore = credentialsStore
        self.httpRedirectListener = httpRedirectListener
        self.ciChecker = ciChecker
    }

    // MARK: - CloudSessionControlling

    public func authenticate() throws {}

    public func session() throws {}

    public func logout() throws {}
}
