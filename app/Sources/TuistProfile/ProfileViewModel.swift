import Foundation
import SwiftUI
import TuistAuthentication
import TuistServer

@Observable
final class ProfileViewModel: Sendable {
    private let deleteAccountService: DeleteAccountServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        deleteAccountService: DeleteAccountServicing = DeleteAccountService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.deleteAccountService = deleteAccountService
        self.serverEnvironmentService = serverEnvironmentService
    }

    func deleteAccount(_ account: Account) async throws {
        try await deleteAccountService.deleteAccount(
            handle: account.handle,
            serverURL: serverEnvironmentService.url()
        )
    }
}
