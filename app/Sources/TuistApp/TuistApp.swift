import SwiftUI
import TuistAuthentication
import TuistServer

#if os(macOS)
    import Sparkle
    import TuistMenuBar

    @main
    struct TuistApp: App {
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

        private let updaterController: SPUStandardUpdaterController

        init() {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        var body: some Scene {
            MenuBarExtra("Tuist", image: "MenuBarIcon") {
                ServerCredentialsStore.$current.withValue(ServerCredentialsStore(backend: .keychain)) {
                    CachedValueStore.$current.withValue(CachedValueStore(backend: .inSystemProcess)) {
                        MenuBarView(
                            appDelegate: appDelegate,
                            updaterController: updaterController
                        )
                    }
                }
            }
            .menuBarExtraStyle(.window)
        }
    }
#else
    import TuistErrorHandling
    import TuistOnboarding
    import TuistPreviews

    @main
    struct TuistApp: App {
        @StateObject private var authenticationService = AuthenticationService()

        var body: some Scene {
            WindowGroup {
                ServerCredentialsStore.$current.withValue(ServerCredentialsStore(backend: .keychain)) {
                    CachedValueStore.$current.withValue(CachedValueStore(backend: .inSystemProcess)) {
                        Group {
                            if case .loggedIn = authenticationService.authenticationState {
                                NavigationView {
                                    PreviewsView()
                                        .navigationBarItems(
                                            trailing:
                                            Button("Log Out") {
                                                Task {
                                                    await authenticationService.signOut()
                                                }
                                            }
                                        )
                                }
                            } else {
                                LogInView()
                            }
                        }
                        .withErrorHandling()
                    }
                }
            }
        }
    }
#endif
