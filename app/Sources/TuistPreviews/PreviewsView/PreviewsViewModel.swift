import Foundation
import SwiftUI
import TuistAppStorage
import TuistAuthentication
import TuistServer

struct SelectedProjectCache: Codable, Equatable {
    let serverURL: URL
    let fullHandle: String
}

struct SelectedProjectFullHandleKey: AppStorageKey {
    static let key = "selectedProjectFullHandle"
    static let defaultValue: SelectedProjectCache? = nil
}

private struct LegacySelectedProjectFullHandleKey: AppStorageKey {
    static let key = SelectedProjectFullHandleKey.key
    static let defaultValue: String? = nil
}

@Observable
final class PreviewsViewModel: Sendable {
    private let listProjectsService: ListProjectsServicing
    private let listPreviewsService: ListPreviewsServicing
    private let serverURL: URL
    private let isDefaultServerURL: Bool
    private let appStorage: AppStoring

    private(set) var projects: [ServerProject] = []
    private(set) var previews: [ServerPreview] = []
    private(set) var selectedProject: ServerProject?

    private var currentPage = 1
    private(set) var isLoadingMore = false
    private(set) var hasMorePreviews = true
    private(set) var isRefreshingPreviews = false
    private(set) var isRefreshingProjects = false
    private(set) var isInitialLoading = true

    init(
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        listPreviewsService: ListPreviewsServicing = ListPreviewsService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.listProjectsService = listProjectsService
        self.listPreviewsService = listPreviewsService
        serverURL = serverEnvironmentService.url()
        let defaultServerURL = (serverEnvironmentService as? AppServerEnvironmentConfiguring)?.defaultURL() ??
            ServerEnvironmentService().url()
        isDefaultServerURL = Self.normalizedURLString(serverURL) == Self.normalizedURLString(defaultServerURL)
        self.appStorage = appStorage
    }

    func onAppear() async throws {
        do {
            try await loadProjects()
            isInitialLoading = false
        } catch {
            isInitialLoading = false
            throw error
        }
    }

    func selectProject(_ project: ServerProject) async throws {
        selectedProject = project
        try? appStorage.set(
            SelectedProjectFullHandleKey.self,
            value: SelectedProjectCache(serverURL: serverURL, fullHandle: project.fullName)
        )
        try await loadPreviews(for: project)
    }

    private func loadPreviews(for project: ServerProject) async throws {
        currentPage = 1
        hasMorePreviews = true
        try await loadPreviewsPage(for: project, page: currentPage)
    }

    func loadMorePreviews() async throws {
        guard let selectedProject,
              !isLoadingMore,
              hasMorePreviews
        else {
            return
        }

        isLoadingMore = true
        let nextPage = currentPage + 1
        try await loadPreviewsPage(for: selectedProject, page: nextPage)
        isLoadingMore = false
    }

    func refreshPreviews() async throws {
        isRefreshingPreviews = true
        let refreshStartTime = Date()

        defer {
            // If the refresh is too fast, it can make the UI feel glitchy, so we're ensuring the loading state preserved for at
            // least 1 second
            Task {
                let elapsed = Date().timeIntervalSince(refreshStartTime)
                let remainingDelay: TimeInterval = max(0, 1.0 - elapsed)
                if remainingDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
                }
                isRefreshingPreviews = false
            }
        }

        guard let selectedProject else { return }
        do {
            try await loadPreviews(for: selectedProject)
        } catch {
            isRefreshingPreviews = false
            throw error
        }
    }

    func refreshProjects() async throws {
        isRefreshingProjects = true
        let refreshStartTime = Date()

        defer {
            // If the refresh is too fast, it can make the UI feel glitchy, so we're ensuring the loading state preserved for at
            // least 1 second
            Task {
                let elapsed = Date().timeIntervalSince(refreshStartTime)
                let remainingDelay: TimeInterval = max(0, 1.0 - elapsed)
                if remainingDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
                }
                isRefreshingProjects = false
            }
        }

        do {
            try await loadProjects()
            isRefreshingProjects = false
        } catch {
            isRefreshingProjects = false
            throw error
        }
    }

    private func loadProjects() async throws {
        projects = try await listProjectsService.listProjects(serverURL: serverURL)

        if let selectedProjectFullHandle = storedSelectedProjectFullHandle(),
           let storedProject = projects.first(where: { $0.fullName == selectedProjectFullHandle })
        {
            selectedProject = storedProject
            try await loadPreviews(for: storedProject)
        } else if let firstProject = projects.first {
            selectedProject = firstProject
            try await loadPreviews(for: firstProject)
        }
    }

    private func loadPreviewsPage(for project: ServerProject, page: Int) async throws {
        let previewsPage = try await listPreviewsService.listPreviews(
            displayName: nil,
            specifier: nil,
            supportedPlatforms: [],
            page: page,
            pageSize: 20,
            distinctField: nil,
            fullHandle: project.fullName,
            serverURL: serverURL
        )

        if previewsPage.paginationMetadata.currentPage == 1 {
            previews = previewsPage.previews
        } else {
            previews.append(contentsOf: previewsPage.previews)
        }

        currentPage = previewsPage.paginationMetadata.currentPage ?? 1
        hasMorePreviews = previewsPage.paginationMetadata.hasNextPage
    }

    private func storedSelectedProjectFullHandle() -> String? {
        do {
            guard let selectedProject = try appStorage.get(SelectedProjectFullHandleKey.self),
                  Self.normalizedURLString(selectedProject.serverURL) == Self.normalizedURLString(serverURL)
            else {
                return nil
            }
            return selectedProject.fullHandle
        } catch {
            guard isDefaultServerURL,
                  let fullHandle = try? appStorage.get(LegacySelectedProjectFullHandleKey.self)
            else {
                return nil
            }
            try? appStorage.set(
                SelectedProjectFullHandleKey.self,
                value: SelectedProjectCache(serverURL: serverURL, fullHandle: fullHandle)
            )
            return fullHandle
        }
    }

    private static func normalizedURLString(_ url: URL) -> String {
        return (try? AppServerEnvironmentService.normalizedURL(from: url.absoluteString).absoluteString) ??
            url.absoluteString
    }
}
