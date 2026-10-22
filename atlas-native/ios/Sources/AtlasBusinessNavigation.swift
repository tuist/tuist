import SwiftUI

struct AtlasRecordRoute: Hashable {
    let id: String
    let identity = UUID()
}

struct AtlasBusinessStack: View {
    @StateObject private var model: AtlasBusiness
    let recordID: String?
    let revision: UUID?
    @State private var path: [AtlasRecordRoute]

    init(resource: AtlasBusinessResource, recordID: String?, revision: UUID?,
         request: @escaping ([String: Any]) async throws -> Data) {
        self.recordID = recordID
        self.revision = revision
        _model = StateObject(wrappedValue: AtlasBusiness(resource: resource, request: request))
        _path = State(initialValue: recordID.map { [AtlasRecordRoute(id: $0)] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            AtlasBusinessView(model: model, loadList: path.isEmpty)
        }
        .onChange(of: revision) { _, _ in path = recordID.map { [AtlasRecordRoute(id: $0)] } ?? [] }
    }
}

struct AtlasLinkedBusinessDetail: View {
    @ObservedObject var model: AtlasBusiness
    let id: String
    @State private var item: AtlasBusinessRecord?
    @State private var error: String?
    @State private var attempt = 0
    @Environment(\.atlasPresence) private var presence

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView {
                    Label("Record unavailable", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("destination-\(model.resource.rawValue)-\(id)-unavailable")
                } description: { Text(error) } actions: {
                    Button("Retry") { self.error = nil; attempt += 1 }
                        .accessibilityIdentifier("navigation-retry")
                }
            } else if model.forbidden {
                ContentUnavailableView("Access required", systemImage: "lock",
                                       description: Text("Ask an Atlas administrator for access."))
            } else if let item {
                AtlasBusinessDetail(model: model, original: item, reloadOnAppear: false)
            } else {
                ProgressView("Loading record").accessibilityIdentifier("navigation-loading")
            }
        }
        .navigationTitle(model.resource.singular)
        .onAppear { presence?.show(resource: model.resource.rawValue) }
        .task(id: attempt) {
            do {
                item = try await model.record(id: id)
                if model.page == nil { await model.load() }
            } catch is CancellationError {} catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
