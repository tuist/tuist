import Foundation
import Mockable
import TuistServer
import TuistSupport

@Mockable
protocol AppCredentialsServicing: ObservableObject {
    var authenticationState: AuthenticationState { get }
    var accountHandle: String? { get }

    func loadCredentials()
    func login() async throws
    func logout() async throws
    func updateAuthenticationState() async throws
}

final class AppCredentialsService: AppCredentialsServicing {
    @Published
    private(set) var authenticationState: AuthenticationState = .loggedOut

    var accountHandle: String? {
        switch authenticationState {
        case let .loggedIn(accountHandle):
            accountHandle
        case .loggedOut:
            nil
        }
    }

    private let appStorage: AppStoring
    private let serverSessionController: ServerSessionControlling
    private let serverURLService: ServerURLServicing

    init(
        appStorage: AppStoring = AppStorage(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverURLService: ServerURLServicing = ServerURLService()
    ) {
        self.appStorage = appStorage
        self.serverSessionController = serverSessionController
        self.serverURLService = serverURLService
    }

    func loadCredentials() {
        authenticationState = (try? appStorage.get(AuthenticationStateKey.self)) ?? .loggedOut
    }

    func login() async throws {
        let serverSessionController = serverSessionController
        let serverURL = serverURLService.serverURL()
        try await withTimeout(
            .seconds(2 * 60),
            onTimeout: {
                logger.warning("Login timed out")
            }
        ) {
            try await serverSessionController.authenticate(
                serverURL: serverURL,
                deviceCodeType: .app,
                onOpeningBrowser: { _ in },
                onAuthWaitBegin: {}
            )
        }
        try await updateAuthenticationState()
    }

    func logout() async throws {
        try await serverSessionController.logout(serverURL: serverURLService.serverURL())
        try await updateAuthenticationState()
    }

    @MainActor
    func updateAuthenticationState() async throws {
        if let accountHandle = try await serverSessionController.whoami(serverURL: serverURLService.serverURL()) {
            authenticationState = .loggedIn(accountHandle: accountHandle)
        } else {
            authenticationState = .loggedOut
        }
        try? appStorage.set(AuthenticationStateKey.self, value: authenticationState)
    }
}
