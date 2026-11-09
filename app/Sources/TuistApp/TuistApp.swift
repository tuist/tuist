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
    import SafariServices
    import TuistErrorHandling
    import TuistFeatureFlags
    import TuistNavigation
    import TuistNoora
    import TuistNotifications
    import TuistOnboarding
    import TuistPreviews
    import TuistProfile
    import TuistSDK

    @main
    struct TuistApp: App {
        @UIApplicationDelegateAdaptor(PushNotificationsAppDelegate.self) private var appDelegate
        @StateObject private var bootstrapper = AppBootstrapper()
        @State private var navigation = AppNavigation()

        var body: some Scene {
            WindowGroup {
                Group {
                    if bootstrapper.isReady {
                        #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("--layout-preview") ||
                                Bundle.main.object(forInfoDictionaryKey: "TuistJamsPreview") as? Bool == true
                            {
                                AccountHomeView(
                                    account: Account(email: "preview@example.com", handle: "pedro"),
                                    isLayoutPreview: true
                                )
                                .environment(FeatureFlags(enabled: ProcessInfo.processInfo.arguments
                                        .contains("--without-ai") ? [] : [.ai]))
                            } else {
                                RootView()
                            }
                        #else
                            RootView()
                        #endif
                    } else {
                        ProgressView()
                    }
                }
                .environment(navigation)
                .onOpenURL { navigation.receive($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { navigation.receive(url) }
                }
                .environment(\.openURL, OpenURLAction { url in
                    let isNativeLink = url.scheme?.lowercased() == "tuist" && url.host?.lowercased() == "app"
                    guard isNativeLink || (try? AppRoute(url: url, serverURL: AppServerEnvironmentService().url())) != nil else {
                        return .systemAction
                    }
                    navigation.receive(url)
                    return .handled
                })
            }
        }
    }

    private struct RootView: View {
        @StateObject private var authenticationService = AuthenticationService(profilesEnabled: true)
        @State private var featureFlags = FeatureFlags()
        @State private var hasLoadedProfiles = false
        @Environment(AppNavigation.self) private var navigation
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Group {
                if authenticationService.isChangingProfile {
                    ProgressView()
                } else {
                    content
                }
            }
            .id(ServerAuthenticationSession.current.id)
            .environmentObject(authenticationService)
            .environment(featureFlags)
            .withErrorHandling()
            .onChange(of: navigation.pendingURL) { _, _ in
                openPendingURL()
            }
            .onChange(of: authenticationService.authenticationState, initial: true) { _, state in
                navigation.reset()
                if case .loggedIn = state { openPendingURL() }
            }
            .onChange(of: authenticationService.isChangingProfile) { _, changing in
                if changing {
                    navigation.reset(clearPending: hasLoadedProfiles && authenticationService.activeProfileID != nil)
                } else {
                    openPendingURL()
                }
            }
            .onChange(of: authenticationService.isSigningIn) { _, signingIn in
                if !signingIn { openPendingURL() }
            }
            .sheet(isPresented: Binding(
                get: { navigation.webURL != nil },
                set: { if !$0 { navigation.webURL = nil } }
            )) {
                if let url = navigation.webURL { AppWebView(url: url).id(url) }
            }
            .alert("Unable to open link", isPresented: Binding(
                get: { navigation.error != nil },
                set: { if !$0 { navigation.error = nil } }
            )) {
                Button("OK", role: .cancel) { navigation.error = nil }
            } message: {
                if navigation.error == .differentServer {
                    Text("This link belongs to a different Tuist server. Sign in to that server and open the link again.")
                } else if navigation.error == .differentOrganization {
                    Text("This link belongs to a different organization. Switch organizations and open the link again.")
                } else {
                    Text("This navigation link is invalid or unsupported.")
                }
            }
            .task {
                authenticationService.beforeProfileChange = { await PushNotifications.shared.prepareForProfileChange() }
                guard !authenticationService.isChangingProfile else { return }
                try? await authenticationService.loadProfiles()
                hasLoadedProfiles = true
                openPendingURL()
            }
            .task(id: authenticationService.authenticationState) {
                await PushNotifications.shared.refresh()
            }
            .task(id: authenticationService.authenticationState) {
                await featureFlags.refresh(for: authenticationService.authenticationState)
            }
            .onChange(of: scenePhase) { _, scenePhase in
                guard scenePhase == .active else { return }
                Task { await PushNotifications.shared.refresh() }
                Task { await featureFlags.refresh(for: authenticationService.authenticationState) }
            }
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
            case let .loggedIn(account, _):
                AccountHomeView(account: account)
                    .id(authenticationService.activeProfileID)
            case .loggedOut:
                LogInView()
                #if DEBUG
                    .task {
                        await checkForAutomaticLogin()
                    }
                #endif
            }
        }

        private func openPendingURL() {
            guard case .loggedIn = authenticationService.authenticationState,
                  hasLoadedProfiles, !authenticationService.isChangingProfile, !authenticationService.isSigningIn
            else { return }
            navigation.openPendingURL(serverURL: AppServerEnvironmentService().url())
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

    private struct AppWebView: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context _: Context) -> SFSafariViewController {
            SFSafariViewController(url: url)
        }

        func updateUIViewController(_: SFSafariViewController, context _: Context) {}
    }
#endif
