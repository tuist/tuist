import Foundation
import SwiftUI

protocol ErrorViewHandling: View {
    var errorHandling: ErrorHandling { get }
}

extension ErrorViewHandling {
    func tryWithErrorHandler(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                errorHandling.handle(error: error)
            }
        }
    }

    func tryWithErrorErrorHandler(_ operation: @escaping () throws -> Void) {
        do {
            try operation()
        } catch {
            errorHandling.handle(error: error)
        }
    }
}
