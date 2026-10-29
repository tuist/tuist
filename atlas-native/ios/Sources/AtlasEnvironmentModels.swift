import Combine
import Foundation

typealias AtlasEnvironmentRequest = ([String: Any]) async throws -> Data

struct AtlasEnvironmentProject: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var coding: Bool?
    var repository: String?
}

struct AtlasPersonalEnvironment: Decodable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool
    let online: Bool
    let terminal: Bool
    let display: Bool
    let projects: [AtlasEnvironmentProject]
    let provider: String?
    let providerState: String?

    var native: Bool { provider == nil || provider == "native" }
}

struct AtlasEnvironmentOverview: Decodable {
    struct Provider: Decodable, Identifiable {
        let id: String
        let name: String
    }
    let ownerId: String
    let environments: [AtlasPersonalEnvironment]
    let providers: [Provider]?
}

struct AtlasEnvironmentSelection: Decodable {
    struct Thread: Decodable {
        let id: String
        let environmentId: String?
        let environmentName: String?
        let projectId: String?
        var repository: String?
    }
    let thread: Thread
}

struct AtlasEnvironmentJob: Decodable, Identifiable, Equatable {
    let id: String
    let messageId: String
    let environmentId: String
    let environmentName: String
    let projectId: String
    let projectName: String
    let digest: String
    let command: String
    let status: String
    let output: String
    let success: Bool?
    let cancelRequested: Bool
    let progressSequence: UInt64
    let executionTimeoutSeconds: Int

    var active: Bool { ["queued", "claimed"].contains(status) }
    var phase: String {
        if cancelRequested && active { return "Stopping · waiting for \(executionTimeoutSeconds == 1800 ? "Mac" : "environment")" }
        switch status {
        case "queued": return executionTimeoutSeconds == 1800 ? "Waiting for Mac" : "Waiting for environment"
        case "claimed": return "Running on \(environmentName)"
        case "settled": return success == true ? "Completed" : "Stopped or failed"
        case "cancelled": return "Cancelled before starting"
        case "expired": return "Expired before starting"
        default: return "Outcome unknown · not retried"
        }
    }
}

enum AtlasEnvironmentCoding {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}

struct AtlasRepositorySettings: Codable, Equatable {
    var installationId: String?
    var defaultRepository: String?
}

struct AtlasRepositoryCatalog: Decodable {
    struct Installation: Decodable, Identifiable {
        let id: String
        let name: String
    }
    struct Repository: Decodable, Identifiable {
        let fullName: String
        var id: String { fullName }
    }
    let settings: AtlasRepositorySettings
    let installations: [Installation]
    let repositories: [Repository]
}

@MainActor
final class AtlasCodingRepositories: ObservableObject {
    @Published private(set) var catalog: AtlasRepositoryCatalog?
    @Published private(set) var draft = AtlasRepositorySettings()
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let request: AtlasEnvironmentRequest
    private var generation = 0

    init(request: @escaping AtlasEnvironmentRequest) { self.request = request }
    var dirty: Bool { catalog.map { draft != $0.settings } ?? false }

    func load() async {
        guard !busy else { return }
        let preserveDraft = dirty
        generation += 1
        let current = generation
        busy = true
        defer { if current == generation { busy = false } }
        do {
            var action: [String: Any] = ["action": "repositories"]
            if preserveDraft, let id = draft.installationId { action["installation_id"] = id }
            let data = try await request(action)
            let value = try AtlasEnvironmentCoding.decode(AtlasRepositoryCatalog.self, from: data)
            guard current == generation, !Task.isCancelled else { return }
            catalog = AtlasRepositoryCatalog(settings: value.settings, installations: value.installations,
                                             repositories: preserveDraft && draft.installationId == nil ? [] : value.repositories)
            if !preserveDraft { draft = value.settings }
            message = nil
        } catch { if current == generation, !Task.isCancelled { message = error.localizedDescription } }
    }

    func chooseInstallation(_ id: String?) async {
        guard !busy else { return }
        generation += 1
        let current = generation
        draft = AtlasRepositorySettings(installationId: id)
        if let catalog {
            self.catalog = AtlasRepositoryCatalog(settings: catalog.settings, installations: catalog.installations, repositories: [])
        }
        message = nil
        guard let id else { return }
        busy = true
        defer { if current == generation { busy = false } }
        do {
            let data = try await request(["action": "repositories", "installation_id": id])
            let value = try AtlasEnvironmentCoding.decode(AtlasRepositoryCatalog.self, from: data)
            guard current == generation, !Task.isCancelled else { return }
            catalog = value
        } catch { if current == generation, !Task.isCancelled { message = error.localizedDescription } }
    }

    func chooseRepository(_ name: String?) { if !busy { draft.defaultRepository = name; message = nil } }

    func save() async {
        guard !busy, catalog != nil else { return }
        let current = generation
        let submitted = draft
        busy = true
        defer { if current == generation { busy = false } }
        do {
            let data = try await request([
                "action": "update_repositories", "installation_id": submitted.installationId as Any? ?? NSNull(),
                "default_repository": submitted.defaultRepository as Any? ?? NSNull()
            ])
            let saved = try AtlasEnvironmentCoding.decode(AtlasRepositorySettings.self, from: data)
            guard current == generation, !Task.isCancelled, let catalog else { return }
            draft = saved
            self.catalog = AtlasRepositoryCatalog(settings: saved, installations: catalog.installations, repositories: catalog.repositories)
            message = "Repository settings saved. Existing conversations are unchanged."
        } catch { if current == generation, !Task.isCancelled { message = error.localizedDescription } }
    }

    func stop() { generation += 1; busy = false }
}
