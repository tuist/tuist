import Combine
import Foundation
import TuistServer
import TuistSupport

@Observable
final class MenuBarViewModel: ObservableObject {
    private(set) var canCheckForUpdates: Bool = false
    private(set) var authenticationState: AuthenticationState = .loggedOut
    var accountHandle: String? {
        switch authenticationState {
        case let .loggedIn(accountHandle):
            accountHandle
        case .loggedOut:
            nil
        }
    }

    private let serverURLService: ServerURLServicing
    private let serverSessionController: ServerSessionControlling
    private let appStorage: AppStoring
    private var cancellables = Set<AnyCancellable>()

    init(
        serverURLService: ServerURLServicing = ServerURLService(),
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.serverURLService = serverURLService
        self.serverSessionController = serverSessionController
        self.appStorage = appStorage
    }

    func canCheckForUpdatesValueChanged(_ newValue: Bool) {
        canCheckForUpdates = newValue
    }

    func loadInitialData() {
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

    func updateAuthenticationState() async throws {
        if let accountHandle = try await serverSessionController.whoami(serverURL: serverURLService.serverURL()) {
            authenticationState = .loggedIn(accountHandle: accountHandle)
        } else {
            authenticationState = .loggedOut
        }
        try? appStorage.set(AuthenticationStateKey.self, value: authenticationState)
    }
}
