import SwiftUI

struct AtlasWorkspaceView<Profile: View>: View {
    let holidayRequest: ([String: Any]) async throws -> Data
    let businessRequest: ([String: Any]) async throws -> Data
    @ViewBuilder var settings: () -> Profile
    @State private var selection = "tasks"

    var body: some View {
        if #available(iOS 18, *) {
            tabs.tabViewStyle(.sidebarAdaptable)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(AtlasBusinessResource.allCases) { resource in
                NavigationStack { AtlasBusinessView(resource: resource, request: businessRequest) }
                    .tabItem { Label(resource.title, systemImage: resource.icon) }
                    .tag(resource.rawValue)
            }
            NavigationStack {
                AtlasBrowsePage(group: nil, holidayRequest: holidayRequest, businessRequest: businessRequest)
            }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }.tag("browse")
            NavigationStack { settings() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag("profile")
        }
    }
}

private struct AtlasBrowsePage: View {
    let group: AtlasGroup?
    let holidayRequest: ([String: Any]) async throws -> Data
    let businessRequest: ([String: Any]) async throws -> Data
    private let catalog = AtlasCatalog()
    @State private var query = ""

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if group == nil {
                    Section("My work") { ForEach(catalog.shortcuts) { destination($0) } }
                }
                Section(group?.title ?? "Workspace") {
                    ForEach(catalog.children(of: group?.id)) { child in
                        NavigationLink {
                            AtlasBrowsePage(group: child, holidayRequest: holidayRequest, businessRequest: businessRequest)
                        } label: {
                            Label(child.title, systemImage: icon(child.id)).frame(minHeight: 44)
                        }.accessibilityIdentifier("workspace-group-\(child.id)")
                    }
                    if let group { ForEach(catalog.entries(in: group.id)) { destination($0) } }
                }
            } else {
                Section("Features") {
                    let results = catalog.search(query)
                    if results.isEmpty { ContentUnavailableView.search(text: query) }
                    ForEach(results) { destination($0, searching: true) }
                }
            }
        }
        .navigationTitle(group?.title ?? "Browse")
        .searchable(text: $query, prompt: "Find a feature")
        .autocorrectionDisabled().textInputAutocapitalization(.never)
    }

    private func destination(_ section: AtlasSection, searching: Bool = false) -> some View {
        NavigationLink {
            if section.screen == "time-off" {
                AtlasTimeOffView(title: section.title, request: holidayRequest)
            } else if let resource = AtlasBusinessResource(rawValue: section.screen) {
                AtlasBusinessView(resource: resource, request: businessRequest)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title).font(.body)
                if searching { Text(catalog.breadcrumb(for: section)).font(.caption).foregroundStyle(.secondary) }
            }.frame(minHeight: 44)
        }.accessibilityIdentifier("workspace-section-\(section.id)")
    }

    private func icon(_ id: String) -> String {
        ["overview": "checklist", "commercial": "briefcase", "sales": "building.2",
         "people": "person.2", "finance": "chart.bar"][id] ?? "folder"
    }
}
