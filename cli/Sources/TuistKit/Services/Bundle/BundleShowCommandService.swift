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

enum BundleShowServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the bundle because the full handle is missing. You can pass either its value or a path to a Tuist project."
        case let .unknownError(statusCode):
            return "We could not get the bundle due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
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
        let resolvedFullHandle = fullHandle != nil ? fullHandle! : config.fullHandle

        guard let resolvedFullHandle else {
            throw BundleShowServiceError.missingFullHandle
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

        if !bundle.artifacts.isEmpty {
            info.append("")
            info.append("Artifacts".bold())
            info.append(contentsOf: formatArtifacts(bundle.artifacts))
        }

        return info.joined(separator: "\n")
    }

    private func formatArtifacts(_ artifacts: [ServerBundleArtifact], depth: Int = 0) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []

        for artifact in artifacts {
            let size = Formatters.formatBytes(artifact.size)
            lines.append("\(indent)• \(artifact.path) (\(artifact.artifactType)) - \(size)")

            if !artifact.children.isEmpty {
                lines.append(contentsOf: formatArtifacts(artifact.children, depth: depth + 1))
            }
        }

        return lines
    }
}
