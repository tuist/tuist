import SwiftUI

struct AppWorkspace: View {
    @StateObject private var client = AppClient()
    @State private var selection = "threads"
    @State private var addingProfile = false

    var body: some View {
        Group {
            if client.view.active == nil {
                LogInView(client: client)
            } else {
                #if os(macOS)
                    // On the Mac, a source-list sidebar takes the place of the tab bar.
                    NavigationSplitView {
                        List(selection: $selection) {
                            Label("Threads", systemImage: "bubble.left.and.bubble.right").tag("threads")
                            Label("Profile", systemImage: "person.crop.circle").tag("profile")
                        }
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
                    } detail: {
                        NavigationStack { destination }
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                profilesMenu
                            } label: {
                                Label("Profiles", systemImage: "person.crop.circle")
                            }
                            .help("Switch profile")
                        }
                    }
                    .id(client.view.generation)
                #else
                    TabView(selection: $selection) {
                        NavigationStack { ThreadsView(client: client) }
                            .tabItem { Label("Threads", systemImage: "bubble.left.and.bubble.right.fill") }
                            .tag("threads")
                        NavigationStack { ProfileView(client: client, addingProfile: $addingProfile) }
                            .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                            .tag("profile")
                    }
                    .background(ProfileTabMenu {
                        UIMenu(title: String(localized: "Profiles"), children: client.view.profiles.map { profile in
                            UIAction(
                                title: profile.handle ?? profile.email ?? profile.server,
                                subtitle: profile.server,
                                attributes: profile.rejected ? .disabled : [],
                                state: profile.id == client.view.active_profile_id ? .on : .off
                            ) { _ in Task { await client.perform("switch_profile", ["id": profile.id]) } }
                        } + [
                            UIAction(
                                title: String(localized: "Add profile"),
                                image: UIImage(systemName: "person.badge.plus")
                            ) { _ in addingProfile = true },
                            UIAction(title: String(localized: "View profile")) { _ in selection = "profile" },
                        ])
                    })
                    .id(client.view.generation)
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
        .tint(Noora.primary)
        .task { await client.perform("snapshot") }
        .sheet(isPresented: $addingProfile) {
            NavigationStack {
                LogInView(client: client)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { Task { await client.cancelSignIn(); addingProfile = false } }
                        }
                    }
                    .onDisappear { Task { await client.cancelSignIn() } }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 640)
            #endif
        }
        .onChange(of: client.view.generation) { _, _ in addingProfile = false }
        .alert("Something went wrong", isPresented: Binding(
            get: { client.error != nil }, set: { if !$0 { client.error = nil } }
        )) {
            Button("OK") { client.error = nil }
        } message: { Text(verbatim: client.error ?? "") }
    }

    #if os(macOS)
        @ViewBuilder private var destination: some View {
            if selection == "profile" {
                ProfileView(client: client, addingProfile: $addingProfile)
            } else {
                ThreadsView(client: client)
            }
        }

        @ViewBuilder private var profilesMenu: some View {
            ForEach(client.view.profiles) { profile in
                Toggle(isOn: Binding(
                    get: { profile.id == client.view.active_profile_id },
                    set: { if $0 { Task { await client.perform("switch_profile", ["id": profile.id]) } } }
                )) {
                    Text(verbatim: profile.handle ?? profile.email ?? profile.server)
                    Text(verbatim: profile.server)
                }
                .disabled(profile.rejected)
            }
            Divider()
            Button("Add Profile…") { addingProfile = true }
            Button("View Profile") { selection = "profile" }
            Divider()
            Button("Sign Out") { Task { await client.perform("sign_out") } }
        }
    #endif
}

/// The shipping app's Profile page (`app/Sources/TuistProfile/ProfileView.swift`).
/// Switching and adding profiles live in the Profile tab's menu on iOS and the
/// toolbar's profile menu on macOS, as in the shipping app.
private struct ProfileView: View {
    @ObservedObject var client: AppClient
    @Binding var addingProfile: Bool
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            if let account = client.view.active {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 72))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Noora.primary)
                        Text(verbatim: "@\(account.handle ?? account.email ?? "")")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                        if account.shared == true {
                            Text("From the Tuist app").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                if account.rejected {
                    // The server refused this profile's session; signing in again replaces it.
                    Section {
                        Label("Your session has expired. Sign in again to keep using this profile.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Sign In Again") {
                            Task { await client.signIn(server: account.server, provider: "tuist") }
                        }
                        .disabled(client.signingIn)
                    }
                }

                Section {
                    LabeledContent("Email", value: account.email ?? "")
                    LabeledContent("Server", value: account.server.hasSuffix("/")
                        ? String(account.server.dropLast()) : account.server)
                }
            }

            Section {
                ExternalLinkRow(title: "Terms of Service", url: URL(string: "https://tuist.dev/terms")!)
                ExternalLinkRow(title: "Privacy Policy", url: URL(string: "https://tuist.dev/privacy")!)
            }

            Section {
                ExternalLinkRow(title: "Get help", url: URL(string: "mailto:contact@tuist.dev")!)
            }

            Section {
                LabeledContent(
                    "App version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                )
            }

            #if os(macOS)
                // System Settings puts account actions in trailing push buttons.
                Section {
                    HStack {
                        Button("Delete Account…", role: .destructive) { confirmingDelete = true }
                        Spacer()
                        Button("Sign Out") { Task { await client.perform("sign_out") } }
                    }
                }
            #else
                Section {
                    Button { Task { await client.perform("sign_out") } } label: {
                        Text("Sign out").frame(maxWidth: .infinity)
                    }
                }

                Section {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Text("Delete account").frame(maxWidth: .infinity)
                    }
                }
            #endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Profile")
        .alert("Delete Account", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await client.perform("delete_account") } }
        } message: {
            Text("Are you sure you want to delete your account? This action cannot be undone.")
        }
    }
}

private struct ExternalLinkRow: View {
    @Environment(\.openURL) private var openURL
    let title: LocalizedStringKey
    let url: URL

    var body: some View {
        Button { openURL(url) } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
