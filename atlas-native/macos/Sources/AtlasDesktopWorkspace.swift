#if os(macOS)
import SwiftUI

struct AtlasDesktopWorkspace<Profile: View>: View {
    let holidayRequest: ([String: Any]) async throws -> Data
    let businessRequest: ([String: Any]) async throws -> Data
    var presence: AtlasPresence?
    @ObservedObject var navigation: AtlasNavigation
    var automation: AtlasAuthentication?
    @ViewBuilder var settings: () -> Profile
    @State private var accounts: AtlasBusiness
    @State private var invoices: AtlasBusiness
    @State private var orbit: AtlasOrbit
    @State private var handledRevisions: [String: UUID] = [:]

    init(holidayRequest: @escaping ([String: Any]) async throws -> Data,
         businessRequest: @escaping ([String: Any]) async throws -> Data,
         orbitRequest: @escaping ([String: Any]) async throws -> Data,
         orbitLocalRequest: @escaping ([String: Any]) async throws -> Data,
         presence: AtlasPresence?, navigation: AtlasNavigation, automation: AtlasAuthentication?,
         @ViewBuilder settings: @escaping () -> Profile) {
        self.holidayRequest = holidayRequest
        self.businessRequest = businessRequest
        self.presence = presence
        self.navigation = navigation
        self.automation = automation
        self.settings = settings
        _accounts = State(initialValue: AtlasBusiness(resource: .accounts, request: businessRequest))
        _invoices = State(initialValue: AtlasBusiness(resource: .invoices, request: businessRequest))
        _orbit = State(initialValue: AtlasOrbit(request: orbitRequest, localRequest: orbitLocalRequest))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Workspace") {
                    Label("Orbit", systemImage: "bubble.left.and.bubble.right").tag("orbit")
                    ForEach(AtlasBusinessResource.allCases.filter { $0 != .tasks }) { resource in
                        Label(resource.title, systemImage: resource.icon).tag(resource.rawValue)
                    }
                    Label("Browse", systemImage: "square.grid.2x2").tag("browse")
                }
                Section {
                    Label("Profile", systemImage: "person.crop.circle").tag("profile")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Atlas")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            .accessibilityIdentifier("workspace-sidebar")
        } detail: {
            destination
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: navigation.selection) { previous, _ in
            handledRevisions[previous] = navigation.revisions[previous]
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { navigation.selection }, set: { value in
            guard let value, value != navigation.selection else { return }
            guard !navigation.hasProtectedWork else {
                navigation.message = "Finish or discard your changes before switching sections."
                return
            }
            navigation.selection = value
        })
    }

    @ViewBuilder private var destination: some View {
        switch navigation.selection {
        case "orbit":
            AtlasOrbitView(model: orbit, recordID: pendingDestination?.recordID, revision: pendingRevision)
        case "accounts", "invoices":
            AtlasBusinessStack(model: navigation.selection == "accounts" ? accounts : invoices,
                               recordID: pendingDestination?.recordID, revision: pendingRevision)
                .id(navigation.selection)
        case "profile":
            NavigationStack { settings().onAppear { presence?.show(resource: "profile") } }
                .id(navigation.revisions["profile"])
        default:
            AtlasBrowseStack(screen: pendingDestination?.screen, recordID: pendingDestination?.recordID,
                             revision: pendingRevision, holidayRequest: holidayRequest,
                             businessRequest: businessRequest, automation: automation)
        }
    }

    private var pendingRevision: UUID? {
        let revision = navigation.revisions[navigation.selection]
        return revision == handledRevisions[navigation.selection] ? nil : revision
    }

    private var pendingDestination: AtlasDestination? {
        pendingRevision == nil ? nil : navigation.destinations[navigation.selection]
    }
}
#endif
