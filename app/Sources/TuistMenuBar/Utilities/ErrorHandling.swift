import AppKit
import Foundation
import OpenAPIRuntime
import TuistAuthentication
import TuistHTTP
import TuistLogging
import TuistServer
import TuistSupport

final class ErrorHandling: ObservableObject, Sendable {
    private let credentialsStore: ServerCredentialsStoring

    init(credentialsStore: ServerCredentialsStoring = ServerCredentialsStore.current) {
        self.credentialsStore = credentialsStore
    }

    func handle(error: Error, serverURL: URL? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            if let error = error as? FatalError {
                alert.messageText = error.description
            } else if error is ClientAuthenticationError {
                // When we fail to authenticate, we sign out the user and force them to sign in again.
                guard let serverURL else {
                    alert.messageText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                    return
                }
                Task {
                    try await self.credentialsStore.delete(serverURL: serverURL)
                }
                return
            } else if let error = error as? ClientError {
                self.handle(error: error.underlyingError, serverURL: serverURL)
                return
            } else {
                alert.messageText = error.localizedDescription
            }
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

extension ErrorHandling {
    func fireAndHandleError(_ action: @escaping () async throws -> Void) {
        let serverURL = AppServerEnvironmentService().url()
        Task {
            do {
                try await ServerCredentialsStore.$current.withValue(credentialsStore) {
                    try await action()
                }
            } catch {
                handle(error: error, serverURL: serverURL)
            }
        }
    }
}
