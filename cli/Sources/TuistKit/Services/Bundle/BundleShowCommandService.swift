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
        fullHandle: String?,
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
        fullHandle: String?,
        bundleId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle != nil ? fullHandle! : config.fullHandle else {
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

    func formatBundleInfo(_ bundle: ServerBundle) -> String {
        var info = [
            "Bundle".bold(),
            "ID: \(bundle.id)",
            "Name: \(bundle.name)",
            "Version: \(bundle.version)",
            "App Bundle ID: \(bundle.appBundleId)",
            "Supported Platforms: \(bundle.supportedPlatforms.joined(separator: ", "))",
            "Install Size: \(Formatters.formatBytes(bundle.installSize))",
            "Download Size: \(bundle.downloadSize.map(Formatters.formatBytes) ?? "Unknown")",
            "Uploaded by: \(bundle.uploadedByAccount)",
            "Created: \(Formatters.formatDate(bundle.insertedAt))",
        ]

        if let gitBranch = bundle.gitBranch {
            info.append("Git Branch: \(gitBranch)")
        }

        if let gitCommitSha = bundle.gitCommitSha {
            info.append("Git Commit: \(gitCommitSha)")
        }

        if let gitRef = bundle.gitRef {
            info.append("Git Ref: \(gitRef)")
        }

        return info.joined(separator: "\n")
    }
}
