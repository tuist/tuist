#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI

struct AtlasDesktopSettings: View {
    let server: URL?
    let accounts: AtlasAIAccounts
    let profileRequest: AtlasWorkstation.Request?
    let notifications: AtlasPushNotifications?
    let signOut: () -> Void
    let workstation: AtlasWorkstation?
    let updater: AtlasUpdater

    var body: some View {
        TabView {
            NavigationStack {
                if let server {
                    AtlasSettingsView(server: server, accounts: accounts, signOut: signOut,
                                      profileRequest: profileRequest, notifications: notifications)
                } else {
                    ContentUnavailableView("Sign in to Atlas", systemImage: "person.crop.circle",
                                           description: Text("Open the Atlas window to sign in."))
                }
            }.tabItem { Label("General", systemImage: "gearshape") }
            NavigationStack {
                if server != nil {
                    AtlasDesktopAISettings(accounts: accounts)
                } else {
                    Text("Sign in to connect your AI accounts.").foregroundStyle(.secondary)
                }
            }.tabItem { Label("AI accounts", systemImage: "person.crop.circle") }
            Group {
                if let workstation {
                    AtlasWorkstationSettings(model: workstation)
                } else {
                    Text("Sign in to configure this Mac for your profile.").foregroundStyle(.secondary)
                }
            }.tabItem { Label("This Mac", systemImage: "desktopcomputer") }
            AtlasUpdateSettingsView(updater: updater)
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 660, height: 640)
    }
}

private struct AtlasDesktopAISettings: View {
    @ObservedObject var accounts: AtlasAIAccounts
    var body: some View {
        Form {
            Section {
                NavigationLink("Claude") { AtlasClaudeAccountView(accounts: accounts) }
                NavigationLink("ChatGPT") { AtlasChatGPTAccountView(accounts: accounts) }
            } header: { Text("AI accounts") } footer: {
                Text("Atlas uses your connected AI accounts for conversations you start with Pip. " +
                     "The conversation runs on the Atlas server, independently of the selected tool environment.")
            }
        }.formStyle(.grouped)
    }
}

struct AtlasWorkstationSettings: View {
    @ObservedObject var model: AtlasWorkstation
    @State private var draft = AtlasWorkstationConfiguration()
    @State private var screenAllowed = false
    @State private var accessibilityAllowed = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.configuration.enabled }, set: { enabled in
                    var next = draft
                    next.enabled = enabled
                    Task { await model.save(next) }
                })) {
                    Label("Use this Mac as an environment", systemImage: "desktopcomputer")
                        .font(.headline)
                }
                .accessibilityIdentifier("workstation-enabled")
                .disabled(!model.available || model.busy)
                LabeledContent("Status") {
                    Label(status, systemImage: model.connected ? "circle.fill" : "circle")
                        .foregroundStyle(model.connected ? .green : .secondary)
                }
                TextField("Name", text: $draft.name).accessibilityIdentifier("workstation-name")
                Toggle("Allow terminal and coding tools", isOn: $draft.terminal)
                    .accessibilityIdentifier("workstation-terminal")
                Text("Once enabled, commands and code edits run without asking for approval each time. " +
                     "Commands run as your macOS user, not inside a folder sandbox, for up to 30 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep this Mac awake", isOn: $draft.keepAwake)
                Text("Prevent idle sleep while this environment is enabled, including on battery power.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("This Mac") } footer: {
                Text("Sessions and AI requests run on the Atlas server and survive deployments. " +
                     "This Mac executes tools only while Atlas is open and you have enabled it. " +
                     "The environment belongs only to your profile and is available in private conversations.")
            }
            Section {
                Toggle("Home directory", isOn: $draft.home)
                folderRows(draft.folders, parentDirectories: false)
                Button("Choose projects…") { choose(parentDirectories: false) }
                    .accessibilityIdentifier("workstation-choose-projects")
                folderRows(draft.projectDirectories, parentDirectories: true)
                Button("Choose project parent directories…") { choose(parentDirectories: true) }
            } header: { Text("Where tools can work") } footer: {
                Text("Git projects use an isolated worktree per conversation, named from its title. " +
                     "Work starts from local HEAD; uncommitted files stay in the original checkout. " +
                     "Worktrees are retained when conversations are archived. " +
                     "Parent directories list their immediate Git repositories. Home includes personal files. " +
                     "Only project names are registered with Atlas; " +
                     "file contents and command output go to Atlas and your AI provider when a tool runs. " +
                     "These folder limits do not restrict terminal commands.")
            }
            Section {
                Toggle("Share this Mac’s display", isOn: .constant(false)).disabled(true)
                Text("Display tools are not available yet. " +
                     "Atlas does not request these permissions or share your screen.")
                    .font(.caption).foregroundStyle(.secondary)
                permission("Screen Recording", allowed: screenAllowed, pane: "Privacy_ScreenCapture")
                permission("Accessibility", allowed: accessibilityAllowed, pane: "Privacy_Accessibility")
            } header: { Text("macOS permissions") }
            if let message = model.message {
                Section {
                    Text(message).foregroundStyle(.red).textSelection(.enabled)
                    if !model.available { Button("Retry connection") { Task { await model.load() } } }
                }
            }
            Section {
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Save changes") { Task { await model.save(draft) } }
                        .disabled(!model.available || model.busy || draft == model.configuration)
                        .accessibilityIdentifier("workstation-save")
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.load(); draft = model.configuration; refreshPermissions() }
        .onChange(of: model.configuration) { _, value in draft = value }
        .onChange(of: phase) { _, value in if value == .active { refreshPermissions() } }
    }

    private var status: String {
        if model.busy { return "Updating…" }
        if !model.available { return "Unavailable" }
        if !model.configuration.enabled { return "Off" }
        return model.connected ? "Connected · \(model.projects.count) projects" : "Connecting…"
    }

    @ViewBuilder private func folderRows(_ folders: [AtlasWorkstationFolder], parentDirectories: Bool) -> some View {
        ForEach(folders) { folder in
            LabeledContent {
                Button("Remove", systemImage: "minus.circle") {
                    if parentDirectories {
                        draft.projectDirectories.removeAll { $0.id == folder.id }
                    } else {
                        draft.folders.removeAll { $0.id == folder.id }
                    }
                }.labelStyle(.iconOnly).buttonStyle(.borderless)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(folder.name)
                        Text(folder.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                } icon: { Image(systemName: parentDirectories ? "folder.badge.gearshape" : "folder") }
            }
        }
    }

    private func choose(parentDirectories: Bool) {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.prompt = "Choose"
        guard picker.runModal() == .OK else { return }
        let selected = picker.urls.map { AtlasWorkstationFolder(path: $0.resolvingSymlinksInPath().path) }
        if parentDirectories {
            draft.projectDirectories += selected.filter { next in
                !draft.projectDirectories.contains { $0.path == next.path }
            }
        } else {
            draft.folders += selected.filter { next in !draft.folders.contains { $0.path == next.path } }
        }
    }

    private func permission(_ name: String, allowed: Bool, pane: String) -> some View {
        LabeledContent(name) {
            Text(allowed ? "Allowed" : "Not allowed").foregroundStyle(.secondary)
            Button("Open System Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func refreshPermissions() {
        screenAllowed = CGPreflightScreenCaptureAccess()
        accessibilityAllowed = AXIsProcessTrusted()
    }
}
#endif
