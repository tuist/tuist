import Foundation
import TuistAppStorage
import TuistAuthentication
import TuistLogging
import TuistServer
import TuistSimulator
import TuistSupport

struct AppPreviewsKey: AppStorageKey {
    static let key = "appPreviews"
    static let defaultValue: [AppPreview] = []
}

/// The server the cached previews came from, so a session on another server doesn't show them.
/// Caches written before this key existed have no server and belong to the Tuist-hosted session they were made in.
struct AppPreviewsServerURLKey: AppStorageKey {
    static let key = "appPreviewsServerURL"
    static let defaultValue: String? = nil
}

enum AppPreviewsModelError: FatalError, Equatable {
    case previewNotFound(String)
    case paginationDidNotAdvance

    var type: ErrorType {
        switch self {
        case .previewNotFound, .paginationDidNotAdvance:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .previewNotFound(displayName):
            return
                "The latest preview for \(displayName) was not found. Has any preview been published?"
        case .paginationDidNotAdvance:
            return "The server returned a preview page that did not advance. Update your server or try again."
        }
    }
}

@Observable
final class AppPreviewsViewModel: Sendable {
    private(set) var appPreviews: [AppPreview] = [] {
        didSet {
            try? appStorage.set(AppPreviewsKey.self, value: appPreviews)
            try? appStorage.set(AppPreviewsServerURLKey.self, value: serverEnvironmentService.url().absoluteString)
        }
    }

    private let listProjectsService: ListProjectsServicing
    private let listPreviewsService: ListPreviewsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let deviceService: any DeviceServicing
    private let appStorage: AppStoring

    init(
        deviceService: any DeviceServicing,
        listProjectsService: ListProjectsServicing = ListProjectsService(),
        listPreviewsService: ListPreviewsServicing = ListPreviewsService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService(),
        appStorage: AppStoring = AppStorage()
    ) {
        self.deviceService = deviceService
        self.listProjectsService = listProjectsService
        self.listPreviewsService = listPreviewsService
        self.serverEnvironmentService = serverEnvironmentService
        self.appStorage = appStorage
    }

    func loadAppPreviewsFromCache() {
        let cachedServerURL = (try? appStorage.get(AppPreviewsServerURLKey.self)) ?? nil
        guard cachedServerURL == nil || cachedServerURL == serverEnvironmentService.url().absoluteString else {
            appPreviews = []
            return
        }
        appPreviews = (try? appStorage.get(AppPreviewsKey.self)) ?? []
    }

    func onAppear() async throws {
        try await updatePreviews()
    }

    private func updatePreviews() async throws {
        let serverURL = serverEnvironmentService.url()
        let projects = try await listProjectsService.listProjects(serverURL: serverURL)
        let listPreviewsService = listPreviewsService
        appPreviews = try await projects.concurrentMap { project -> [AppPreview] in
            var previews: [ServerPreview] = []
            var seenIDs = Set<String>()
            var page = 1
            while true {
                let result = try await listPreviewsService.listPreviews(
                    displayName: nil,
                    specifier: nil,
                    track: nil,
                    supportedPlatforms: [],
                    page: page,
                    pageSize: 20,
                    distinctField: .bundleIdentifier,
                    fullHandle: project.fullName,
                    serverURL: serverURL
                )
                try Self.validatePagination(result, seenIDs: &seenIDs)
                previews.append(contentsOf: result.previews)
                guard result.paginationMetadata.hasNextPage else { break }
                page += 1
            }
            return previews.compactMap { preview in
                guard let bundleIdentifier = preview.bundleIdentifier else { return nil }
                let platformName = Self.preferredPlatformName(from: preview.supportedPlatforms)
                return AppPreview(
                    fullHandle: project.fullName,
                    displayName: preview.displayName ?? project.fullName,
                    bundleIdentifier: bundleIdentifier,
                    iconURL: preview.iconURL,
                    platformName: platformName
                )
            }
        }
        .flatMap { $0 }
        .sorted(by: { $0.displayName < $1.displayName })
    }

    private static func preferredPlatformName(from platforms: [DestinationType]) -> String? {
        for platform in platforms {
            switch platform {
            case .device(.iOS), .simulator(.iOS):
                return "iOS"
            default:
                continue
            }
        }
        return platforms.first.map(\.description)
    }

    func launchAppPreview(_ appPreview: AppPreview) async throws {
        let serverURL = serverEnvironmentService.url()

        let supportedPlatforms = [try deviceService.selectedDevice?.destinationType()].compactMap { $0 }
        // Older servers choose distinct apps before applying platform filters, so a device-only upload can hide
        // a compatible simulator build. Only fall back to history when the distinct search finds no match.
        for distinctField in [ListPreviewsDistinctField.bundleIdentifier, nil] {
            var seenIDs = Set<String>()
            var page = 1
            while true {
                let result = try await listPreviewsService.listPreviews(
                    displayName: nil,
                    specifier: nil,
                    track: nil,
                    supportedPlatforms: supportedPlatforms,
                    page: page,
                    pageSize: 20,
                    distinctField: distinctField,
                    fullHandle: appPreview.fullHandle,
                    serverURL: serverURL
                )
                try Self.validatePagination(result, seenIDs: &seenIDs)
                if let preview = result.previews.first(where: { $0.bundleIdentifier == appPreview.bundleIdentifier }) {
                    try await deviceService.launchPreview(
                        with: preview.id,
                        fullHandle: appPreview.fullHandle,
                        serverURL: serverURL
                    )
                    return
                }
                guard result.paginationMetadata.hasNextPage else { break }
                page += 1
            }
        }
        throw AppPreviewsModelError.previewNotFound(appPreview.displayName)
    }

    private static func validatePagination(_ result: ServerPreviewsPage, seenIDs: inout Set<String>) throws {
        let ids = Set(result.previews.map(\.id))
        if (!ids.isEmpty && ids.isSubset(of: seenIDs)) || (ids.isEmpty && result.paginationMetadata.hasNextPage) {
            throw AppPreviewsModelError.paginationDidNotAdvance
        }
        seenIDs.formUnion(ids)
    }
}
