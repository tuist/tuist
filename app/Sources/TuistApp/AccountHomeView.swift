#if os(iOS)
    import SwiftUI
    import TuistAuthentication
    import TuistFeatureFlags
    import TuistNoora
    import TuistPreviews
    import TuistProfile
    import TuistServer
    import UIKit

    struct AccountHomeView: View {
        let account: Account
        var isLayoutPreview = false

        @EnvironmentObject private var authenticationService: AuthenticationService
        @Environment(FeatureFlags.self) private var featureFlags
        @State private var activeTab = "previews"
        @State private var selectedAccount = "Tuist"
        @State private var selectedThreadAccount: String?
        @State private var organizations: [String] = []
        @State private var accountsError: String?
        @State private var showingAccounts = false
        @State private var showingSignOut = false
        @State private var showingPreviewNotice = false

        private var threadAccount: String {
            isLayoutPreview ? selectedAccount : selectedThreadAccount ?? account.handle
        }

        var body: some View {
            TabView(selection: $activeTab) {
                if featureFlags.isEnabled(.ai) {
                    ThreadsPreview(
                        accountName: threadAccount,
                        isLayoutPreview: isLayoutPreview,
                        switchAccount: { showingAccounts = true }
                    )
                    .id("\(threadAccount)@\(AppServerEnvironmentService().url().absoluteString)")
                    .tabItem { Label("Threads", systemImage: "bubble.left.and.bubble.right.fill") }
                    .tag("threads")
                }

                previews
                    .tabItem { Label("Previews", systemImage: "square.stack.3d.up.fill") }
                    .tag("previews")

                profile
                    .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                    .tag("profile")
            }
            .background(ProfileTabContextMenu(menu: quickSwitchMenu))
            .tint(Noora.Colors.accent)
            .onAppear {
                if isLayoutPreview, featureFlags.isEnabled(.ai) {
                    activeTab = ProcessInfo.processInfo.arguments.contains("--show-previews") ? "previews" : "threads"
                }
            }
            .onChange(of: featureFlags.isEnabled(.ai)) { _, enabled in
                if !enabled, activeTab == "threads" { activeTab = "previews" }
            }
            .onOpenURL { _ in activeTab = "previews" }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { _ in activeTab = "previews" }
            .sheet(isPresented: $showingAccounts) {
                NavigationStack {
                    List {
                        Section {
                            if isLayoutPreview {
                                accountRow("Tuist", subtitle: "Organization", symbol: "building.2.crop.circle.fill")
                                accountRow("Personal", subtitle: "@\(account.handle)", symbol: "person.crop.circle.fill")
                            } else {
                                accountRow(account.handle, subtitle: "@\(account.handle)", symbol: "person.crop.circle.fill")
                                ForEach(organizations, id: \.self) { name in
                                    accountRow(
                                        name,
                                        subtitle: String(localized: "Organization"),
                                        symbol: "building.2.crop.circle.fill"
                                    )
                                }
                            }
                        } footer: {
                            if isLayoutPreview { Text("Design preview · Sample accounts") }
                        }
                        if let accountsError { Text(verbatim: accountsError).foregroundStyle(.red) }
                    }
                    .navigationTitle("Accounts")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { showingAccounts = false }
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .presentationDetents([.medium])
                .task {
                    guard !isLayoutPreview else { return }
                    do {
                        let values = try await ListOrganizationsService()
                            .listOrganizations(serverURL: AppServerEnvironmentService().url())
                        guard !Task.isCancelled else { return }
                        organizations = Array(Set(values)).sorted()
                        accountsError = nil
                    } catch { if !Task.isCancelled { accountsError = error.localizedDescription } }
                }
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
                Text("Signing out of this app does not stop running threads.")
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
                                Button { showingAccounts = true } label: {
                                    HStack {
                                        Label("Account", systemImage: "building.2")
                                        Spacer()
                                        Text(selectedAccount).foregroundStyle(Color.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }
                                    .foregroundStyle(Color.primary)
                                }
                                .accessibilityLabel("Switch account")
                                .accessibilityValue(selectedAccount)
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
                        .id(selectedAccount)
                } else {
                    PreviewsView()
                }
            #else
                PreviewsView()
            #endif
        }

        private func quickSwitchMenu() -> UIMenu {
            var actions: [UIMenuElement] = []
            if isLayoutPreview {
                actions = ["Tuist", "Personal"].map { name in
                    UIAction(
                        title: name,
                        image: UIImage(systemName: name == "Tuist" ? "building.2" : "person"),
                        state: selectedAccount == name ? .on : .off
                    ) { _ in
                        selectAccount(name)
                    }
                }
            }
            actions.append(UIMenu(options: .displayInline, children: [
                UIAction(title: "View profile", image: UIImage(systemName: "person.crop.circle")) { _ in
                    activeTab = "profile"
                },
                UIAction(
                    title: "Sign out",
                    image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                    attributes: .destructive
                ) { _ in
                    showingSignOut = true
                },
            ]))
            return UIMenu(title: isLayoutPreview ? "Switch account" : "Profile", children: actions)
        }

        private func selectAccount(_ name: String) {
            if isLayoutPreview { selectedAccount = name } else { selectedThreadAccount = name }
            showingAccounts = false
        }

        private func accountRow(_ name: String, subtitle: String, symbol: String) -> some View {
            Button {
                selectAccount(name)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .foregroundStyle(Noora.Colors.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).foregroundStyle(Noora.Colors.surfaceLabelPrimary)
                        Text(subtitle).font(.subheadline).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    if threadAccount == name {
                        Image(systemName: "checkmark").foregroundStyle(Noora.Colors.accent)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private struct ProfileTabContextMenu: UIViewControllerRepresentable {
        var menu: () -> UIMenu

        func makeUIViewController(context _: Context) -> MenuController {
            MenuController(menu: menu)
        }

        func updateUIViewController(_ controller: MenuController, context _: Context) {
            controller.menu = menu
            DispatchQueue.main.async { controller.install() }
        }

        static func dismantleUIViewController(_ controller: MenuController, coordinator _: ()) {
            controller.uninstall()
        }

        final class MenuController: UIViewController, UIContextMenuInteractionDelegate {
            var menu: () -> UIMenu
            private weak var tabBar: UITabBar?
            private lazy var interaction = UIContextMenuInteraction(delegate: self)

            init(menu: @escaping () -> UIMenu) {
                self.menu = menu
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
                guard let bar = findTabBar(in: root), bar !== tabBar else { return }
                uninstall()
                tabBar = bar
                bar.addInteraction(interaction)
            }

            func uninstall() {
                tabBar?.removeInteraction(interaction)
                tabBar = nil
            }

            private func findTabBar(in controller: UIViewController) -> UITabBar? {
                if let controller = controller as? UITabBarController { return controller.tabBar }
                for child in controller.children {
                    if let bar = findTabBar(in: child) { return bar }
                }
                return nil
            }

            private func profileItem(in view: UIView) -> UIView? {
                if view is UIControl, view.accessibilityLabel == tabBar?.items?.last?.title { return view }
                for child in view.subviews {
                    if let item = profileItem(in: child) { return item }
                }
                return nil
            }

            func contextMenuInteraction(
                _: UIContextMenuInteraction,
                previewForHighlightingMenuWithConfiguration _: UIContextMenuConfiguration
            ) -> UITargetedPreview? {
                guard let tabBar, let item = profileItem(in: tabBar) else { return nil }
                return UITargetedPreview(view: item)
            }

            func contextMenuInteraction(
                _: UIContextMenuInteraction,
                configurationForMenuAtLocation location: CGPoint
            ) -> UIContextMenuConfiguration? {
                guard let tabBar, let count = tabBar.items?.count, count > 0,
                      location.x >= tabBar.bounds.width * CGFloat(count - 1) / CGFloat(count)
                else { return nil }
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
