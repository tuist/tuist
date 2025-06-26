import SwiftUI

#if canImport(TuistMenuBar)
    import Sparkle
    import TuistMenuBar

    @main
    struct TuistApp: App {
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

        private let updaterController: SPUStandardUpdaterController
        private let appCredentialsService = AppCredentialsService()

        init() {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        var body: some Scene {
            MenuBarExtra("Tuist", image: "MenuBarIcon") {
                MenuBarView(
                    appDelegate: appDelegate,
                    updaterController: updaterController
                )
                .environmentObject(appCredentialsService)
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
                Group {
                    if authenticationService.isAuthenticated {
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
                .onAppear {
                    Task {
                        await authenticationService.loadCredentials()
                    }
                }
            }
        }
    }
#endif
