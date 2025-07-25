import Foundation
import OpenAPIURLSession
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BundleShowServicing {
    func run(
        fullHandle: String,
        bundleId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum BundleShowServiceError: Equatable, FatalError, LocalizedError {
    case missingFullHandle
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var type: TuistSupport.ErrorType {
        switch self {
        case .missingFullHandle: .abort
        case .unknownError, .notFound, .forbidden, .unauthorized: .abort
        }
    }

    var description: String {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the bundle because the full handle is missing. You can pass either its value or a path to a Tuist project."
        case let .unknownError(statusCode):
            return "We could not get the bundle due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }

    var errorDescription: String? { description }
}

final class BundleShowService: BundleShowServicing {
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
        fullHandle: String,
        bundleId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath
        if let path {
            directoryPath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }

        let config = try await configLoader.loadConfig(path: directoryPath)
        let resolvedFullHandle = fullHandle.isEmpty ? config.fullHandle : fullHandle

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
            // Create a raw response that matches the API format
            let rawBundle: [String: Any] = [
                "id": bundle.id,
                "name": bundle.name,
                "app_bundle_id": bundle.appBundleId,
                "version": bundle.version,
                "supported_platforms": bundle.supportedPlatforms,
                "install_size": bundle.installSize,
                "download_size": bundle.downloadSize as Any,
                "git_branch": bundle.gitBranch as Any,
                "git_commit_sha": bundle.gitCommitSha as Any,
                "git_ref": bundle.gitRef as Any,
                "inserted_at": Int(bundle.insertedAt.timeIntervalSince1970),
                "updated_at": Int(bundle.updatedAt.timeIntervalSince1970),
                "uploaded_by_account": bundle.uploadedByAccount,
                "artifacts": bundle.artifacts.map { artifact in
                    [
                        "artifact_type": artifact.artifactType,
                        "path": artifact.path,
                        "size": artifact.size,
                        "shasum": artifact.shasum,
                        "children": artifact.children.map { child in
                            [
                                "artifact_type": child.artifactType,
                                "path": child.path,
                                "size": child.size,
                                "shasum": child.shasum,
                                "children": [] as [[String: Any]],
                            ]
                        },
                    ]
                },
                "url": bundle.url,
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: rawBundle, options: .prettyPrinted)
            Logger.current.info(.init(stringLiteral: String(data: jsonData, encoding: .utf8)!), metadata: .json)
            return
        }

        let bundleInfo = formatBundleInfo(bundle)
        Logger.current.info("\(bundleInfo)")
    }

    private func formatBundleInfo(_ bundle: ServerBundle) -> String {
        var info = [
            "Bundle".bold(),
            "ID: \(bundle.id)",
            "Name: \(bundle.name)",
            "Version: \(bundle.version)",
            "App Bundle ID: \(bundle.appBundleId)",
            "Supported Platforms: \(bundle.supportedPlatforms.joined(separator: ", "))",
            "Install Size: \(formatBytes(bundle.installSize))",
            "Download Size: \(bundle.downloadSize.map(formatBytes) ?? "Unknown")",
            "Uploaded by: \(bundle.uploadedByAccount)",
            "Created: \(formatDate(bundle.insertedAt))",
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
            let size = formatBytes(artifact.size)
            lines.append("\(indent)• \(artifact.path) (\(artifact.artifactType)) - \(size)")

            if !artifact.children.isEmpty {
                lines.append(contentsOf: formatArtifacts(artifact.children, depth: depth + 1))
            }
        }

        return lines
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
