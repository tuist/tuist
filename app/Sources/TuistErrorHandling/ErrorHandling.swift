import OpenAPIRuntime
import SwiftUI
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

    @MainActor
    public func handle(error: Error) {
        if let clientError = error as? ClientError {
            if clientError.underlyingError is ClientAuthenticationError {
                Logger.current.error(
                    "Client authentication error received. Deleting stored credentials. Error: \(clientError.underlyingError.localizedDescription)"
                )
                Task {
                    try await ServerCredentialsStore.current.delete(
                        serverURL: ServerEnvironmentService().url()
                    )
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
    @StateObject var errorHandling = ErrorHandling()

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
    public func withErrorHandling() -> some View {
        modifier(HandleErrorsByShowingAlertViewModifier())
    }
}

extension ErrorHandling {
    public func fireAndHandleError(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                await handle(error: error)
            }
        }
    }
}
