import Foundation
import SwiftUI
import TuistAuthentication
import TuistProjects
import TuistServer

enum PreviewsViewModelError: LocalizedError, Equatable {
    case trackFilteringUnsupported
    case searchUnsupported

    var errorDescription: String? {
        switch self {
        case .trackFilteringUnsupported:
            "This server does not support filtering previews by track. Update your self-hosted Tuist server, or select All tracks."
        case .searchUnsupported:
            "This server does not support searching previews. Update your self-hosted Tuist server, or clear the search."
        }
    }
}

@MainActor
@Observable
public final class PreviewsViewModel {
    public let projectContext: ProjectContext
    private let listPreviewsService: ListPreviewsServicing
    private let listPreviewTracksService: ListPreviewTracksServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private var items: [ServerPreview] = []
    private var recentItems: [ServerPreview] = []
    private var recentFullHandle: String?
    private var loadedFullHandle: String?
    private var requestedFullHandle: String?
    private var requestID = UUID()
    private var currentPage = 1
    private var hasLoaded = false
    private var unfilteredTotalCount: Int?

    public var projects: [ServerProject] { projectContext.projects }
    public var selectedProject: ServerProject? { projectContext.selectedProject }
    var previews: [ServerPreview] { loadedFullHandle == projectContext.selectedFullHandle ? items : [] }
    public var recentPreviews: [ServerPreview] {
        recentFullHandle == projectContext.selectedFullHandle ? Array(recentItems.prefix(3)) : []
    }

    private(set) var selectedTrack: String?
    private(set) var trackSummary: ServerPreviewTrackSummary?
    private(set) var searchQuery = ""
    private(set) var isTrackSelectionSupported = true
    private(set) var isLoadingMore = false
    private(set) var hasMorePreviews = false
    public private(set) var isRefreshingPreviews = false
    var isLoadingPreviews: Bool { isRefreshingPreviews }
    public var isRefreshingProjects: Bool { projectContext.isLoading }
    public var isInitialLoading: Bool {
        (projectContext.isLoading && projects.isEmpty) || !hasLoaded
    }

    var availableTracks: [String] { trackSummary?.tracks.map(\.name) ?? [] }
    var totalPreviewCount: Int? { trackSummary?.totalCount ?? unfilteredTotalCount }

    func previewCount(for track: String) -> Int? {
        trackSummary?.tracks.first { $0.name.caseInsensitiveCompare(track) == .orderedSame }?.count
    }

    var trackOptions: [String] {
        var options = availableTracks
        if let selectedTrack {
            if let index = options.firstIndex(where: { $0.caseInsensitiveCompare(selectedTrack) == .orderedSame }) {
                options[index] = selectedTrack
            } else {
                options.append(selectedTrack)
            }
        }
        return options
    }

    public init(
        projectContext: ProjectContext,
        listPreviewsService: ListPreviewsServicing = ListPreviewsService(),
        listPreviewTracksService: ListPreviewTracksServicing = ListPreviewTracksService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService()
    ) {
        self.projectContext = projectContext
        self.listPreviewsService = listPreviewsService
        self.listPreviewTracksService = listPreviewTracksService
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
        let projectChanged = requestedFullHandle != fullHandle
        guard projectChanged || !isRefreshingPreviews else { return }
        guard force || !hasLoaded || projectChanged else { return }
        if projectChanged {
            hasLoaded = false
            selectedTrack = nil
            searchQuery = ""
            trackSummary = nil
            unfilteredTotalCount = nil
            isTrackSelectionSupported = true
        }
        requestedFullHandle = fullHandle
        try await loadPreviews(reloadTracks: true, refreshRecent: true)
    }

    func selectTrack(_ track: String?) async throws {
        selectedTrack = track.flatMap { $0.isEmpty ? nil : $0 }
        items = []
        try await loadPreviews()
    }

    func searchPreviews(_ query: String) async throws {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != searchQuery, selectedProject != nil else { return }
        guard query.isEmpty || isTrackSelectionSupported else { throw PreviewsViewModelError.searchUnsupported }
        searchQuery = query
        items = []
        try await loadPreviews()
    }

