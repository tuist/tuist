import Foundation
import SwiftUI
import TuistServer
import TuistAppStorage

struct SelectedProjectFullHandleKey: AppStorageKey {
    static let key = "selectedProjectFullHandle"
    static let defaultValue: String? = nil
}

@Observable
final class PreviewsViewModel: Sendable {
    private let listProjectsService: ListProjectsServicing
    private let listPreviewsService: ListPreviewsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let appStorage: AppStoring

    private(set) var projects: [ServerProject] = []
    private(set) var previews: [TuistServer.Preview] = []
    var selectedProject: ServerProject?
    
    private var currentPage = 1
    private(set) var isLoadingMore = false
    private(set) var hasMorePreviews = true

    init(
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        listPreviewsService: ListPreviewsServicing = ListPreviewsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.listProjectsService = listProjectsService
        self.listPreviewsService = listPreviewsService
        self.serverEnvironmentService = serverEnvironmentService
        self.appStorage = appStorage
    }

    func onAppear() async throws {
        projects = try await listProjectsService.listProjects(serverURL: serverEnvironmentService.url())

        if let selectedProjectFullHandle = try? appStorage.get(SelectedProjectFullHandleKey.self),
           let storedProject = projects.first(where: { $0.fullName == selectedProjectFullHandle }) {
            selectedProject = storedProject
            await loadPreviews(for: storedProject)
        } else if let firstProject = projects.first {
            selectedProject = firstProject
            await loadPreviews(for: firstProject)
        }
    }
    
    func selectProject(_ project: ServerProject) async {
        selectedProject = project
        try? appStorage.set(SelectedProjectFullHandleKey.self, value: selectedProject?.fullName)
        await loadPreviews(for: project)
    }
    
    private func loadPreviews(for project: ServerProject) async {
        currentPage = 1
        hasMorePreviews = true
        await loadPreviewsPage(for: project, page: currentPage, resetList: true)
    }
    
    func loadMorePreviews() async {
        guard let selectedProject = selectedProject,
              !isLoadingMore,
              hasMorePreviews else {
            return
        }
        
        isLoadingMore = true
        let nextPage = currentPage + 1
        await loadPreviewsPage(for: selectedProject, page: nextPage, resetList: false)
        isLoadingMore = false
    }
    
    private func loadPreviewsPage(for project: ServerProject, page: Int, resetList: Bool) async {
        do {
            let newPreviews = try await listPreviewsService.listPreviews(
                displayName: nil,
                specifier: nil,
                supportedPlatforms: [],
                page: page,
                pageSize: 20,
                distinctField: nil,
                fullHandle: project.fullName,
                serverURL: serverEnvironmentService.url()
            )
            
            if resetList {
                previews = newPreviews
            } else {
                previews.append(contentsOf: newPreviews)
            }
            
            currentPage = page
            hasMorePreviews = newPreviews.count == 20
        } catch {
            if resetList {
                previews = []
            }
            hasMorePreviews = false
        }
    }
}
