import SwiftUI

private struct ReleaseSummary: Decodable, Identifiable {
    let hash: String
    let title: String
    let state: String
    var id: String { hash }
}

private struct ReleaseReview: Decodable {
    struct Change: Decodable, Identifiable {
        let path: String
        let kind: String
        let before: String
        let after: String
        var id: String { path }
    }

    let hash: String
    let title: String
    let state: String
    let author: Int64
    let reviewer: Int64?
    let baseline: String?
    let created_at: String
    let active_at: String?
    let blockers: [String]
    let merge_blockers: [String]?
    let actions: [String]
    let review_changes: [Change]
    let definition_text: String
    let baseline_text: String
}

/// Presentation adapter only: the core selects actions and owns session authority.
@MainActor @Observable private final class ReleaseSurface {
    let client: AppClient
    let generation: UInt64
    private let surface = UUID().uuidString.lowercased()
    private var revision = 0
    private var pendingLoad: (String, String?)?
    var rows: [ReleaseSummary] = []
    var activeHash: String?
    var detail: ReleaseReview?
    var error: String?
    var busy = false

    init(client: AppClient, generation: UInt64) {
        self.client = client
        self.generation = generation
    }

    func load(_ operation: String, hash: String? = nil) async {
        guard client.view.generation == generation else { return }
        if busy {
            if operation == "releases" || operation == "release_open" { pendingLoad = (operation, hash) }
            return
        }
        let revision = revision
        busy = true
        detail = nil
        error = nil
        defer {
            busy = false
            if let pending = pendingLoad {
                pendingLoad = nil
                Task { await load(pending.0, hash: pending.1) }
            }
        }
        do {
            var args: [String: Any] = ["generation": generation, "surface": surface]
            if let hash { args["hash"] = hash }
            let response = try await client.call(operation, args)
            guard revision == self.revision, client.view.generation == generation, !Task.isCancelled else { return }
            let view = response["surface"] as? [String: Any] ?? [:]
            let list = view["list"] as? [String: Any] ?? [:]
            rows = try decode([ReleaseSummary].self, list["releases"] ?? [])
            activeHash = list["active"] as? String
            if let value = view["detail"] as? [String: Any] { detail = try decode(ReleaseReview.self, value) }
            error = response["error"] as? String
        } catch {
            guard revision == self.revision else { return }
            clear()
            self.error = error.localizedDescription
        }
    }

    func clear(keepList: Bool = false) {
        revision += 1
        pendingLoad = nil
        if !keepList { rows = []; activeHash = nil }
        detail = nil; error = nil
        Task { _ = try? await client.call("release_close", ["generation": generation, "surface": surface]) }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
}

/// Uses the shell's native navigation stack, never embeds another stack.
struct ReleasesView: View {
    let client: AppClient
    @State private var surface: ReleaseSurface

    init(client: AppClient) {
        self.client = client
        _surface = State(initialValue: ReleaseSurface(client: client, generation: client.view.generation))
    }

    var body: some View {
        ReleaseList(surface: surface)
            .id(surface.generation)
            .navigationTitle("Releases")
            .onChange(of: client.view.generation) {
                surface.clear()
                surface = ReleaseSurface(client: client, generation: client.view.generation)
            }
            .preference(key: RecordPresentedKey.self, value: true)
    }
}

private struct ReleaseList: View {
    let surface: ReleaseSurface
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        List {
            if let error = surface.error { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
            if let active = surface.activeHash {
                Section("Active release") { Text(verbatim: active).font(.caption.monospaced()).textSelection(.enabled) }
            }
            ForEach(surface.rows) { row in
                NavigationLink {
                    ReleaseDetail(client: surface.client, generation: surface.generation, hash: row.hash)
                } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: row.title)
                        Text(LocalizedStringKey(row.state)).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: row.hash).font(.caption.monospaced()).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if surface.rows.isEmpty, !surface.busy, surface.error == nil { Text("No releases") }
            Button("Refresh releases") { Task { await surface.load("releases") } }.disabled(surface.busy)
        }
        .overlay { if surface.busy { ProgressView("Loading releases") } }
        .task { visible = true; await surface.load("releases") }
        .onDisappear { visible = false; surface.clear(keepList: true) }
        .refreshable { await surface.load("releases") }
        .onChange(of: scenePhase) { _, phase in
            guard visible else { return }
            if phase == .background { surface.clear() }
            if phase == .active { Task { await surface.load("releases") } }
        }
    }
}

