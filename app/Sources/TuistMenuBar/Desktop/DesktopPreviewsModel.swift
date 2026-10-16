import Foundation
import SwiftUI
import TuistAuthentication
import TuistProjects
import TuistServer

@MainActor
@Observable
final class DesktopPreviewsModel {
    let projectContext: ProjectContext
    var projects: [ServerProject] { projectContext.projects }
    var selectedProjectFullHandle: String? { projectContext.selectedFullHandle }
    var previews: [ServerPreview] { loadedFullHandle == selectedProjectFullHandle ? items : [] }
    private var items: [ServerPreview] = []
    private var loadedFullHandle: String?
    private var requestedFullHandle: String?
    private var fetchingFullHandle: String?
    private var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMorePreviews = false
    var errorMessage: String? { previewErrorMessage ?? projectContext.errorMessage }
    private var previewErrorMessage: String?
    var searchText = ""

    var recentPreviews: [ServerPreview] {
        Array(previews.prefix(3))
    }

    var filteredPreviews: [ServerPreview] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return previews }
        return previews.filter { preview in
            [preview.displayName, preview.bundleIdentifier, preview.gitBranch, preview.gitCommitSHA]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private let listPreviewsService: ListPreviewsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private var currentPage = 1
    private var requestID = UUID()

    init(
        projectContext: ProjectContext,
        listPreviewsService: ListPreviewsServicing = ListPreviewsService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService()
    ) {
        self.projectContext = projectContext
        self.listPreviewsService = listPreviewsService
        self.serverEnvironmentService = serverEnvironmentService
    }

    func refresh() async throws {
        try await projectContext.refresh()
        try await loadSelectedProject(force: true)
    }

    func selectProject(_ fullHandle: String) async throws {
        projectContext.selectProject(fullHandle)
        try await loadSelectedProject()
    }

    func loadSelectedProject(force: Bool = false) async throws {
        let fullHandle = selectedProjectFullHandle
        guard fetchingFullHandle != fullHandle || !isLoading else { return }
        guard force || !hasLoaded || requestedFullHandle != fullHandle else { return }
        if requestedFullHandle != fullHandle { searchText = "" }
        let request = beginRequest()
        requestedFullHandle = fullHandle
        fetchingFullHandle = fullHandle
        defer {
            if requestID == request {
                fetchingFullHandle = nil
                hasLoaded = true
            }
            finishRequest(request)
        }
        guard let fullHandle else {
            items = []
            loadedFullHandle = nil
            return
        }
        do {
            try await loadFirstPage(fullHandle: fullHandle, request: request)
        } catch {
            if isCurrent(request), selectedProjectFullHandle == fullHandle {
                previewErrorMessage = error.localizedDescription
            }
            throw error
        }
    }

    func loadMore() async throws {
        guard !isLoading, !isLoadingMore, hasMorePreviews,
              let fullHandle = selectedProjectFullHandle, loadedFullHandle == fullHandle
        else { return }
        let request = requestID
        isLoadingMore = true
        defer {
            if requestID == request { isLoadingMore = false }
        }
        let page = try await fetchPage(currentPage + 1, fullHandle: fullHandle)
        guard isCurrent(request), selectedProjectFullHandle == fullHandle else { return }
        items.append(contentsOf: page.previews)
        currentPage = page.paginationMetadata.currentPage ?? currentPage + 1
        hasMorePreviews = page.paginationMetadata.hasNextPage
    }

    private func beginRequest() -> UUID {
        requestID = UUID()
        isLoading = true
        isLoadingMore = false
        previewErrorMessage = nil
        hasMorePreviews = false
        return requestID
    }

    private func finishRequest(_ request: UUID) {
        if requestID == request { isLoading = false }
    }

    private func isCurrent(_ request: UUID) -> Bool {
        requestID == request && !Task.isCancelled
    }

    private func loadFirstPage(fullHandle: String, request: UUID) async throws {
        let page = try await fetchPage(1, fullHandle: fullHandle)
        guard isCurrent(request), selectedProjectFullHandle == fullHandle else { return }
        items = page.previews
        loadedFullHandle = fullHandle
        currentPage = page.paginationMetadata.currentPage ?? 1
        hasMorePreviews = page.paginationMetadata.hasNextPage
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
