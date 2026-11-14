import SwiftUI

struct AppWorkspace: View {
    @StateObject private var client = AppClient()
    @State private var selection = "previews"
    @State private var addingProfile = false

    var body: some View {
        Group {
            if client.view.active == nil {
                SignInView(client: client)
            } else {
                #if os(macOS)
                    NavigationSplitView {
                        List(selection: $selection) {
                            Label("Previews", systemImage: "square.stack.3d.up").tag("previews")
                            Label("Profile", systemImage: "person.crop.circle").tag("profile")
                        }
                    } detail: {
                        NavigationStack {
                            if selection == "profile" { ProfileView(client: client, addingProfile: $addingProfile) }
                            else { PreviewsView(client: client) }
                        }
                    }
                    .frame(minWidth: 720, minHeight: 500)
                    .id(client.view.generation)
                #else
                    TabView(selection: $selection) {
                        NavigationStack { PreviewsView(client: client) }
                            .tabItem { Label("Previews", systemImage: "square.stack.3d.up") }.tag("previews")
                        NavigationStack { ProfileView(client: client, addingProfile: $addingProfile) }
                            .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag("profile")
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
        .task { await client.perform("snapshot") }
        .sheet(isPresented: $addingProfile) {
            NavigationStack {
                SignInView(client: client)
                    .toolbar { Button("Cancel") { Task { await client.cancelSignIn(); addingProfile = false } } }
                    .onDisappear { Task { await client.cancelSignIn() } }
            }
        }
        .onChange(of: client.view.generation) { _, _ in addingProfile = false }
        .alert("Something went wrong", isPresented: Binding(
            get: { client.error != nil }, set: { if !$0 { client.error = nil } }
        )) {
            Button("OK") { client.error = nil }
        } message: { Text(verbatim: client.error ?? "") }
    }
}

private struct SignInView: View {
    @ObservedObject var client: AppClient
    @State private var server = "https://tuist.dev"
    @State private var selfHosted = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 56)).foregroundStyle(.purple)
            Text("Tuist Code").font(.largeTitle.bold())
            Text("Your projects and previews, together.").foregroundStyle(.secondary)
            if selfHosted {
                TextField("Server URL", text: $server).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Button("Sign in") { signIn("tuist") }.buttonStyle(.borderedProminent)
                Button("Use Tuist-hosted") { selfHosted = false; server = "https://tuist.dev" }
            } else {
                Button("Continue with Apple") { signIn("apple") }.buttonStyle(.bordered)
                Button("Continue with GitHub") { signIn("github") }.buttonStyle(.bordered)
                Button("Continue with Google") { signIn("google") }.buttonStyle(.bordered)
                Button("Sign in with Tuist") { signIn("tuist") }.buttonStyle(.borderedProminent)
                Button("Use a self-hosted server") { selfHosted = true }
            }
            if client.signingIn { ProgressView() }
            Spacer()
            Text("Internal preview · Your current Tuist app is unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28).frame(maxWidth: 440).frame(maxWidth: .infinity)
        .disabled(client.signingIn)
    }

    private func signIn(_ provider: String) {
        Task { await client.signIn(server: server, provider: provider) }
    }
}

private struct ProfileView: View {
    @ObservedObject var client: AppClient
    @Binding var addingProfile: Bool
    @State private var confirmingDelete = false

    var body: some View {
        List {
            if let account = client.view.active {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(.purple)
                        Text(verbatim: "@\(account.handle ?? "")").font(.title3.weight(.medium))
                    }.frame(maxWidth: .infinity).padding(.vertical)
                    LabeledContent("Email", value: account.email ?? "")
                    LabeledContent("Server", value: account.server)
                }
                Section("Profiles") {
                    ForEach(client.view.profiles) { profile in
                        Button {
                            Task { await client.perform("switch_profile", ["id": profile.id]) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: profile.handle ?? profile.email ?? profile.server)
                                    Text(verbatim: profile.server).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == client.view.active_profile_id { Image(systemName: "checkmark") }
                                if profile.rejected { Image(systemName: "exclamationmark.triangle") }
                            }
                        }.disabled(profile.rejected)
                    }
                    Button("Add profile", systemImage: "person.badge.plus") { addingProfile = true }
                }
                Section("Organization") {
                    let names = Array(Set((account.organizations ?? []) + [account.handle].compactMap { $0 })).sorted()
                    ForEach(names, id: \.self) { name in
                        Button {
                            Task { await client.perform("select_organization", ["id": account.id, "name": name]) }
                        } label: {
                            HStack {
                                Text(verbatim: name)
                                Spacer()
                                if name == (account.organization ?? account.handle) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            Section {
                Link("Terms of Service", destination: URL(string: "https://tuist.dev/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://tuist.dev/privacy")!)
                Link("Get help", destination: URL(string: "mailto:contact@tuist.dev")!)
                LabeledContent(
                    "App version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                )
            }
            Section {
                Button("Sign out", role: .destructive) { Task { await client.perform("sign_out") } }
                Button("Delete account", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Profile")
        .task(id: client.view.active_profile_id) { await client.perform("organizations") }
        .refreshable { await client.perform("organizations") }
        .confirmationDialog("Delete Account", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await client.perform("delete_account") } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to delete your account? This action cannot be undone.") }
    }
}