    private func loadPreviews(reloadTracks: Bool = false, refreshRecent: Bool = false) async throws {
        let request = UUID()
        requestID = request
        isLoadingMore = false
        hasMorePreviews = false
        isRefreshingPreviews = true
        defer {
            if requestID == request {
                isRefreshingPreviews = false
                hasLoaded = true
            }
        }
        guard let fullHandle = projectContext.selectedFullHandle else {
            items = []
            recentItems = []
            loadedFullHandle = nil
            recentFullHandle = nil
            return
        }
        do {
            try await loadPage(1, fullHandle: fullHandle, request: request)
            guard isCurrent(request, fullHandle: fullHandle) else { return }
            if refreshRecent, selectedTrack != nil || !searchQuery.isEmpty {
                let page = try await listPreviewsService.listPreviews(
                    displayName: nil, specifier: nil, track: nil, supportedPlatforms: [],
                    page: 1, pageSize: 20, distinctField: nil, fullHandle: fullHandle,
                    serverURL: serverEnvironmentService.url()
                )
                guard isCurrent(request, fullHandle: fullHandle) else { return }
                recentItems = Array(page.previews.prefix(3))
                recentFullHandle = fullHandle
                unfilteredTotalCount = page.paginationMetadata.totalCount
            }
            guard reloadTracks else { return }
            let tracks = try await listPreviewTracksService.listPreviewTracks(
                fullHandle: fullHandle, serverURL: serverEnvironmentService.url()
            )
            guard isCurrent(request, fullHandle: fullHandle) else { return }
            trackSummary = tracks
            isTrackSelectionSupported = tracks != nil
        } catch {
            guard isCurrent(request, fullHandle: fullHandle) else { return }
            throw error
        }
    }

    func loadMorePreviews() async throws {
        guard let fullHandle = projectContext.selectedFullHandle,
              loadedFullHandle == fullHandle,
              !isRefreshingPreviews, !isLoadingMore, hasMorePreviews
        else { return }
        let request = requestID
        isLoadingMore = true
        defer { if requestID == request { isLoadingMore = false } }
        do {
            try await loadPage(currentPage + 1, fullHandle: fullHandle, request: request)
        } catch {
            guard isCurrent(request, fullHandle: fullHandle) else { return }
            throw error
        }
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

    private func loadPage(_ page: Int, fullHandle: String, request: UUID) async throws {
        let previewsPage: ServerPreviewsPage
        if searchQuery.isEmpty {
            previewsPage = try await listPreviewsService.listPreviews(
                displayName: nil, specifier: nil, track: selectedTrack, supportedPlatforms: [],
                page: page, pageSize: 20, distinctField: nil, fullHandle: fullHandle,
                serverURL: serverEnvironmentService.url()
            )
        } else {
            previewsPage = try await listPreviewsService.searchPreviews(
                search: searchQuery, track: selectedTrack, page: page, pageSize: 20,
                fullHandle: fullHandle, serverURL: serverEnvironmentService.url()
            )
        }
        guard isCurrent(request, fullHandle: fullHandle) else { return }
        if let selectedTrack,
           previewsPage.previews.contains(where: { $0.track?.caseInsensitiveCompare(selectedTrack) != .orderedSame })
        {
            throw PreviewsViewModelError.trackFilteringUnsupported
        }
        if !searchQuery.isEmpty,
           previewsPage.previews.contains(where: {
               $0.displayName?.localizedCaseInsensitiveContains(searchQuery) != true
                   && $0.releaseNotes?.localizedCaseInsensitiveContains(searchQuery) != true
           })
        {
            throw PreviewsViewModelError.searchUnsupported
        }
        if selectedTrack == nil, searchQuery.isEmpty {
            unfilteredTotalCount = previewsPage.paginationMetadata.totalCount
            if page == 1 {
                recentItems = Array(previewsPage.previews.prefix(3))
                recentFullHandle = fullHandle
            }
        }
        if page == 1 {
            items = previewsPage.previews
        } else {
            items.append(contentsOf: previewsPage.previews)
        }
        loadedFullHandle = fullHandle
        currentPage = previewsPage.paginationMetadata.currentPage ?? page
        hasMorePreviews = previewsPage.paginationMetadata.hasNextPage
    }
}
