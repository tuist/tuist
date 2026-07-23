import Foundation
import TuistAppStorage
import TuistAuthentication
import TuistLogging
import TuistServer
import TuistSimulator
import TuistSupport

struct AppPreviewsCache: Codable, Equatable {
    let serverURL: URL
    let appPreviews: [AppPreview]
}

struct AppPreviewsKey: AppStorageKey {
    static let key = "appPreviews"
    static let defaultValue: AppPreviewsCache? = nil
}

struct LegacyAppPreviewsKey: AppStorageKey {
    static let key = AppPreviewsKey.key
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
            return
                "The latest preview for \(displayName) was not found. Has any preview been published?"
        }
    }
}

@Observable
final class AppPreviewsViewModel: Sendable {
    private(set) var appPreviews: [AppPreview] = [] {
        didSet {
            try? appStorage.set(
                AppPreviewsKey.self,
                value: AppPreviewsCache(serverURL: serverURL, appPreviews: appPreviews)
            )
        }
    }

    private let listProjectsService: ListProjectsServicing
    private let listPreviewsService: ListPreviewsServicing
    private let serverURL: URL
    private let isDefaultServerURL: Bool
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
        serverURL = serverEnvironmentService.url()
        let defaultServerURL = (serverEnvironmentService as? AppServerEnvironmentConfiguring)?.defaultURL() ??
            ServerEnvironmentService().url()
        isDefaultServerURL = Self.normalizedURLString(serverURL) == Self.normalizedURLString(defaultServerURL)
        self.appStorage = appStorage
    }

    func loadAppPreviewsFromCache() {
        do {
            let cache = try appStorage.get(AppPreviewsKey.self)
            guard let cache,
                  Self.normalizedURLString(cache.serverURL) == Self.normalizedURLString(serverURL)
            else {
                appPreviews = []
                return
            }
            appPreviews = cache.appPreviews
        } catch {
            guard isDefaultServerURL else {
                appPreviews = []
                return
            }
            appPreviews = (try? appStorage.get(LegacyAppPreviewsKey.self)) ?? []
        }
    }

    func onAppear() async throws {
        try await updatePreviews()
    }

    private func updatePreviews() async throws {
        let projects = try await listProjectsService.listProjects(serverURL: serverURL)
        let listPreviewsService = listPreviewsService
        appPreviews = try await projects.concurrentMap { project in
            try await listPreviewsService.listPreviews(
                displayName: nil,
                specifier: "latest",
                supportedPlatforms: [],
                page: nil,
                pageSize: nil,
                distinctField: .bundleIdentifier,
                fullHandle: project.fullName,
                serverURL: self.serverURL
            )
            .previews
            .compactMap { preview in
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

    private static func normalizedURLString(_ url: URL) -> String {
        return (try? AppServerEnvironmentService.normalizedURL(from: url.absoluteString).absoluteString) ??
            url.absoluteString
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
        let previews = try await listPreviewsService.listPreviews(
            displayName: nil,
            specifier: "latest",
            supportedPlatforms: [try deviceService.selectedDevice?.destinationType()].compactMap { $0 },
            page: nil,
            pageSize: 1,
            distinctField: nil,
            fullHandle: appPreview.fullHandle,
            serverURL: serverURL
        )
        .previews

        guard let preview = previews.first else {
            throw AppPreviewsModelError.previewNotFound(appPreview.displayName)
        }

        try await deviceService.launchPreview(
            with: preview.id,
            fullHandle: appPreview.fullHandle,
            serverURL: serverURL
        )
    }
}
