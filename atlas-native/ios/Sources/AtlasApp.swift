import SwiftUI

@main
struct AtlasApp: App {
    @StateObject private var authentication = AtlasAuthentication()
    @StateObject private var navigation = AtlasNavigation()
    @StateObject private var appearance = AtlasAppearance()
    #if os(macOS)
    @StateObject private var updater = AtlasUpdater()
    @NSApplicationDelegateAdaptor(AtlasPushDelegate.self) private var pushDelegate
    @Environment(\.openWindow) private var openWindow
    #else
    @UIApplicationDelegateAdaptor(AtlasPushDelegate.self) private var pushDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        #if os(macOS)
        Window("Atlas", id: "workspace") {
            root.frame(minWidth: 820, minHeight: 580)
                .onAppear { pushDelegate.openWorkspace = { openWindow(id: "workspace") } }
        }
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
        .commands { AtlasUpdateCommands(updater: updater) }
        Settings {
            AtlasDesktopSettings(server: authentication.server, accounts: authentication.accountSettings,
                                 profileRequest: authentication.businessRequest, notifications: authentication.pushNotifications,
                                 signOut: authentication.signOut, workstation: authentication.workstation, updater: updater)
                .modifier(AtlasThemeScope(appearance: appearance, server: authentication.server))
                .environment(\.atlasReadCache, authentication.cachedRead)
                .environment(\.atlasEnvironmentRequest, authentication.server == nil ? nil : authentication.environmentRequest)
        }
        #else
        WindowGroup { root }
        #endif
    }

    private var root: some View {
            ZStack {
                if authentication.server != nil {
                    workspace
                } else {
                    AtlasLoginView(authentication: authentication)
                }
            }
            .modifier(AtlasThemeScope(appearance: appearance, server: authentication.server))
            .task(id: authentication.server) {
                #if os(iOS)
                await authentication.liveActivity.configure(
                    server: authentication.server,
                    request: authentication.server == nil ? nil : authentication.liveActivityRequest
                )
                authentication.liveActivity.setActive(scenePhase == .active)
                #elseif os(macOS)
                await authentication.workstation?.load()
                #endif
                await appearance.configure(server: authentication.server)
                await authentication.pushNotifications.configure(
                    server: authentication.server,
                    request: authentication.server == nil ? nil : authentication.pushRequest
                )
                await authentication.pushNotifications.refresh(token: pushDelegate.token)
            }
            .onChange(of: pushDelegate.token) { _, token in
                Task { await authentication.pushNotifications.refresh(token: token) }
            }
            .onChange(of: pushDelegate.registrationFailed) { _, failed in
                if failed { authentication.pushNotifications.registrationFailed() }
            }
            .onChange(of: pushDelegate.destination, initial: true) { _, url in
                if let url { navigation.receive(url, server: authentication.server); pushDelegate.destination = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                #if os(iOS)
                authentication.liveActivity.setActive(phase == .active)
                #endif
                if phase == .active {
                    #if os(iOS)
                    authentication.sharedItems?.reload()
                    #endif
                    Task { await appearance.refresh(); await authentication.pushNotifications.refresh() }
                }
            }
            #if os(iOS)
            .environment(\.atlasLiveActivity, authentication.liveActivity)
            #endif
            .environment(\.atlasEnvironmentRequest, authentication.environmentRequest)
            .environment(\.atlasReadCache, authentication.cachedRead)
            .environment(\.atlasNavigation, navigation)
            .task { await authentication.restore(); navigation.resolve(server: authentication.server) }
            .onOpenURL { navigation.receive($0, server: authentication.server) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { navigation.receive(url, server: authentication.server) }
            }
            .onChange(of: authentication.server) { previous, server in
                if previous != nil, server == nil { navigation.reset() }
                navigation.resolve(server: server)
            }
            .alert("Atlas link", isPresented: Binding(
                get: { navigation.message != nil && !navigation.hasVisibleProtectedWork },
                set: { if !$0 { navigation.message = nil } }
            )) {
                Button("OK") { navigation.message = nil }
            } message: { Text(navigation.message ?? "") }
    }

    @ViewBuilder private var workspace: some View {
        if let server = authentication.server {
            AtlasWorkspaceView(holidayRequest: authentication.holidayRequest,
                               businessRequest: authentication.businessRequest,
                               orbitRequest: authentication.orbitRequest,
                               orbitLocalRequest: authentication.orbitLocalRequest,
                               presence: authentication.presence, navigation: navigation,
                               automation: authentication) {
                #if os(iOS)
                AtlasSettingsView(server: server, accounts: authentication.accountSettings, signOut: authentication.signOut,
                                  profileRequest: authentication.businessRequest, notifications: authentication.pushNotifications,
                                  sharedItems: authentication.sharedItems, connections: authentication.connectionSettings)
                #else
                AtlasSettingsView(server: server, accounts: authentication.accountSettings, signOut: authentication.signOut,
                                  profileRequest: authentication.businessRequest, notifications: authentication.pushNotifications,
                                  connections: authentication.connectionSettings)
                #endif
            }
            #if os(iOS)
            .modifier(AtlasSharedItemsPresentation(model: authentication.sharedItems,
                                                   protectedWork: navigation.hasVisibleProtectedWork))
            #endif
            .safeAreaInset(edge: .bottom) {
                if let message = authentication.errorMessage {
                    Text(message).foregroundStyle(.red).padding()
                }
            }
            .environment(\.atlasServer, server)
        }
    }
}
