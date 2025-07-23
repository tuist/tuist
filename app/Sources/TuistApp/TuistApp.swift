import SwiftUI
import TuistAuthentication
import TuistServer

#if os(macOS)
    import FluidMenuBarExtra
    import Sparkle
    import TuistMenuBar

    @main
    struct TuistApp: App {
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

        private let updaterController: SPUStandardUpdaterController
        private var menuBarExtra: FluidMenuBarExtra?

        init() {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        var body: some Scene {
            appDelegate.menuBarExtra = FluidMenuBarExtra(title: "Tuist", image: "MenuBarIcon") {
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

            // It is not possible to set `FluidMenuBarExtra` as the main scene.
            // To get around this, we're removing empty Settings view.
            // In the future, we should implement the Settings view, for example, to allow setting apps shown in the quick
            // launcher.
            return Settings {
                EmptyView()
            }
            .commands {
                CommandGroup(replacing: .appSettings) {}
            }
        }
    }
#else
    import TuistErrorHandling
    import TuistNoora
    import TuistOnboarding
    import TuistPreviews
    import TuistProfile

    enum TabIdentifier: Hashable {
        case previews, profile
    }

    @main
    struct TuistApp: App {
        @StateObject private var authenticationService = AuthenticationService()
        @State var activeTab = TabIdentifier.previews

        var body: some Scene {
            WindowGroup {
                ServerCredentialsStore.$current.withValue(
                    ServerCredentialsStore(backend: .keychain)
                ) {
                    CachedValueStore.$current.withValue(CachedValueStore(backend: .inSystemProcess)) {
                        Group {
                            if case let .loggedIn(account: account) = authenticationService.authenticationState {
                                TabView(selection: $activeTab) {
                                    PreviewsView()
                                        .environmentObject(authenticationService)
                                        .tabItem {
                                            NooraIcon(.deviceMobile)
                                            Text("Previews")
                                        }
                                        .tag(TabIdentifier.previews)

                                    ProfileView(account: account)
                                        .environmentObject(authenticationService)
                                        .tabItem {
                                            NooraIcon(.user)
                                                .frame(width: 24, height: 24)
                                            Text("Profile")
                                        }
                                        .tag(TabIdentifier.profile)
                                }
                                .onOpenURL { _ in
                                    activeTab = .previews
                                }
                                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { _ in
                                    activeTab = .previews
                                }
                                .accentColor(Noora.Colors.accent)
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
