import SwiftUI

struct AtlasWorkspaceView<Profile: View>: View {
    let holidayRequest: ([String: Any]) async throws -> Data
    let businessRequest: ([String: Any]) async throws -> Data
    var presence: AtlasPresence?
    @ObservedObject var navigation: AtlasNavigation
    @ViewBuilder var settings: () -> Profile
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if #available(iOS 18, *) {
                tabs.tabViewStyle(.sidebarAdaptable)
            } else {
                tabs
            }
        }
        .environment(\.atlasPresence, presence)
        .environment(\.atlasNavigation, navigation)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let presence { AtlasAlsoHere(presence: presence).padding(.horizontal) }
        }
        .onAppear { presence?.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in presence?.setActive(phase == .active) }
        .onDisappear { presence?.setActive(false) }
    }

    private var tabs: some View {
        TabView(selection: $navigation.selection) {
            ForEach(AtlasBusinessResource.allCases) { resource in
                AtlasBusinessStack(resource: resource, recordID: navigation.destinations[resource.rawValue]?.recordID,
                                   revision: navigation.revisions[resource.rawValue], request: businessRequest)
                    .tabItem { Label(resource.title, systemImage: resource.icon) }
                    .tag(resource.rawValue)
            }
            AtlasBrowseStack(screen: navigation.destinations["browse"]?.screen, revision: navigation.revisions["browse"],
                             holidayRequest: holidayRequest, businessRequest: businessRequest)
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }.tag("browse")
            NavigationStack { settings().onAppear { presence?.show(resource: "profile") } }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag("profile")
        }
    }
}

private struct AtlasBrowseStack: View {
    let holidayRequest: ([String: Any]) async throws -> Data
    let businessRequest: ([String: Any]) async throws -> Data
    @State private var path: [String]
    let screen: String?
    let revision: UUID?
    @Environment(\.atlasPresence) private var presence

    init(screen: String?, revision: UUID?, holidayRequest: @escaping ([String: Any]) async throws -> Data,
         businessRequest: @escaping ([String: Any]) async throws -> Data) {
        self.screen = screen
        self.revision = revision
        self.holidayRequest = holidayRequest
        self.businessRequest = businessRequest
        _path = State(initialValue: screen.map { ["time-off", "people"].contains($0) ? [$0] : [] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            AtlasBrowsePage(group: nil, holidayRequest: holidayRequest, businessRequest: businessRequest)
                .navigationDestination(for: String.self) { screen in
                    if screen == "time-off" {
                        AtlasTimeOffView(title: AtlasCatalog().sections.first { $0.screen == "time-off" }?.title ?? "Time off",
                                         request: holidayRequest)
                            .onAppear { presence?.show(resource: "time_off") }
                    } else if screen == "people", let presence {
                        AtlasPeopleView(presence: presence)
                    }
                }
        }
        .onChange(of: revision) { _, _ in path = screen.map { [$0] } ?? [] }
    }
}

private struct AtlasBrowsePage: View {
    let group: AtlasGroup?
    let holidayRequest: ([String: Any]) async throws -> Data
    let businessRequest: ([String: Any]) async throws -> Data
    private let catalog = AtlasCatalog()
    @State private var query = ""
    @Environment(\.atlasPresence) private var presence

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
        .onAppear { presence?.show() }
    }

    private func destination(_ section: AtlasSection, searching: Bool = false) -> some View {
        NavigationLink {
            if section.screen == "people", let presence {
                AtlasPeopleView(presence: presence)
            } else if section.screen == "time-off" {
                AtlasTimeOffView(title: section.title, request: holidayRequest)
                    .onAppear { presence?.show(resource: "time_off") }
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
