import Foundation
import SwiftUI
import TuistAuthentication
import TuistProjects
import TuistServer

@MainActor
@Observable
public final class PreviewsViewModel {
    public let projectContext: ProjectContext
    private let listPreviewsService: ListPreviewsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private var items: [ServerPreview] = []
    private var loadedFullHandle: String?
    private var requestedFullHandle: String?
    private var fetchingFullHandle: String?
    private var requestID = UUID()
    private var currentPage = 1
    private var hasLoaded = false

    public var projects: [ServerProject] { projectContext.projects }
    public var selectedProject: ServerProject? { projectContext.selectedProject }
    var previews: [ServerPreview] { loadedFullHandle == projectContext.selectedFullHandle ? items : [] }
    public var recentPreviews: [ServerPreview] {
        Array(previews.prefix(5))
    }

    private(set) var isLoadingMore = false
    private(set) var hasMorePreviews = false
    public private(set) var isRefreshingPreviews = false
    public var isRefreshingProjects: Bool { projectContext.isLoading }
    public var isInitialLoading: Bool {
        (projectContext.isLoading && projects.isEmpty) || !hasLoaded
    }

    public init(
        projectContext: ProjectContext,
        listPreviewsService: ListPreviewsServicing = ListPreviewsService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService()
    ) {
        self.projectContext = projectContext
        self.listPreviewsService = listPreviewsService
        self.serverEnvironmentService = serverEnvironmentService
    }

    public func onAppear() async throws {
        try await projectContext.load()
        try await loadSelectedProject()
    }

    public func selectProject(_ project: ServerProject) async throws {
        projectContext.selectProject(project.fullName)
        try await loadSelectedProject()
    }

    public func loadSelectedProject(force: Bool = false) async throws {
        let fullHandle = projectContext.selectedFullHandle
        guard fetchingFullHandle != fullHandle || !isRefreshingPreviews else { return }
        guard force || !hasLoaded || requestedFullHandle != fullHandle else { return }
        let request = UUID()
        requestID = request
        if requestedFullHandle != fullHandle { hasLoaded = false }
        requestedFullHandle = fullHandle
        isLoadingMore = false
        hasMorePreviews = false
        fetchingFullHandle = fullHandle
        isRefreshingPreviews = true
        defer {
            if requestID == request {
                isRefreshingPreviews = false
                fetchingFullHandle = nil
                hasLoaded = true
            }
        }
        guard let fullHandle else {
            items = []
            loadedFullHandle = nil
            return
        }
        let page = try await fetchPage(1, fullHandle: fullHandle)
        guard isCurrent(request, fullHandle: fullHandle) else { return }
        items = page.previews
        loadedFullHandle = fullHandle
        currentPage = page.paginationMetadata.currentPage ?? 1
        hasMorePreviews = page.paginationMetadata.hasNextPage
    }

    func loadMorePreviews() async throws {
        guard let fullHandle = projectContext.selectedFullHandle,
              loadedFullHandle == fullHandle,
              !isRefreshingPreviews, !isLoadingMore, hasMorePreviews
        else { return }
        let request = requestID
        isLoadingMore = true
        defer { if requestID == request { isLoadingMore = false } }
        let page = try await fetchPage(currentPage + 1, fullHandle: fullHandle)
        guard isCurrent(request, fullHandle: fullHandle) else { return }
        items.append(contentsOf: page.previews)
        currentPage = page.paginationMetadata.currentPage ?? currentPage + 1
        hasMorePreviews = page.paginationMetadata.hasNextPage
    }

    public func refreshPreviews() async throws {
        try await loadSelectedProject(force: true)
    }

    public func refreshProjects() async throws {
        try await projectContext.refresh()
        try await refreshPreviews()
    }

    private func isCurrent(_ request: UUID, fullHandle: String) -> Bool {
        requestID == request && projectContext.selectedFullHandle == fullHandle && !Task.isCancelled
    }

    private func fetchPage(_ page: Int, fullHandle: String) async throws -> ServerPreviewsPage {
        try await listPreviewsService.listPreviews(
            displayName: nil,
            specifier: nil,
            supportedPlatforms: [],
            page: page,
            pageSize: 20,
            distinctField: nil,
            fullHandle: fullHandle,
            serverURL: serverEnvironmentService.url()
        )
    }
}
