import OpenAPIRuntime
import SwiftUI
import TuistAuthentication
import TuistHTTP
import TuistLogging
import TuistServer

struct ErrorAlert: Identifiable {
    var id = UUID()
    var message: String
    var dismissAction: (() -> Void)?
}

public final class ErrorHandling: ObservableObject {
    @Published var currentAlert: ErrorAlert?
    private let credentialsStore: ServerCredentialsStoring

    public init(credentialsStore: ServerCredentialsStoring = ServerCredentialsStore.current) {
        self.credentialsStore = credentialsStore
    }

    @MainActor
    public func handle(error: Error, serverURL: URL? = nil) {
        if let clientError = error as? ClientError {
            if clientError.underlyingError is ClientAuthenticationError {
                guard let serverURL else {
                    Logger.current.error(
                        "Client authentication error received without a server address. Preserving stored credentials."
                    )
                    currentAlert = ErrorAlert(message: clientError.underlyingError.localizedDescription)
                    return
                }
                Logger.current.error(
                    "Client authentication error received. Deleting stored credentials for \(serverURL.absoluteString)."
                )
                Task {
                    try await credentialsStore.delete(serverURL: serverURL)
                }
                return
            }
            Logger.current.error(
                "Client error received: \(clientError.underlyingError.localizedDescription)"
            )
            currentAlert = ErrorAlert(message: clientError.underlyingError.localizedDescription)
            return
        } else {
            Logger.current.error("Error received: \(error.localizedDescription)")
            currentAlert = ErrorAlert(message: error.localizedDescription)
        }
    }
}

struct HandleErrorsByShowingAlertViewModifier: ViewModifier {
    @ObservedObject var errorHandling: ErrorHandling

    func body(content: Content) -> some View {
        content
            .environmentObject(errorHandling)
            // Applying the alert for error handling using a background element
            // is a workaround, if the alert would be applied directly,
            // other .alert modifiers inside of content would not work anymore
            .background(
                EmptyView()
                    .alert(item: $errorHandling.currentAlert) { currentAlert in
                        Alert(
                            title: Text("Error"),
                            message: Text(currentAlert.message),
                            dismissButton: .default(Text("Ok")) {
                                currentAlert.dismissAction?()
                            }
                        )
                    }
            )
    }
}

extension View {
    public func withErrorHandling(_ errorHandling: ErrorHandling = ErrorHandling()) -> some View {
        modifier(HandleErrorsByShowingAlertViewModifier(errorHandling: errorHandling))
    }
}

extension ErrorHandling {
    public func fireAndHandleError(_ action: @escaping () async throws -> Void) {
        let serverURL = AppServerEnvironmentService().url()
        Task {
            do {
                try await ServerCredentialsStore.$current.withValue(credentialsStore) {
                    try await action()
                }
            } catch {
                await handle(error: error, serverURL: serverURL)
            }
        }
    }
}
