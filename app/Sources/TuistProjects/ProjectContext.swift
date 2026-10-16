import Foundation
import SwiftUI
import TuistAppStorage
import TuistAuthentication
import TuistServer

struct ProjectSelectionsKey: AppStorageKey {
    static let key = "projectSelections"
    static let defaultValue: [String: String] = [:]
}

struct RecentProjectsKey: AppStorageKey {
    static let key = "recentProjects"
    static let defaultValue: [String: [String]] = [:]
}

@MainActor
@Observable
public final class ProjectContext {
    public private(set) var projects: [ServerProject] = []
    public private(set) var selectedProject: ServerProject?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var recentFullHandles: [String] = []

    public var selectedFullHandle: String? { selectedProject?.fullName }
    public var recentProjects: [ServerProject] {
        recentFullHandles.compactMap { handle in projects.first { $0.fullName == handle } }
    }

    private let scope: String
    private let listProjectsService: ListProjectsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let appStorage: AppStoring
    private let credentialsStore: ServerCredentialsStoring
    private let cachedValueStore: CachedValueStoring
    private var hasLoaded = false
    private var requestID = UUID()

    public init(
        scope: String,
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.scope = scope
        self.listProjectsService = listProjectsService
        self.serverEnvironmentService = serverEnvironmentService
        self.appStorage = appStorage
        credentialsStore = ServerCredentialsStore.current
        cachedValueStore = CachedValueStore.current
    }

    public func load() async throws {
        guard !hasLoaded, !isLoading else { return }
        try await refresh()
    }

    public func refresh() async throws {
        let request = UUID()
        requestID = request
        isLoading = true
        errorMessage = nil
        defer { if requestID == request { isLoading = false } }
        do {
            let projects = try await ServerCredentialsStore.$current.withValue(credentialsStore) {
                try await CachedValueStore.$current.withValue(cachedValueStore) {
                    try await listProjectsService.listProjects(serverURL: serverEnvironmentService.url())
                }
            }
            guard requestID == request, !Task.isCancelled else { return }
            self.projects = projects
            recentFullHandles = ((try? appStorage.get(RecentProjectsKey.self)) ?? [:])[scope] ?? []
            let saved = ((try? appStorage.get(ProjectSelectionsKey.self)) ?? [:])[scope]
            let fullHandle = selectedFullHandle ?? saved
            selectedProject = projects.first { $0.fullName == fullHandle } ?? projects.first
            hasLoaded = true
            persistSelection()
        } catch {
            if requestID == request, !Task.isCancelled { errorMessage = error.localizedDescription }
            throw error
        }
    }

    public func selectProject(_ fullHandle: String) {
        guard let project = projects.first(where: { $0.fullName == fullHandle }) else { return }
        selectedProject = project
        persistSelection()
    }

    public func projects(matching search: String) -> [ServerProject] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? projects : projects.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    private func persistSelection() {
        var selections = (try? appStorage.get(ProjectSelectionsKey.self)) ?? [:]
        selections[scope] = selectedFullHandle
        try? appStorage.set(ProjectSelectionsKey.self, value: selections)
        if let selectedFullHandle {
            recentFullHandles = [selectedFullHandle] + recentFullHandles.filter { $0 != selectedFullHandle }
            recentFullHandles = Array(recentFullHandles.prefix(5))
        }
        var recents = (try? appStorage.get(RecentProjectsKey.self)) ?? [:]
        recents[scope] = recentFullHandles
        try? appStorage.set(RecentProjectsKey.self, value: recents)
    }
}
