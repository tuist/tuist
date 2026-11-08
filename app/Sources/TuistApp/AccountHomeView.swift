#if os(iOS)
    import SwiftUI
    import TuistAuthentication
    import TuistErrorHandling
    import TuistFeatureFlags
    import TuistNavigation
    import TuistNoora
    import TuistOnboarding
    import TuistPreviews
    import TuistProfile
    import TuistServer
    import UIKit

    struct AccountHomeView: View {
        let account: Account
        var isLayoutPreview = false

        @EnvironmentObject private var authenticationService: AuthenticationService
        @EnvironmentObject private var errorHandler: ErrorHandling
        @Environment(FeatureFlags.self) private var featureFlags
        @Environment(AppNavigation.self) private var navigation
        @State private var showingSignOut = false
        @State private var showingPreviewNotice = false
        @State private var showingAddProfile = false
        @State private var pendingOrganization: StoredOrganization?

        private var organizationName: String {
            isLayoutPreview ? account.handle : authenticationService.selectedOrganization ?? account.handle
        }

        var body: some View {
            @Bindable var navigation = navigation
            TabView(selection: $navigation.tab) {
                if featureFlags.isEnabled(.ai) {
                    JamsPreview(
                        accountName: organizationName,
                        isLayoutPreview: isLayoutPreview
                    )
                    .tabItem { Label("Jams", systemImage: "bubble.left.and.bubble.right.fill") }
                    .tag(AppNavigation.Tab.jams)
                }

                previews
                    .tabItem { Label("Previews", systemImage: "square.stack.3d.up.fill") }
                    .tag(AppNavigation.Tab.previews)

                profile
                    .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                    .tag(AppNavigation.Tab.profile)
            }
            .background(ProfileTabContextMenu(menu: quickSwitchMenu, refresh: {
                if !isLayoutPreview { await authenticationService.refreshOrganizations() }
            }))
            .tint(Noora.Colors.accent)
            .onAppear {
                if isLayoutPreview, featureFlags.isEnabled(.ai) {
                    navigation.tab = ProcessInfo.processInfo.arguments.contains("--show-previews") ? .previews : .jams
                }
            }
            .onChange(of: featureFlags.isEnabled(.ai)) { _, enabled in
                if !enabled, navigation.tab == .jams { navigation.tab = .previews }
            }
            .sheet(isPresented: $showingAddProfile, onDismiss: {
                authenticationService.cancelAddingProfile()
            }) {
                NavigationStack {
                    LogInView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showingAddProfile = false }
                                    .disabled(authenticationService.isSigningIn || authenticationService.isChangingProfile)
                            }
                        }
                }
                .interactiveDismissDisabled(authenticationService.isSigningIn || authenticationService.isChangingProfile)
                .onChange(of: authenticationService.isAddingProfile) { _, adding in
                    if !adding { showingAddProfile = false }
                }
            }
            .confirmationDialog("Switch organization?", isPresented: Binding(
                get: { pendingOrganization != nil }, set: { if !$0 { pendingOrganization = nil } }
            ), titleVisibility: .visible) {
                if let pendingOrganization {
                    Button("Switch organization") {
                        Task {
                            do { try await authenticationService.switchOrganization(pendingOrganization) }
                            catch { errorHandler.handle(error: error) }
                            self.pendingOrganization = nil
                        }
                    }
                }
            } message: {
                Text("Open screens and unsent drafts will be closed. Running jams will continue.")
            }
            .confirmationDialog("Sign out of Tuist?", isPresented: $showingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    if isLayoutPreview {
                        showingPreviewNotice = true
                    } else {
                        Task { await authenticationService.signOut() }
                    }
                }
            } message: {
                Text("Signing out of this app does not stop running jams.")
            }
            .alert("Layout preview", isPresented: $showingPreviewNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No account is signed in. These screens use sample data.")
            }
        }

        private var profile: some View {
            NavigationStack {
                Group {
                    if isLayoutPreview {
                        List {
                            Section {
                                HStack(spacing: 16) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 52))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.handle.capitalized)
                                            .font(.title3.weight(.semibold))
                                        Text("@\(account.handle)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            Section {
                                Link(destination: URL(string: "https://tuist.dev/terms")!) {
                                    Label("Terms of Service", systemImage: "doc.text")
                                        .foregroundStyle(Color.primary)
                                }
                                Link(destination: URL(string: "https://tuist.dev/privacy")!) {
                                    Label("Privacy Policy", systemImage: "hand.raised")
                                        .foregroundStyle(Color.primary)
                                }
                            }
                            Section {
                                Button("Sign out", role: .destructive) { showingSignOut = true }
                            } footer: {
                                Text("Design preview · Sample data")
                            }
                        }
                    } else {
                        ProfileView(account: account)
                    }
                }
                .navigationTitle("Profile")
            }
        }

        @ViewBuilder
        private var previews: some View {
            #if DEBUG
                if isLayoutPreview {
                    PreviewsLayoutPreview()
                } else {
                    PreviewsView(accountName: authenticationService.selectedOrganization ?? account.handle)
                }
            #else
                PreviewsView(accountName: authenticationService.selectedOrganization ?? account.handle)
            #endif
        }

        private func quickSwitchMenu() -> UIMenu {
            var actions: [UIMenuElement] = []
            if isLayoutPreview {
                actions = [UIAction(
                    title: "Tuist",
                    subtitle: "tuist.dev",
                    image: UIImage(systemName: "person.crop.circle"),
                    state: .on
                ) { _ in }]
            } else {
                actions = authenticationService.organizations.map { organization in
                    UIAction(
                        title: organization.name,
                        subtitle: organization.serverURL.absoluteString,
                        image: UIImage(systemName: "building.2"),
                        state: authenticationService.activeProfileID == organization.profileID &&
                            authenticationService.selectedOrganization == organization.name ? .on : .off
                    ) { _ in
                        if organization.profileID != authenticationService.activeProfileID ||
                            organization.name != authenticationService.selectedOrganization
                        { pendingOrganization = organization }
                    }
                }
                actions.append(UIAction(
                    title: String(localized: "Add profile"), image: UIImage(systemName: "person.badge.plus")
                ) { _ in
                    Task {
                        do {
                            try await authenticationService.beginAddingProfile()
                            showingAddProfile = true
                        } catch { errorHandler.handle(error: error) }
                    }
                })
            }
            actions.append(UIMenu(options: .displayInline, children: [
                UIAction(title: String(localized: "View profile"), image: UIImage(systemName: "person.crop.circle")) { _ in
                    navigation.navigate(to: .profile)
                },
                UIAction(
                    title: String(localized: "Sign out"),
                    image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                    attributes: .destructive
                ) { _ in
                    showingSignOut = true
                },
            ]))
            return UIMenu(title: String(localized: "Profiles"), children: actions)
        }
    }

    private struct ProfileTabContextMenu: UIViewControllerRepresentable {
        var menu: () -> UIMenu
        var refresh: () async -> Void

        func makeUIViewController(context _: Context) -> MenuController {
            MenuController(menu: menu, refresh: refresh)
        }

        func updateUIViewController(_ controller: MenuController, context _: Context) {
            controller.menu = menu
            controller.refresh = refresh
            DispatchQueue.main.async { controller.install() }
        }

        static func dismantleUIViewController(_ controller: MenuController, coordinator _: ()) {
            controller.uninstall()
        }

        final class MenuController: UIViewController, UIContextMenuInteractionDelegate {
            var menu: () -> UIMenu
            var refresh: () async -> Void
            private lazy var interaction = UIContextMenuInteraction(delegate: self)

            init(menu: @escaping () -> UIMenu, refresh: @escaping () async -> Void) {
                self.menu = menu
                self.refresh = refresh
                super.init(nibName: nil, bundle: nil)
            }

            required init?(coder _: NSCoder) { nil }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                install()
            }

            func install() {
                var root: UIViewController = self
                while let parent = root.parent {
                    root = parent
                }
                guard let bar = findTabBar(in: root), let title = bar.items?.last?.title,
                      let button = profileButton(in: bar, title: title), button !== interaction.view
                else { return }
                uninstall()
                button.addInteraction(interaction)
            }

            func uninstall() {
                interaction.view?.removeInteraction(interaction)
            }

            private func findTabBar(in controller: UIViewController) -> UITabBar? {
                if let controller = controller as? UITabBarController { return controller.tabBar }
                for child in controller.children {
                    if let bar = findTabBar(in: child) { return bar }
                }
                return nil
            }

            private func profileButton(in view: UIView, title: String) -> UIView? {
                if view is UIControl,
                   view.accessibilityLabel == title || view.subviews.contains(where: { ($0 as? UILabel)?.text == title })
                {
                    return view
                }
                for child in view.subviews.reversed() {
                    if let button = profileButton(in: child, title: title) { return button }
                }
                return nil
            }

            func contextMenuInteraction(
                _ interaction: UIContextMenuInteraction,
                previewForHighlightingMenuWithConfiguration _: UIContextMenuConfiguration
            ) -> UITargetedPreview? {
                guard let button = interaction.view, let window = button.window else { return nil }
                // Keep UIKit-managed tab buttons in their glass bar rather than lifting them into the menu preview.
                let preview = UIView(frame: CGRect(x: 0, y: 0, width: button.bounds.width, height: 1))
                let parameters = UIPreviewParameters()
                parameters.backgroundColor = .clear
                parameters.shadowPath = UIBezierPath()
                return UITargetedPreview(
                    view: preview,
                    parameters: parameters,
                    target: UIPreviewTarget(
                        container: window,
                        center: button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.minY), to: window)
                    )
                )
            }

            func contextMenuInteraction(
                _ interaction: UIContextMenuInteraction,
                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
            ) -> UITargetedPreview? {
                contextMenuInteraction(interaction, previewForHighlightingMenuWithConfiguration: configuration)
            }

            func contextMenuInteraction(
                _ interaction: UIContextMenuInteraction,
                willDisplayMenuFor _: UIContextMenuConfiguration,
                animator _: UIContextMenuInteractionAnimating?
            ) {
                Task {
                    await refresh()
                    interaction.updateVisibleMenu { _ in self.menu() }
                }
            }

            func contextMenuInteraction(
                _: UIContextMenuInteraction,
                configurationForMenuAtLocation _: CGPoint
            ) -> UIContextMenuConfiguration? {
                return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in self.menu() }
            }
        }
    }

    #if DEBUG
        private struct PreviewsLayoutPreview: View {
            @Environment(\.dynamicTypeSize) private var dynamicTypeSize
            @State private var project = "Tuist App"
            @State private var showingProjects = false
            @State private var search = ""
            private let projects = ["Tuist App", "Tuist CLI", "Noora", "Tuist Android"]

            var body: some View {
                NavigationStack {
                    List {
                        Section("Latest builds") {
                            build("1.8.0 (142)", branch: "main", time: "12 minutes ago")
                            build("1.8.0 (141)", branch: "fix/account-navigation", time: "1 hour ago")
                            build("1.7.2 (140)", branch: "main", time: "Yesterday")
                        }
                        Section {
                            build("1.7.1 (138)", branch: "main", time: "Oct 28")
                            build("1.7.0 (135)", branch: "main", time: "Oct 25")
                        } header: {
                            Text("Previous builds")
                        } footer: {
                            Text("Design preview · Sample builds")
                        }
                    }
                    .navigationTitle("Previews")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showingProjects = true } label: {
                                HStack(spacing: 4) {
                                    Text(project)
                                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                                }
                            }
                            .tint(.primary)
                            .accessibilityIdentifier("project-picker")
                            .accessibilityLabel("Select project")
                            .accessibilityValue(project)
                        }
                    }
                    .sheet(isPresented: $showingProjects, onDismiss: { search = "" }, content: {
                        NavigationStack {
                            List {
                                ForEach(
                                    projects.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) },
                                    id: \.self
                                ) { name in
                                    Button {
                                        project = name
                                        showingProjects = false
                                    } label: {
                                        HStack {
                                            Text(name).foregroundStyle(Color.primary)
                                            Spacer()
                                            if project == name {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            .searchable(text: $search, prompt: "Search projects")
                            .navigationTitle("Projects")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close", systemImage: "xmark") { showingProjects = false }
                                        .labelStyle(.iconOnly)
                                }
                            }
                        }
                        .presentationDetents([.medium, .large])
                    })
                }
            }

            private func build(_ version: String, branch: String, time: String) -> some View {
                HStack(spacing: 12) {
                    NooraIcon(.brandTuist)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .frame(width: 48, height: 48)
                        .background(Noora.Colors.accent.gradient, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project).font(.body.weight(.semibold))
                        Text(version).font(.subheadline).foregroundStyle(.secondary)
                        Text(branch)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if dynamicTypeSize.isAccessibilitySize {
                            Text(time).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 8)
                        Text(time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    #endif
#endif
