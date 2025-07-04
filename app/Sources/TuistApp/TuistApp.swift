import SwiftUI
import TuistAuthentication
import TuistNoora
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
                ServerCredentialsStore.$current.withValue(
                    ServerCredentialsStore(backend: .keychain)
                ) {
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
                ServerCredentialsStore.$current.withValue(
                    ServerCredentialsStore(backend: .keychain)
                ) {
                    CachedValueStore.$current.withValue(CachedValueStore(backend: .inSystemProcess)) {
                        Group {
                            if case .loggedIn = authenticationService.authenticationState {
                                TabView {
                                    NavigationView {
                                        PreviewsView()
                                    }
                                    .tabItem {
                                        Image(systemName: "iphone")
                                            .font(.system(size: 24))
                                        Text("Previews")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .tag(0)

                                    ProfileView()
                                        .environmentObject(authenticationService)
                                        .tabItem {
                                            Image(systemName: "person.crop.circle")
                                                .font(.system(size: 24))
                                            Text("Profile")
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .tag(1)
                                }
                                .accentColor(Noora.Colors.purple500)
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
