import SwiftUI
import TuistAuthentication
import TuistProjects
import TuistServer

#if os(macOS)
    import Sparkle
    import TuistMenuBar

    @main
    struct TuistApp: App {
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
        @StateObject private var bootstrapper = AppBootstrapper()
        @StateObject private var applicationModel: MacApplicationModel
        @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
        @Environment(\.openWindow) private var openWindow

        private let updaterController: SPUStandardUpdaterController

        init() {
            let updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.updaterController = updaterController
            _applicationModel = StateObject(wrappedValue: MacApplicationModel(updaterController: updaterController))
        }

        var body: some Scene {
            appDelegate.openMainWindow = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            applicationModel.observeURLs(from: appDelegate)
            return scenes
        }

        @SceneBuilder
        private var scenes: some Scene {
            Window("Tuist", id: "main") {
                if bootstrapper.isReady {
                    DesktopView(applicationModel: applicationModel)
                } else {
                    ProgressView().frame(width: 900, height: 560)
                }
            }
            .defaultSize(width: 1100, height: 720)
            .windowResizability(.contentMinSize)
            .windowToolbarStyle(.unified)
            .commands {
                DesktopCommands()
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") { updaterController.updater.checkForUpdates() }
                        .disabled(!updaterController.updater.canCheckForUpdates)
                }
                CommandGroup(after: .newItem) {
                    Button("Open Tuist") {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }
            }

            Settings {
                if bootstrapper.isReady {
                    DesktopSettingsView(applicationModel: applicationModel)
                } else {
                    ProgressView().padding()
                }
            }

            MenuBarExtra("Tuist", image: "MenuBarIcon", isInserted: $showMenuBarExtra) {
                if bootstrapper.isReady {
                    MenuBarView(applicationModel: applicationModel)
                } else {
                    ProgressView().padding()
                }
            }
            .menuBarExtraStyle(.window)
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
        case home, previews, profile
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

    private struct SignedInView: View {
        let account: Account
        @EnvironmentObject private var errorHandling: ErrorHandling
        @State private var activeTab = TabIdentifier.home
        @State private var projectContext: ProjectContext
        @State private var previewsViewModel: PreviewsViewModel
        @State private var pendingPreview: DeeplinkPreview?
        @State private var incomingPreview: DeeplinkPreview?
        @State private var isProjectContextReady = false

        init(account: Account, serverURL: URL) {
            self.account = account
            let context = ProjectContext(scope: "\(serverURL.absoluteString)/\(account.handle)")
            _projectContext = State(initialValue: context)
            _previewsViewModel = State(initialValue: PreviewsViewModel(projectContext: context))
        }

        var body: some View {
            TabView(selection: $activeTab) {
                HomeView(viewModel: previewsViewModel) {
                    activeTab = .previews
                }
                .id(projectContext.selectedFullHandle)
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
                .tag(TabIdentifier.home)

                PreviewsView(viewModel: previewsViewModel, pendingPreview: $pendingPreview)
                    .id(projectContext.selectedFullHandle)
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
            .onOpenURL(perform: openPreviewURL)
            .onChange(of: projectContext.isLoading) {
                routeIncomingPreview()
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                if let url = userActivity.webpageURL { openPreviewURL(url) }
            }
            .task {
                do {
                    try await projectContext.load()
                } catch {
                    if !Task.isCancelled { errorHandling.handle(error: error) }
                }
                isProjectContextReady = true
                routeIncomingPreview()
            }
            .task(id: projectContext.selectedFullHandle) {
                do {
                    try await previewsViewModel.loadSelectedProject()
                } catch {
                    if !Task.isCancelled { errorHandling.handle(error: error) }
                }
            }
            .accentColor(Noora.Colors.accent)
        }

        private func openPreviewURL(_ url: URL) {
            guard let preview = DeeplinkPreview(url: url) else { return }
            incomingPreview = preview
            routeIncomingPreview()
        }

        private func routeIncomingPreview() {
            guard isProjectContextReady, !projectContext.isLoading, let incomingPreview else { return }
            projectContext.selectProject(incomingPreview.fullHandle)
            pendingPreview = incomingPreview
            self.incomingPreview = nil
            activeTab = .previews
        }
    }

    private struct RootView: View {
        @StateObject private var authenticationService = AuthenticationService()

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
            case let .loggedIn(account, server):
                let serverURL = server?.url ?? AppServerEnvironmentService().url()
                SignedInView(account: account, serverURL: serverURL)
                    .id("\(serverURL.absoluteString)/\(account.handle)")
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
