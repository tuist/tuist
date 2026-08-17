import OpenAPIRuntime
import SwiftUI
import TuistHTTP
import TuistLogging
import TuistServer
import UIKit

struct ErrorAlert: Identifiable {
    var id = UUID()
    var message: String
    var logReport: String?
    var dismissAction: (() -> Void)?
}

public final class ErrorHandling: ObservableObject {
    @Published var currentAlert: ErrorAlert?

    @MainActor
    public func handle(error: Error) {
        if let clientError = error as? ClientError {
            let recordingTask = recordRequestFailure(
                error: clientError,
                underlyingError: clientError.underlyingError
            )
            if clientError.underlyingError is ClientAuthenticationError {
                Logger.current.error(
                    "Client authentication error received. Deleting stored credentials. Error: \(clientError.underlyingError.localizedDescription)"
                )
                showAlert(
                    message: clientError.underlyingError.localizedDescription,
                    withLogReport: true,
                    after: recordingTask
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
            let recordingTask = recordRequestFailure(error: error)
            Logger.current.error("Error received: \(error.localizedDescription)")
            showAlert(
                message: error.localizedDescription,
                withLogReport: error is ClientAuthenticationError,
                after: recordingTask
            )
        }
    }

    @MainActor
    private func showAlert(
        message: String,
        withLogReport: Bool,
        after recordingTask: Task<Void, Never>
    ) {
        guard withLogReport else {
            currentAlert = ErrorAlert(message: message)
            return
        }

        Task {
            await recordingTask.value
            let logReport = await ApplicationLogStore.shared.currentProcessReport()
            currentAlert = ErrorAlert(message: message, logReport: logReport)
        }
    }

    private func recordRequestFailure(
        error: Error,
        underlyingError: Error? = nil
    ) -> Task<Void, Never> {
        ApplicationLogStore.shared.record(
            level: .error,
            category: "request",
            message: "request_failed error_type=\(String(reflecting: type(of: error))) "
                + "underlying_error_type=\(underlyingError.map { String(reflecting: type(of: $0)) } ?? "none")"
        )
    }
}

struct HandleErrorsByShowingAlertViewModifier: ViewModifier {
    @StateObject var errorHandling = ErrorHandling()
    @State private var logsToShare: LogsToShare?

    func body(content: Content) -> some View {
        content
            .environmentObject(errorHandling)
            // Applying the alert for error handling using a background element
            // is a workaround, if the alert would be applied directly,
            // other .alert modifiers inside of content would not work anymore
            .background(
                EmptyView()
                    .alert(item: $errorHandling.currentAlert) { currentAlert in
                        if let logReport = currentAlert.logReport {
                            return Alert(
                                title: Text("Error"),
                                message: Text(currentAlert.message),
                                primaryButton: .default(Text("Share logs")) {
                                    currentAlert.dismissAction?()
                                    logsToShare = LogsToShare(report: logReport)
                                },
                                secondaryButton: .cancel(Text("Ok")) {
                                    currentAlert.dismissAction?()
                                }
                            )
                        } else {
                            return Alert(
                                title: Text("Error"),
                                message: Text(currentAlert.message),
                                dismissButton: .default(Text("Ok")) {
                                    currentAlert.dismissAction?()
                                }
                            )
                        }
                    }
            )
            .sheet(item: $logsToShare) { logsToShare in
                ActivityView(activityItems: [logsToShare.report])
            }
    }
}

private struct LogsToShare: Identifiable {
    let id = UUID()
    let report: String
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
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
