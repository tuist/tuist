#if os(macOS)
    import AppKit
    import SwiftUI

    /// What `luft-runner status` and its other commands print.
    struct RunnerReport: Decodable, Equatable {
        struct Config: Decodable, Equatable {
            var name: String
            var folders: [String]
            var newProjectFolder: String
            var shareDisplay: Bool
            var allowTerminal: Bool
            var allowPortals: Bool
            var keepAwake: Bool
        }

        /// The server this runner connects to, when it has one.
        struct Link: Decodable, Equatable {
            var server: String
            var runnerId: String
        }

        struct Status: Decodable, Equatable {
            var activity: String
            var connection: String
            var server: String?
            var keepingAwake: Bool
            var screenRecording: Bool?
            var accessibility: Bool?
        }

        var installed: Bool
        var loaded: Bool
        var current: Bool
        var running: Bool
        var status: Status?
        var config: Config
        var connection: Link?
        var configError: String?
        var displaySupported: Bool
        var log: String
    }

    /// Drives the runner daemon bundled beside the app's executable. The daemon
    /// owns its configuration and service installation; this only runs its
    /// commands off the main thread and shows what they print.
    @MainActor @Observable
    final class RunnerController {
        private(set) var report: RunnerReport?
        var error: String?
        private(set) var busy = false

        nonisolated static let program = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("luft-runner")

        /// The pane's periodic refresh: it neither disables the pane nor
        /// replaces an error the person hasn't dismissed.
        func refresh() async {
            await run(["status"], quiet: true)
        }

        func reset() async {
            await run(["reset"])
        }

        func setEnabled(_ enabled: Bool) async {
            await run([enabled ? "install" : "uninstall"])
        }

        func set(_ key: String, _ value: String) async {
            await run(["set", key, value])
        }

        func set(_ key: String, _ value: Bool) async {
            await run(["set", key, value ? "true" : "false"])
        }

        func requestPermissions() async {
            await run(["request-permissions"])
        }

        /// Hands the runner its server and secret. The secret goes on stdin, so no
        /// other process sees it in an argument list; the daemon keeps it private.
        /// Returns whether the daemon now holds this runner's connection.
        func connect(server: String, runnerId: String, token: String) async -> Bool {
            await run(["connect", server, runnerId], input: Data((token + "\n").utf8))
            return report?.connection?.runnerId == runnerId
        }

        func disconnect() async {
            await run(["disconnect"])
        }

        private func run(_ arguments: [String], input: Data? = nil, quiet: Bool = false) async {
            guard let program = Self.program, FileManager.default.isExecutableFile(atPath: program.path) else {
                if !quiet { error = String(localized: "This copy of Luft does not include the runner.") }
                return
            }
            if !quiet { busy = true }
            defer { if !quiet { busy = false } }
            let output = await Task.detached { () -> Data? in
                let process = Process()
                process.executableURL = program
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                let stdin = Pipe()
                process.standardInput = input == nil ? FileHandle.nullDevice : stdin
                do { try process.run() } catch { return nil }
                if let input {
                    stdin.fileHandleForWriting.write(input)
                    try? stdin.fileHandleForWriting.close()
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return data
            }.value
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // An unreadable config shows inline with Reset, not as an alert.
            if let output, let report = try? decoder.decode(RunnerReport.self, from: output) {
                self.report = report
            } else if quiet {
                return
            } else if let output, let failure = try? JSONDecoder().decode([String: String].self, from: output) {
                error = failure["error"]
            } else {
                error = String(localized: "The runner did not respond.")
            }
        }
    }

    struct SettingsView: View {
        let client: AppClient

        var body: some View {
            // One pane, so no tab bar: the pane's own header names it.
            RunnerSettingsView(client: client)
                .frame(width: 620)
                .tint(Noora.primary)
        }
    }

    struct RunnerSettingsView: View {
        let client: AppClient
        @State private var runner = RunnerController()
        @State private var connecting = false
        @State private var name = ""

        var body: some View {
            ScrollViewReader { proxy in
                form
                    // Turning the runner on adds sections below; keep the
                    // toggle and its status in view rather than the end.
                    .onChange(of: installed) { _, _ in
                        Task {
                            try? await Task.sleep(for: .milliseconds(50))
                            proxy.scrollTo("header", anchor: .top)
                        }
                    }
            }
        }

        private var form: some View {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Runner").font(.headline)
                            Text("Run threads on this Mac, and start and follow them from Luft on any of your devices.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .id("header")
                }

                if let report = runner.report {
                    service(report)
                    if let problem = report.configError {
                        Section {
                            LabeledContent {
                                Button("Reset Settings") { Task { await runner.reset() } }
                            } label: {
                                Label {
                                    Text("The runner’s settings can’t be read")
                                    Text(verbatim: problem)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                }
                            }
                        } footer: {
                            Text("Until they are fixed, the runner keeps the settings it last read, or shares nothing. Resetting shares only the projects folder, with everything else off.")
                        }
                    }
                    if report.installed {
                        connection(report)
                        permissions(report.config, displaySupported: report.displaySupported)
                        folders(report.config)
                        if report.config.shareDisplay {
                            displayAccess(report)
                        }
                        Section("All Runners") {
                            Toggle(isOn: binding(report.config.keepAwake, "keep_awake")) {
                                Text("Keep This Mac Awake")
                                Text("While plugged in and the runner is on.")
                            }
                        }
                    }
                } else if runner.error == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .formStyle(.grouped)
            // Until the runner is installed the pane is two rows, so the window
            // fits them; installed, it is a fixed height that scrolls.
            .scrollDisabled(!installed)
            .fixedSize(horizontal: false, vertical: !installed)
            .frame(height: installed ? 600 : nil)
            .disabled(runner.busy)
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { runner.error != nil }, set: { if !$0 { runner.error = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: runner.error ?? "")
            }
            // The daemon writes a heartbeat every few seconds; follow it while the pane shows.
            .task {
                while !Task.isCancelled {
                    await runner.refresh()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .onChange(of: runner.report?.config.name, initial: true) { _, value in name = value ?? "" }
        }

        private var installed: Bool { runner.report?.installed ?? false }

        private func binding(_ value: Bool, _ key: String) -> Binding<Bool> {
            Binding(get: { value }, set: { newValue in Task { await runner.set(key, newValue) } })
        }

        // MARK: Service

        @ViewBuilder private func service(_ report: RunnerReport) -> some View {
            Section {
                Toggle(isOn: Binding(
                    get: { report.installed },
                    set: { enabled in Task { await runner.setEnabled(enabled) } }
                )) {
                    Text("Run Threads on This Mac")
                    Text("Starts when you log in and keeps running when Luft is closed.")
                }
                if report.installed {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle().fill(statusColor(report)).frame(width: 8, height: 8)
                            Text(statusText(report))
                            Button {
                                Task { await runner.refresh() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh")
                        }
                    }
                    if !report.current {
                        LabeledContent {
                            Button("Use This Copy") { Task { await runner.setEnabled(true) } }
                        } label: {
                            Text("Installed from another copy of Luft")
                            Text("Use this copy so the runner updates with the app.")
                        }
                    }
                    LabeledContent("Runner Name") {
                        TextField("Runner Name", text: $name)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .onSubmit { Task { await runner.set("name", name) } }
                    }
                }
            }
        }

        // MARK: Connection

        /// Which account's threads run here. Registering creates the runner on
        /// the server for the active profile and hands its secret to the daemon.
        @ViewBuilder private func connection(_ report: RunnerReport) -> some View {
            Section("Connection") {
                if let link = report.connection {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Circle().fill(connectionColor(report)).frame(width: 8, height: 8)
                            Text(connectionText(report))
                        }
                    } label: {
                        Text("Tuist")
                        Text(verbatim: link.server)
                    }
                    if report.status?.connection == "unauthorized" {
                        LabeledContent {
                            Button("Connect Again") { Task { await connect(report) } }
                        } label: {
                            Text("Tuist no longer accepts this runner")
                            Text("It was removed, or its account lost access to threads.")
                        }
                    }
                    LabeledContent("Account") {
                        Button("Disconnect", role: .destructive) { Task { await disconnect(link) } }
                    }
                } else if let profile = client.view.active {
                    LabeledContent {
                        Button("Connect") { Task { await connect(report) } }
                            .disabled(connecting)
                    } label: {
                        Text(verbatim: profile.handle ?? profile.email ?? profile.server)
                        Text("Threads you start on any device can run on this Mac.")
                    }
                } else {
                    LabeledContent("Account") {
                        Text("Sign in to Luft to connect this Mac.").foregroundStyle(.secondary)
                    }
                }
            }
        }

        private func connect(_ report: RunnerReport) async {
            connecting = true
            defer { connecting = false }
            do {
                let created = try await client.call("register_runner", ["name": report.config.name, "platform": "macos"])
                guard let id = created["id"] as? String, let token = created["token"] as? String,
                      let server = created["server"] as? String
                else { throw AppClientError(message: String(localized: "Tuist did not register the runner.")) }
                if await !runner.connect(server: server, runnerId: id, token: token) {
                    // The daemon didn't take the secret, which is now gone:
                    // remove the registration rather than leave it unusable.
                    _ = try? await client.call("remove_runner", ["id": id])
                }
            } catch {
                runner.error = error.localizedDescription
            }
        }

        private func disconnect(_ link: RunnerReport.Link) async {
            // The daemon forgets it either way; say so when Tuist still has it.
            var removed = true
            do {
                _ = try await client.call("remove_runner", ["id": link.runnerId])
            } catch {
                removed = false
            }
            await runner.disconnect()
            if !removed {
                runner.error = String(localized: "This Mac is disconnected, but Tuist still lists the runner. Remove it while signed in to the account that connected it.")
            }
        }

        private func connectionText(_ report: RunnerReport) -> String {
            switch report.status?.connection {
            case "connected": String(localized: "Connected")
            case "unauthorized": String(localized: "Not accepted")
            case "offline": String(localized: "Offline")
            default: report.running ? String(localized: "Connecting…") : String(localized: "Stopped")
            }
        }

        private func connectionColor(_ report: RunnerReport) -> Color {
            switch report.status?.connection {
            case "connected": .green
            case "unauthorized", "offline": .orange
            default: .secondary
            }
        }

        private func statusText(_ report: RunnerReport) -> String {
            guard report.running, let status = report.status else {
                return report.loaded ? String(localized: "Starting…") : String(localized: "Stopped")
            }
            return status.activity == "busy" ? String(localized: "Running · busy") : String(localized: "Running · idle")
        }

        private func statusColor(_ report: RunnerReport) -> Color {
            report.running ? .green : (report.loaded ? .orange : .secondary)
        }

        // MARK: Permissions

        /// Portals aren't offered: nothing on the server uses them yet.
        @ViewBuilder private func permissions(_ config: RunnerReport.Config, displaySupported: Bool) -> some View {
            Section("Permissions") {
                if displaySupported {
                    permissionToggle(
                        "Share This Mac’s Display",
                        detail: "Threads can see and control this Mac’s screen.",
                        systemImage: "rectangle.inset.filled.and.person.filled",
                        color: .indigo,
                        isOn: binding(config.shareDisplay, "share_display")
                    )
                }
                permissionToggle(
                    "Allow Terminal Access",
                    detail: "Threads can run commands in a shell on this Mac.",
                    systemImage: "apple.terminal",
                    color: .gray,
                    isOn: binding(config.allowTerminal, "allow_terminal")
                )
            }
        }

        private func permissionToggle(
            _ title: LocalizedStringKey,
            detail: LocalizedStringKey,
            systemImage: String,
            color: Color,
            isOn: Binding<Bool>
        ) -> some View {
            Toggle(isOn: isOn) {
                Label {
                    Text(title)
                    Text(detail)
                } icon: {
                    Image(systemName: systemImage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(color.gradient, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }

        // MARK: Folders

        @ViewBuilder private func folders(_ config: RunnerReport.Config) -> some View {
            Section {
                ForEach(config.folders, id: \.self) { folder in
                    LabeledContent {
                        Menu {
                            Button("Show in Finder") { reveal(folder) }
                            Button("Use for New Projects") { Task { await runner.set("new_project_folder", folder) } }
                                .disabled(folder == config.newProjectFolder)
                            Divider()
                            Button("Remove", role: .destructive) { Task { await runner.set("remove_folder", folder) } }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    } label: {
                        Label {
                            Text(verbatim: displayName(folder))
                            Text(verbatim: folder)
                        } icon: {
                            Image(systemName: folder == "~" ? "house" : "folder.fill")
                                .foregroundStyle(folder == "~" ? Color.secondary : Color.blue)
                        }
                    }
                }
                LabeledContent {
                    Menu("Change…") {
                        ForEach(config.folders, id: \.self) { folder in
                            Button {
                                Task { await runner.set("new_project_folder", folder) }
                            } label: {
                                Text(verbatim: folder)
                            }
                        }
                        Divider()
                        Button("Choose Folder…") {
                            if let folder = chooseFolder() {
                                Task { await runner.set("new_project_folder", folder) }
                            }
                        }
                    }
                    .fixedSize()
                } label: {
                    Label {
                        Text("New Project Folder")
                        Text(verbatim: config.newProjectFolder)
                    } icon: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                LabeledContent("Logs") {
                    Button("Show Runner Log") { showLog() }
                }
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Folders")
                        Text("Threads started on any device can work in these.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                    Spacer()
                    Button {
                        if let folder = chooseFolder() {
                            Task { await runner.set("add_folder", folder) }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add Folder")
                }
            }
        }

        private func expanded(_ folder: String) -> String {
            (folder as NSString).expandingTildeInPath
        }

        private func displayName(_ folder: String) -> String {
            folder == "~" ? String(localized: "Home Folder") : (expanded(folder) as NSString).lastPathComponent
        }

        private func reveal(_ folder: String) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded(folder))])
        }

        private func chooseFolder() -> String? {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "Choose")
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return url.path
        }

        private func showLog() {
            guard let log = runner.report?.log else { return }
            let url = URL(fileURLWithPath: log)
            if FileManager.default.fileExists(atPath: log) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
            }
        }

        // MARK: Display access

        @ViewBuilder private func displayAccess(_ report: RunnerReport) -> some View {
            Section {
                permissionRow(
                    "Screen Recording",
                    granted: report.status?.screenRecording,
                    pane: "Privacy_ScreenCapture"
                )
                permissionRow(
                    "Accessibility",
                    granted: report.status?.accessibility,
                    pane: "Privacy_Accessibility"
                )
            } footer: {
                Text("Anyone who can write to a thread running here can see and control this display. Allow both for luft-runner.")
            }
        }

        private func permissionRow(_ title: LocalizedStringKey, granted: Bool?, pane: String) -> some View {
            LabeledContent(title) {
                HStack {
                    switch granted {
                    case true?: Text("Allowed").foregroundStyle(.secondary)
                    case false?: Text("Not Allowed").foregroundStyle(.orange)
                    case nil: Text("Unknown").foregroundStyle(.secondary)
                    }
                    if granted == false {
                        Button("Request") { Task { await runner.requestPermissions() } }
                    }
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
#endif
