import AppKit
import Combine
import FluidMenuBarExtra
import Foundation
import TuistAuthentication
import TuistServer

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    public var menuBarExtra: FluidMenuBarExtra?
    public let credentialsStore: ServerCredentialsStoring

    let authenticationService: AuthenticationService
    let errorHandling: ErrorHandling

    let onChangeOfURLs = PassthroughSubject<[URL], Never>()
    private var cancellables = Set<AnyCancellable>()
    private lazy var loginWindowController = LoginWindowController(
        authenticationService: authenticationService,
        errorHandling: errorHandling
    )

    override public init() {
        let credentialsStore = ServerCredentialsStore(backend: .keychain)
        self.credentialsStore = credentialsStore
        authenticationService = AuthenticationService(credentialsStore: credentialsStore)
        errorHandling = ErrorHandling(credentialsStore: credentialsStore)
        super.init()
    }

    public func applicationDidFinishLaunching(_: Notification) {
        authenticationService.$authenticationState
            .sink { [weak self] authenticationState in
                let isLoggedOut = authenticationState == .loggedOut
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if isLoggedOut {
                        presentLoginWindow()
                    } else {
                        loginWindowController.dismiss()
                    }
                }
            }
            .store(in: &cancellables)
    }

    public func application(_: NSApplication, open urls: [URL]) {
        onChangeOfURLs.send(urls)
    }

    func presentLoginWindow() {
        loginWindowController.present()
    }
}
