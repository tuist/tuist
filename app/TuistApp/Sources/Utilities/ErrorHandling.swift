import AppKit
import Foundation
import TuistSupport

final class ErrorHandling: ObservableObject, Sendable {
    func handle(error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            if let error = error as? FatalError {
                alert.messageText = error.description
            } else {
                alert.messageText = error.localizedDescription
            }
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
