#if os(iOS)
    import Foundation
    import SwiftUI
    import TuistServer

    final class AuthenticationService: ObservableObject {
        @Published public var isAuthenticated = false
        @Published public var isAuthenticating = true

        private let serverCredentialsStore: ServerCredentialsStore
        private let serverEnvironmentService: ServerEnvironmentServicing
        private var credentialsListenerTask: Task<Void, Never>?

        init(
            serverCredentialsStore: ServerCredentialsStore = ServerCredentialsStore(),
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
        ) {
            self.serverCredentialsStore = serverCredentialsStore
            self.serverEnvironmentService = serverEnvironmentService

            startCredentialsListener()
        }

        deinit {
            credentialsListenerTask?.cancel()
        }

        private func startCredentialsListener() {
            credentialsListenerTask = Task {
                for await credentials in ServerCredentialsStore.credentialsChanged {
                    await MainActor.run {
                        isAuthenticated = credentials?.refreshToken != nil
                    }
                }
            }
        }

        @MainActor
        func loadCredentials() async {
            do {
                let credentials = try await serverCredentialsStore.read(serverURL: serverEnvironmentService.url())
                isAuthenticated = credentials?.refreshToken != nil
            } catch {
                isAuthenticated = false
            }
            isAuthenticating = false
        }

        func signOut() async {
            try! await serverCredentialsStore.delete(serverURL: serverEnvironmentService.url())
        }
    }
#endif
