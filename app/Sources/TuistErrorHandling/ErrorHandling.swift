import Foundation
import OpenAPIRuntime
import SwiftUI
import TuistHTTP
import TuistLogging
import TuistServer
import UIKit

struct ErrorAlert: Identifiable {
    var id = UUID()
    var message: String
    var logExportURL: URL?
    var dismissAction: (() -> Void)?
}

public final class ErrorHandling: ObservableObject {
    @Published var currentAlert: ErrorAlert?

    @MainActor
    public func handle(error: Error) {
        if let clientError = error as? ClientError {
            if clientError.underlyingError is ClientAuthenticationError {
                let clientErrorType = String(reflecting: type(of: clientError))
                let underlyingErrorType = String(reflecting: type(of: clientError.underlyingError))
                Logger.current.error(
                    "Client authentication error received. Deleting stored credentials. error_type=\(clientErrorType) underlying_error_type=\(underlyingErrorType) error=\(clientError.underlyingError.localizedDescription)"
                )
                showAlert(
                    message: clientError.underlyingError.localizedDescription,
                    withLogExport: true
                )
                Task {
                    try await ServerCredentialsStore.current.delete(
                        serverURL: ServerEnvironmentService().url()
                    )
                }
                return
            }
            let clientErrorType = String(reflecting: type(of: clientError))
            let underlyingErrorType = String(reflecting: type(of: clientError.underlyingError))
            Logger.current.error(
                "Client error received error_type=\(clientErrorType) underlying_error_type=\(underlyingErrorType) error=\(clientError.underlyingError.localizedDescription)"
            )
            currentAlert = ErrorAlert(message: clientError.underlyingError.localizedDescription)
            return
        } else {
            let errorType = String(reflecting: type(of: error))
            Logger.current.error(
                "Error received error_type=\(errorType) error=\(error.localizedDescription)"
            )
            showAlert(
                message: error.localizedDescription,
                withLogExport: error is ClientAuthenticationError
            )
        }
    }

    @MainActor
    private func showAlert(
        message: String,
        withLogExport: Bool
    ) {
        guard withLogExport else {
            currentAlert = ErrorAlert(message: message)
            return
        }

        Task {
            do {
                let logExportURL = try await ApplicationLogStore.plainTextExport()
                currentAlert = ErrorAlert(message: message, logExportURL: logExportURL)
            } catch {
                Logger.current.error("Failed to prepare application logs for sharing: \(error.localizedDescription)")
                currentAlert = ErrorAlert(message: message)
            }
        }
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
                        if let logExportURL = currentAlert.logExportURL {
                            return Alert(
                                title: Text("Error"),
                                message: Text(currentAlert.message),
                                primaryButton: .default(Text("Share logs")) {
                                    currentAlert.dismissAction?()
                                    logsToShare = LogsToShare(fileURL: logExportURL)
                                },
                                secondaryButton: .cancel(Text("Ok")) {
                                    currentAlert.dismissAction?()
                                    try? FileManager.default.removeItem(at: logExportURL)
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
                ActivityView(
                    activityItems: [logsToShare.fileURL],
                    completion: { try? FileManager.default.removeItem(at: logsToShare.fileURL) }
                )
            }
    }
}

private struct LogsToShare: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: () -> Void

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let viewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        viewController.completionWithItemsHandler = { _, _, _, _ in completion() }
        return viewController
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
