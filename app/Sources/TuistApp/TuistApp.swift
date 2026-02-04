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
    import ArgumentParser
    import TuistErrorHandling
    import TuistNoora
    import TuistOnboarding
    import TuistPreviews
    import TuistProfile
    import TuistSDK

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
                                #if DEBUG
                                    .task {
                                        await checkForAutomaticLogin()
                                    }
                                #endif
                            }
                        }
                        .withErrorHandling()
                        .task {
                            TuistSDK(
                                fullHandle: "tuist/tuist",
                                apiKey: "tuist_019b26d5-fd7e-7b79-ae62-b5525b26ce38_OTSCoR3hGfPI20i1Hfnpl7HPSWI="
                            )
                            .monitorPreviewUpdates()
                        }
                    }
                }
            }
        }

        /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
        /// automatically log in
        private func checkForAutomaticLogin() async {
            struct LaunchArguments: ParsableArguments {
                @Option var email: String?
                @Option var password: String?
            }

            do {
                let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

                guard let email = parsedArguments.email,
                      let password = parsedArguments.password
                else {
                    return
                }

                try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
            } catch {
                // Skipping automatic log in, such as when the credentials are not passed
            }
        }
    }
#endif
