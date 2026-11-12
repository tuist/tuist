import SwiftUI

private struct PreviewProject: Decodable, Identifiable, Hashable {
    let full_name: String
    var id: String { full_name }
}

struct AppPreview: Decodable, Identifiable {
    let id: String
    let display_name: String?
    let bundle_identifier: String?
    let version: String?
    let git_branch: String?
    let git_commit_sha: String?
    let track: String?
    let release_notes: String?
    let inserted_at: String
    let url: String
    let device_url: String?
    let supported_platforms: [String]
    let builds: [Build]

    struct Build: Decodable { let type: String; let supported_platforms: [String]; let url: String }
    var title: String { display_name ?? bundle_identifier ?? "Tuist Preview" }
    var notesSummary: String? { release_notes?.split(whereSeparator: \.isNewline).first.map(String.init) }
    var installURL: URL? {
        guard builds.contains(where: { $0.type == "ipa" && $0.supported_platforms.contains("ios") }),
              let text = device_url, let url = URL(string: text), url.scheme == "itms-services",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.first(where: { $0.name == "action" })?.value == "download-manifest",
              let manifest = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let target = URL(string: manifest), target.scheme == "https", target.host != nil,
              target.user == nil, target.password == nil else { return nil }
        return url
    }
}

struct PreviewsView: View {
    @ObservedObject var client: AppClient
    @State private var projects: [PreviewProject] = []
    @State private var project = ""
    @State private var previews: [AppPreview] = []
    @State private var tracks: [(String, Int)] = []
    @State private var total: Int?
    @State private var track: String?
    @State private var search = ""
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var supportsFilters = true
    @State private var requestID = UUID()
    @State private var trackRequestID = UUID()

    var body: some View {
        List {
            if !projects.isEmpty {
                Section {
                    Picker("Apps in", selection: $project) {
                        ForEach(projects) { Text(verbatim: $0.full_name).tag($0.full_name) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tracks").font(.headline)
                        ScrollView(.horizontal) {
                            HStack {
                                trackButton(String(localized: "All"), value: nil, count: total)
                                ForEach(tracks, id: \.0) { name, count in trackButton(name, value: name, count: count) }
                            }
                        }.scrollIndicators(.hidden)
                        if !supportsFilters {
                            Text("Tracks are unavailable. You can still browse all previews.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if loading && previews.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if previews.isEmpty {
                ContentUnavailableView {
                    Label(projects.isEmpty ? "No Tuist projects found" : "No previews found", systemImage: "square.stack.3d.up")
                } description: {
                    Text(search.isEmpty && track == nil ? "Pull down to refresh your previews." : "Try a different search or select another track.")
                }
            } else {
                ForEach(previews) { preview in
                    NavigationLink {
                        PreviewDetailView(client: client, project: project, preview: preview)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: preview.title).font(.headline)
                            HStack {
                                if let version = preview.version { Text(verbatim: version) }
                                if let commit = preview.git_commit_sha { Text(verbatim: String(commit.prefix(7))).monospaced() }
                                if let track = preview.track { Text(verbatim: track).foregroundStyle(.purple) }
                            }.font(.caption).foregroundStyle(.secondary)
                            if let notes = preview.notesSummary { Text(verbatim: notes).font(.subheadline).lineLimit(1) }
                        }.padding(.vertical, 4)
                    }
                }
                if hasMore {
                    Button("Load more") { Task { await load(nextPage: page + 1) } }.disabled(loading)
                }
            }
        }
        .navigationTitle("Previews")
        .searchable(text: $search, prompt: "Search previews")
        .task(id: client.view.generation) { await reloadProjects() }
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(300)); await load(nextPage: 1) }
            catch {}
        }
        .onChange(of: search) { _, _ in requestID = UUID() }
        .onChange(of: project) { _, _ in
            requestID = UUID(); trackRequestID = UUID()
            track = nil; search = ""; previews = []
            tracks = []; total = nil
            Task { await reloadTracks(); await load(nextPage: 1) }
        }
        .refreshable {
            if projects.isEmpty { await reloadProjects() }
            else { await reloadTracks(); await load(nextPage: 1) }
        }
    }

    private func trackButton(_ title: String, value: String?, count: Int?) -> some View {
        Button {
            requestID = UUID()
            track = value
            Task { await load(nextPage: 1) }
        } label: {
            Text(verbatim: title + (count.map { " (\($0))" } ?? ""))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(track == value ? Color.white : Color.primary)
                .background(track == value ? Color.purple : Color.secondary.opacity(0.12), in: Capsule())
        }.buttonStyle(.plain).disabled(value != nil && !supportsFilters)
    }

