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
        @StateObject private var bootstrapper = AppBootstrapper()

        private let updaterController: SPUStandardUpdaterController

        init() {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        var body: some Scene {
            // `FluidMenuBarExtra` creates an `NSStatusItem` on initialization and expects to be
            // initialized only once for the lifetime of the app. `body` is re-evaluated, for example
            // when `bootstrapper.isReady` changes, so creating the extra unconditionally here leaves
            // a stale duplicated icon in the menu bar. The readiness state is instead observed by
            // `MenuBarRootView`, which swaps the spinner for the menu inside the same status item.
            if appDelegate.menuBarExtra == nil {
                appDelegate.menuBarExtra = FluidMenuBarExtra(title: "Tuist", image: "MenuBarIcon") {
                    MenuBarRootView(
                        bootstrapper: bootstrapper,
                        appDelegate: appDelegate,
                        updaterController: updaterController
                    )
                }
            }

            // `FluidMenuBarExtra` cannot be used as the main scene.
            // To get around this, we're returning an empty Settings view.
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

    private struct MenuBarRootView: View {
        @ObservedObject var bootstrapper: AppBootstrapper
        let appDelegate: AppDelegate
        let updaterController: SPUStandardUpdaterController

        var body: some View {
            if bootstrapper.isReady {
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
            } else {
                ProgressView()
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
        @StateObject private var bootstrapper = AppBootstrapper()

        var body: some Scene {
            WindowGroup {
                if bootstrapper.isReady {
                    RootView()
                } else {
                    ProgressView()
                }
            }
        }
    }

    private struct RootView: View {
        @StateObject private var authenticationService = AuthenticationService()
        @State private var activeTab = TabIdentifier.previews

        var body: some View {
            content
                .environmentObject(authenticationService)
                .withErrorHandling()
                .task {
                    TuistSDK(
                        fullHandle: "tuist/tuist",
                        apiKey: "tuist_019b26d5-fd7e-7b79-ae62-b5525b26ce38_OTSCoR3hGfPI20i1Hfnpl7HPSWI="
                    )
                    .monitorPreviewUpdates()
                }
        }

        @ViewBuilder
        private var content: some View {
            switch authenticationService.authenticationState {
            case let .loggedIn(account):
                TabView(selection: $activeTab) {
                    PreviewsView()
                        .tabItem {
                            NooraIcon(.deviceMobile)
                            Text("Previews")
                        }
                        .tag(TabIdentifier.previews)

                    ProfileView(account: account)
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
            case .loggedOut:
                LogInView()
                #if DEBUG
                    .task {
                        await checkForAutomaticLogin()
                    }
                #endif
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
