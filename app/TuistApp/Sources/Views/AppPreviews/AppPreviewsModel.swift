import Foundation
import TuistServer
import TuistSupport

struct AppPreviewsKey: AppStorageKey {
    static let key = "appPreviews"
    static let defaultValue: [AppPreview] = []
}

enum AppPreviewsModelError: FatalError, Equatable {
    case previewNotFound(String)

    var type: ErrorType {
        switch self {
        case .previewNotFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .previewNotFound(displayName):
            return "Latest preview for \(displayName) was not found."
        }
    }
}

@Observable
final class AppPreviewsViewModel: Sendable {
    private(set) var appPreviews: [AppPreview] = []

    private let listProjectsService: ListProjectsServicing
    private let listPreviewsService: ListPreviewsServicing
    private let serverURLService: ServerURLServicing
    private let deviceService: any DeviceServicing
    private let appStorage: AppStoring

    init(
        deviceService: any DeviceServicing,
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        listPreviewsService: ListPreviewsServicing = ListPreviewsService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.deviceService = deviceService
        self.listProjectsService = listProjectsService
        self.listPreviewsService = listPreviewsService
        self.serverURLService = serverURLService
        self.appStorage = appStorage
    }

    func loadAppPreviewsFromCache() {
        appPreviews = (try? appStorage.get(AppPreviewsKey.self)) ?? []
    }

    func onAppear() async throws {
        let serverURL = serverURLService.serverURL()
        let projects = try await listProjectsService.listProjects(serverURL: serverURL)
        let listPreviewsService = listPreviewsService
        appPreviews = try await projects.concurrentMap { project in
            try await listPreviewsService.listPreviews(
                displayName: nil,
                specifier: "latest",
                page: nil,
                pageSize: nil,
                distinctField: .bundleIdentifier,
                fullHandle: project.fullName,
                serverURL: serverURL
            )
            .compactMap { preview in
                guard let bundleIdentifier = preview.bundleIdentifier else { return nil }
                return AppPreview(
                    fullHandle: project.fullName,
                    displayName: preview.displayName ?? project.fullName,
                    bundleIdentifier: bundleIdentifier
                )
            }
        }
        .flatMap { $0 }
        .sorted(by: { $0.displayName < $1.displayName })
        try? appStorage.set(AppPreviewsKey.self, value: appPreviews)
    }

    func launchAppPreview(_ appPreview: AppPreview) async throws {
        let serverURL = serverURLService.serverURL()

        let previews = try await listPreviewsService.listPreviews(
            displayName: nil,
            specifier: "latest",
            page: nil,
            pageSize: 1,
            distinctField: nil,
            fullHandle: appPreview.fullHandle,
            serverURL: serverURL
        )

        guard let preview = previews.first else { throw AppPreviewsModelError.previewNotFound(appPreview.displayName) }

        try await deviceService.launchPreview(
            with: preview.id,
            fullHandle: appPreview.fullHandle,
            serverURL: serverURL
        )
    }
}