    private func reloadProjects() async {
        requestID = UUID()
        projects = []; previews = []; tracks = []; total = nil; project = ""; track = nil; search = ""
        let generation = client.view.generation
        loading = true
        do {
            let data = try await client.call("projects")
            guard generation == client.view.generation, !Task.isCancelled else { return }
            projects = try decode([PreviewProject].self, data["projects"] ?? [])
            project = projects.first?.full_name ?? ""
            if project.isEmpty { loading = false }
        } catch {
            if generation == client.view.generation, !Task.isCancelled { loading = false; client.error = error.localizedDescription }
        }
    }

    private func reloadTracks() async {
        guard !project.isEmpty else { return }
        let ticket = UUID()
        trackRequestID = ticket
        let selected = project
        let generation = client.view.generation
        do {
            let data = try await client.call("tracks", ["project": selected])
            guard ticket == trackRequestID, selected == project, generation == client.view.generation, !Task.isCancelled else { return }
            supportsFilters = data["unsupported"] as? Bool != true
            total = data["total_count"] as? Int
            tracks = (data["tracks"] as? [[String: Any]] ?? []).compactMap {
                guard let name = $0["name"] as? String, let count = $0["count"] as? Int else { return nil }
                return (name, count)
            }
        } catch {
            if ticket == trackRequestID, selected == project, generation == client.view.generation, !Task.isCancelled {
                tracks = []; total = nil; supportsFilters = false; track = nil
            }
        }
    }

    private func load(nextPage: Int) async {
        guard !project.isEmpty, !Task.isCancelled else { return }
        let id = UUID()
        requestID = id
        let generation = client.view.generation
        let args: [String: Any] = ["project": project, "track": track as Any? ?? NSNull(),
                                   "search": search, "page": nextPage, "page_size": 20]
        loading = true
        do {
            let data = try await client.call("previews", args)
            guard id == requestID, generation == client.view.generation, !Task.isCancelled else { return }
            let rows = try decode([AppPreview].self, data["previews"] ?? [])
            if nextPage == 1 { previews = rows }
            else { previews.append(contentsOf: rows.filter { row in !previews.contains { $0.id == row.id } }) }
            page = nextPage
            hasMore = (data["pagination_metadata"] as? [String: Any])?["has_next_page"] as? Bool ?? false
            loading = false
        } catch {
            if id == requestID, generation == client.view.generation, !Task.isCancelled {
                loading = false; client.error = error.localizedDescription
            }
        }
    }
}

private struct PreviewDetailView: View {
    @ObservedObject var client: AppClient
    let project: String
    @State var preview: AppPreview
    @State private var confirmingInstall = false
    @State private var confirmingDelete = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(verbatim: preview.title).font(.title2.bold())
                if let version = preview.version { LabeledContent("Version", value: version) }
                if let identifier = preview.bundle_identifier { LabeledContent("Bundle identifier", value: identifier) }
                if let track = preview.track { LabeledContent("Track", value: track) }
                if let branch = preview.git_branch { LabeledContent("Branch", value: branch) }
                if let commit = preview.git_commit_sha { LabeledContent("Commit", value: commit) }
                LabeledContent("Created", value: preview.inserted_at)
                LabeledContent("Platforms", value: preview.supported_platforms.joined(separator: ", "))
            }
            if let notes = preview.release_notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Release notes") { Text(verbatim: notes).textSelection(.enabled) }
            }
            Section {
                #if os(iOS)
                    if preview.installURL != nil {
                        Button("Install preview") { confirmingInstall = true }
                    }
                #endif
                if let url = URL(string: preview.url), url.scheme == "https" {
                    Link("Open on web", destination: url)
                    ShareLink(item: url) { Label("Share preview", systemImage: "square.and.arrow.up") }
                }
                Button("Delete preview", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(Text(verbatim: preview.title))
        .task {
            let generation = client.view.generation
            do {
                let data = try await client.call("preview", ["project": project, "id": preview.id])
                guard generation == client.view.generation, !Task.isCancelled else { return }
                preview = try decode(AppPreview.self, data)
            } catch { if generation == client.view.generation, !Task.isCancelled { client.error = error.localizedDescription } }
        }
        .confirmationDialog("Install preview?", isPresented: $confirmingInstall, titleVisibility: .visible) {
            Button("Install preview") {
                if let url = preview.installURL { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only install previews from people you trust.") }
        .confirmationDialog("Delete preview?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do { _ = try await client.call("delete_preview", ["project": project, "id": preview.id]); dismiss() }
                    catch { client.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
}
