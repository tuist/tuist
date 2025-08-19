import Foundation
import Mockable
import Noora
import OpenAPIURLSession
import Path
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol BundleShowCommandServicing {
    func run(
        project: String?,
        bundleId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum BundleShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the bundle because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class BundleShowCommandService: BundleShowCommandServicing {
    private let getBundleService: GetBundleServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getBundleService: GetBundleServicing = GetBundleService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getBundleService = getBundleService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        bundleId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw BundleShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let bundle = try await getBundleService.getBundle(
            fullHandle: resolvedFullHandle,
            bundleId: bundleId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(bundle)
            return
        }

        let bundleInfo = formatBundleInfo(bundle)
        Noora.current.passthrough("\(bundleInfo)")
    }

    func formatBundleInfo(_ bundle: Components.Schemas.Bundle) -> String {
        var info = [
            "Bundle".bold(),
            "ID: \(bundle.id)",
            "Name: \(bundle.name)",
            "Version: \(bundle.version)",
            "App Bundle ID: \(bundle.app_bundle_id)",
            "Supported Platforms: \(bundle.supported_platforms.map(\.rawValue).joined(separator: ", "))",
            "Install Size: \(Formatters.formatBytes(bundle.install_size))",
            "Download Size: \(bundle.download_size.map(Formatters.formatBytes) ?? "Unknown")",
            "Uploaded by: \(bundle.uploaded_by_account)",
            "Created: \(Formatters.formatDate(bundle.inserted_at))",
        ]

        if let gitBranch = bundle.git_branch {
            info.append("Git Branch: \(gitBranch)")
        }

        if let gitCommitSha = bundle.git_commit_sha {
            info.append("Git Commit: \(gitCommitSha)")
        }

        if let gitRef = bundle.git_ref {
            info.append("Git Ref: \(gitRef)")
        }

        return info.joined(separator: "\n")
    }
}