private struct ReleaseDetail: View {
    @State private var surface: ReleaseSurface
    @State private var confirmActivation = false
    let hash: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    init(client: AppClient, generation: UInt64, hash: String) {
        _surface = State(initialValue: ReleaseSurface(client: client, generation: generation))
        self.hash = hash
    }

    var body: some View {
        Form {
            if let error = surface.error { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
            if surface.client.view.generation == surface.generation, let detail = surface.detail {
                Section("Release") {
                    Text(verbatim: detail.title)
                    LabeledContent("Hash", value: detail.hash)
                    LabeledContent("State") { Text(LocalizedStringKey(detail.state)) }
                    LabeledContent("Author", value: String(detail.author))
                    LabeledContent("Reviewer", value: detail.reviewer.map(String.init) ?? "—")
                    LabeledContent("Baseline", value: detail.baseline ?? "—")
                    LabeledContent("Created", value: detail.created_at)
                    if let date = detail.active_at { LabeledContent("Activated", value: date) }
                }
                if !detail.blockers.isEmpty {
                    Section("Release blockers") {
                        ForEach(Array(detail.blockers.enumerated()), id: \.offset) { _, blocker in Text(verbatim: blocker) }
                    }
                }
                if let blockers = detail.merge_blockers, !blockers.isEmpty {
                    Section("Merge blockers") {
                        ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in Text(verbatim: blocker) }
                    }
                }
                Section("Exact changes") {
                    ForEach(detail.review_changes) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: change.path.isEmpty ? String(localized: "Definition root") : change.path)
                                .font(.headline.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                            Text(LocalizedStringKey(change.kind)).foregroundStyle(.secondary)
                            Text("Before").font(.caption.bold())
                            code(change.before)
                            Text("After").font(.caption.bold())
                            code(change.after)
                        }
                    }
                    if detail.review_changes.isEmpty { Text("No definition changes") }
                }
                Section("Full definitions") {
                    DisclosureGroup("Baseline definition") { code(detail.baseline_text) }
                    DisclosureGroup("Candidate definition") { code(detail.definition_text) }
                }
                Section {
                    ForEach(detail.actions, id: \.self) { action in
                        Button(action == "approve" ? String(localized: "Approve release") :
                            action == "merge" ? String(localized: "Merge into main") :
                            String(localized: "Activate release"))
                        {
                            if action == "activate" {
                                confirmActivation = true
                            } else {
                                Task { await surface.load("release_\(action)", hash: detail.hash) }
                            }
                        }
                        .disabled(surface.busy)
                    }
                } footer: {
                    if detail.actions.contains("approve") {
                        Text("Approval applies to this exact release. Activation is a separate step.")
                    }
                    if detail.actions.contains("merge") {
                        Text("Merging into main does not activate this release. Activation requires separate confirmation.")
                    }
                }
            }
            Button("Reload release") { Task { await surface.load("release_open", hash: hash) } }.disabled(surface.busy)
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .textSelection(.enabled)
        .navigationTitle("Release review")
        .overlay { if surface.busy { ProgressView("Loading release") } }
        .alert("Activate Release?", isPresented: $confirmActivation, presenting: surface.detail) { detail in
            Button("Cancel", role: .cancel) {}
            Button("Activate release") {
                guard !surface.busy, surface.detail?.hash == detail.hash,
                      surface.detail?.actions.contains("activate") == true else { return }
                Task { await surface.load("release_activate", hash: detail.hash) }
            }
        } message: { detail in
            Text("New invocations will use this release. Existing data may receive additive schema changes.")
                + Text("\n\n") + Text(verbatim: detail.hash)
        }
        .task(id: hash) { visible = true; await surface.load("release_open", hash: hash) }
        .onDisappear { visible = false; confirmActivation = false; surface.clear() }
        .onChange(of: surface.client.view.generation) { confirmActivation = false; surface.clear() }
        .onChange(of: scenePhase) { _, phase in
            guard visible else { return }
            if phase != .active { confirmActivation = false; surface.clear() }
            if phase == .active { Task { await surface.load("release_open", hash: hash) } }
        }
    }

    private func code(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.caption.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
