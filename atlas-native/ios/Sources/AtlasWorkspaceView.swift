import SwiftUI

struct AtlasWorkspaceView<Settings: View>: View {
    let server: URL
    let holidayRequest: ([String: Any]) async throws -> Data
    @ViewBuilder var settings: () -> Settings
    private let catalog = AtlasCatalog()

    var body: some View {
        NavigationStack {
            AtlasWorkspacePage(catalog: catalog, group: nil, server: server, holidayRequest: holidayRequest, settings: settings)
        }
    }
}

private struct AtlasWorkspacePage<Settings: View>: View {
    let catalog: AtlasCatalog
    let group: AtlasGroup?
    let server: URL
    let holidayRequest: ([String: Any]) async throws -> Data
    @ViewBuilder var settings: () -> Settings
    @State private var query = ""

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if group == nil {
                    Section {
                        ForEach(catalog.shortcuts) { destination($0) }
                    } header: {
                        Text("My work")
                    } footer: {
                        Text(server.host() ?? "Atlas")
                    }
                }
                Section(group?.title ?? "Workspace") {
                    ForEach(catalog.children(of: group?.id)) { child in
                        NavigationLink {
                            AtlasWorkspacePage(catalog: catalog, group: child, server: server,
                                               holidayRequest: holidayRequest, settings: settings)
                        } label: {
                            Label {
                                row(child.title, description: child.description)
                            } icon: { Image(systemName: icon(child.id)).accessibilityHidden(true) }
                        }.accessibilityIdentifier("workspace-group-\(child.id)")
                    }
                    if let group {
                        ForEach(catalog.entries(in: group.id)) { destination($0) }
                    }
                }
            } else {
                let results = catalog.search(query)
                Section("Features") {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(results) { destination($0, searching: true) }
                }
            }
            Section {
                Text("Browser destinations may require separate sign-in and additional permissions. Access is checked by Atlas.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(group?.title ?? "Atlas")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a feature")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { settings() } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("workspace-settings")
            }
        }
    }

    @ViewBuilder private func destination(_ section: AtlasSection, searching: Bool = false) -> some View {
        if section.screen == "time-off" {
            NavigationLink {
                AtlasTimeOffView(title: section.title, request: holidayRequest)
            } label: { sectionRow(section, searching: searching) }
            .accessibilityIdentifier("workspace-section-\(section.id)")
        } else {
            Link(destination: section.destination(on: server)) { sectionRow(section, searching: searching) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workspace-section-\(section.id)")
        }
    }

    private func sectionRow(_ section: AtlasSection, searching: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title).font(.headline).foregroundStyle(.primary)
                if searching { Text(catalog.breadcrumb(for: section)).font(.caption).foregroundStyle(.secondary) }
                Text(section.description).font(.subheadline).foregroundStyle(.secondary)
                if section.screen == "browser" {
                    Text(section.requiredScope.isEmpty ? "Opens in browser" : "Opens in browser · Access controlled")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if section.screen == "browser" {
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }.frame(minHeight: 44).padding(.vertical, 4).contentShape(Rectangle())
    }

    private func row(_ title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(description).font(.subheadline).foregroundStyle(.secondary)
        }.frame(minHeight: 44).padding(.vertical, 4)
    }

    private func icon(_ id: String) -> String {
        [
            "overview": "chart.bar", "commercial": "briefcase", "sales": "briefcase", "outbound": "paperplane",
            "engineering": "chevron.left.forwardslash.chevron.right", "people": "person.2",
            "operations": "server.rack", "hardware": "server.rack", "library": "books.vertical", "admin": "lock.shield",
            "finance": "chart.pie", "gtm": "megaphone"
        ][id] ?? "folder"
    }
}
