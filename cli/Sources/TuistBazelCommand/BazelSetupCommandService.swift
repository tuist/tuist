import FileSystem
import Foundation
import Noora
import Path
import TuistAlert
import TuistCAS
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistREAPI
import TuistServer

private enum BazelrcImportResult {
    case added
    case alreadyImported
    case disabled
    case workspaceNotFound
    case symbolicLink
    case managedOptionsPresent
    case fileUpdateFailed
}

private struct BazelrcImportEditor {
    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming) {
        self.fileSystem = fileSystem
    }

    func add(to directoryPath: AbsolutePath) async -> BazelrcImportResult {
        let bazelrcPath = directoryPath.appending(component: ".bazelrc")
        let importLine = "try-import %workspace%/.bazelrc.tuist"

        do {
            let existingContent: String
            if isSymbolicLink(bazelrcPath) {
                return .symbolicLink
            } else if try await fileSystem.exists(bazelrcPath) {
                existingContent = try await fileSystem.readTextFile(at: bazelrcPath)
            } else {
                existingContent = ""
            }

            guard !hasBazelrcImport(existingContent) else { return .alreadyImported }
            guard !hasManagedBazelOptions(existingContent) else { return .managedOptionsPresent }

            try await fileSystem.writeText(
                insertingBazelrcImport(importLine, into: existingContent),
                at: bazelrcPath,
                encoding: .utf8,
                options: Set([.overwrite])
            )

            return .added
        } catch {
            return .fileUpdateFailed
        }
    }

    private func isSymbolicLink(_ path: AbsolutePath) -> Bool {
        guard let type = try? FileManager.default.attributesOfItem(atPath: path.pathString)[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeSymbolicLink
    }

    private func hasBazelrcImport(_ content: String) -> Bool {
        content
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let tokens = line.split(whereSeparator: \.isWhitespace)
                guard tokens.count == 2 else { return false }
                return (tokens[0] == "try-import" || tokens[0] == "import")
                    && tokens[1] == "%workspace%/.bazelrc.tuist"
            }
    }

    private func hasManagedBazelOptions(_ content: String) -> Bool {
        content
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.hasPrefix("#") else { return false }

                return trimmedLine.split(whereSeparator: \.isWhitespace).contains { token in
                    token == "--remote_cache"
                        || token.hasPrefix("--remote_cache=")
                        || token == "--bes_backend"
                        || token.hasPrefix("--bes_backend=")
                }
            }
    }

    private func insertingBazelrcImport(_ importLine: String, into content: String) -> String {
        let newline = content.contains("\r\n") ? "\r\n" : "\n"
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalizedContent.components(separatedBy: "\n")
        var insertionIndex = lines.endIndex

        while insertionIndex > lines.startIndex {
            let line = lines[lines.index(before: insertionIndex)]
            if line.trimmingCharacters(in: .whitespaces).isEmpty || isBazelrcImportDirective(line) {
                insertionIndex = lines.index(before: insertionIndex)
            } else {
                break
            }
        }

        lines.insert(importLine, at: insertionIndex)
        var result = lines.joined(separator: newline)
        if !result.hasSuffix(newline) {
            result.append(contentsOf: newline)
        }
        return result
    }

    private func isBazelrcImportDirective(_ line: String) -> Bool {
        guard let directive = line.split(whereSeparator: \.isWhitespace).first else { return false }
        return directive == "try-import" || directive == "import"
    }
}

private struct BazelSetupConfiguration {
    let endpoint: GRPCEndpoint
    let accountHandle: String
    let projectHandle: String
    let fullHandle: String
}

public struct BazelSetupCommandService {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheURLStore: CacheURLStoring
    private let remoteCacheProbeService: RemoteCacheProbing
    private let fullHandleService: FullHandleServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        remoteCacheProbeService: RemoteCacheProbing = RemoteCacheProbeService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.remoteCacheProbeService = remoteCacheProbeService
        self.fullHandleService = fullHandleService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
    }

    public func run(
        directory: String?,
        buildInsights: Bool = true,
        addBazelrcImport shouldAddBazelrcImport: Bool = true
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let canonicalDirectoryPath = try canonicalPath(directoryPath)
        let setupConfiguration = try await setupConfiguration(directoryPath: directoryPath)

        let bazelWorkspacePath = try await bazelWorkspacePath(startingAt: canonicalDirectoryPath)
        let bazelrcDirectoryPath = bazelWorkspacePath ?? canonicalDirectoryPath
        let credentialHelperPath = try await createCredentialHelperScriptIfNeeded(
            directoryPath: canonicalDirectoryPath,
            bazelrcDirectoryPath: bazelrcDirectoryPath,
            fullHandle: setupConfiguration.fullHandle
        )
        let bazelrcPath = bazelrcDirectoryPath.appending(component: BazelrcFile.name)
        let bazelrcContent = BazelrcFile.render(
            endpoint: setupConfiguration.endpoint,
            accountHandle: setupConfiguration.accountHandle,
            projectHandle: setupConfiguration.projectHandle,
            credentialHelperPath: credentialHelperPath,
            buildInsights: buildInsights
        )
        try await fileSystem.writeText(bazelrcContent, at: bazelrcPath, encoding: .utf8, options: Set([.overwrite]))

        let bazelrcImportResult =
            if !shouldAddBazelrcImport {
                BazelrcImportResult.disabled
            } else if bazelWorkspacePath != nil {
                await BazelrcImportEditor(fileSystem: fileSystem).add(to: bazelrcDirectoryPath)
            } else {
                BazelrcImportResult.workspaceNotFound
            }

        showSuccess(
            bazelrcPath: bazelrcPath,
            bazelrcImportResult: bazelrcImportResult,
            buildInsights: buildInsights
        )
    }

    private func setupConfiguration(directoryPath: AbsolutePath) async throws -> BazelSetupConfiguration {
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        guard let fullHandle = config.fullHandle else {
            throw BazelSetupCommandServiceError.missingFullHandle
        }
        let (accountHandle, projectHandle) = try fullHandleService.parse(fullHandle)
        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL) else {
            throw BazelSetupCommandServiceError.notAuthenticated
        }
        let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
        guard let host = cacheURL.host else {
            throw BazelSetupCommandServiceError.invalidCacheEndpoint(cacheURL.absoluteString)
        }
        let endpoint = GRPCEndpoint(host: host, explicitPort: cacheURL.port, isTLS: cacheURL.scheme != "http")

        try await remoteCacheProbeService.probe(
            endpoint: endpoint,
            accountHandle: accountHandle,
            instanceName: projectHandle,
            token: token.value
        )
        return BazelSetupConfiguration(
            endpoint: endpoint,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            fullHandle: fullHandle
        )
    }

    private func showSuccess(
        bazelrcPath: AbsolutePath,
        bazelrcImportResult: BazelrcImportResult,
        buildInsights: Bool
    ) {
        AlertController.current.success(
            .alert(
                "Generated \(bazelrcPath.pathString)",
                takeaways: [
                    bazelrcImportTakeaway(
                        result: bazelrcImportResult,
                        buildInsights: buildInsights
                    ),
                    "Run Bazel normally to use the Tuist remote cache\(buildInsights ? " and record build insights" : "")",
                ]
            )
        )
    }

    private func bazelrcImportTakeaway(
        result: BazelrcImportResult,
        buildInsights: Bool
    ) -> TerminalText {
        let capabilities = buildInsights ? "remote cache and build insights" : "remote cache"

        switch result {
        case .added:
            return "Added 'try-import %workspace%/.bazelrc.tuist' to your .bazelrc to enable the Tuist \(capabilities)"
        case .alreadyImported:
            return "Your .bazelrc already imports .bazelrc.tuist"
        case .disabled:
            return "Add 'try-import %workspace%/.bazelrc.tuist' to your .bazelrc to enable the Tuist \(capabilities)"
        case .workspaceNotFound:
            return "No Bazel workspace marker was found. Run setup from the workspace or import the generated file manually"
        case .symbolicLink:
            return "Your .bazelrc is a symbolic link. Add 'try-import %workspace%/.bazelrc.tuist' to its target to enable the Tuist \(capabilities)"
        case .managedOptionsPresent:
            return "Your .bazelrc already configures a remote cache or Build Event Service. Review the generated .bazelrc.tuist before importing it"
        case .fileUpdateFailed:
            return "Could not update your .bazelrc. Add 'try-import %workspace%/.bazelrc.tuist' manually to enable the Tuist \(capabilities)"
        }
    }

    private func createCredentialHelperScriptIfNeeded(
        directoryPath: AbsolutePath,
        bazelrcDirectoryPath: AbsolutePath,
        fullHandle: String
    ) async throws -> AbsolutePath {
        let credentialsDirectory = Environment.current.configDirectory.appending(component: "credentials")
        let helperName =
            "tuist-bazel-credential-helper-\(fullHandle.replacingOccurrences(of: "/", with: "-"))-\(directoryIdentifier(directoryPath: directoryPath, bazelrcDirectoryPath: bazelrcDirectoryPath))"
        let scriptPath = credentialsDirectory.appending(component: helperName)

        if try await fileSystem.exists(scriptPath) {
            return scriptPath
        }

        if !(try await fileSystem.exists(credentialsDirectory)) {
            try await fileSystem.makeDirectory(at: credentialsDirectory)
        }

        let directoryPathArgument = shellSingleQuoted(directoryPath.pathString)
        let bazelrcDirectoryPathArgument = shellSingleQuoted(bazelrcDirectoryPath.pathString)
        let relativeDirectoryPathArgument = shellSingleQuoted(directoryPath.relative(to: bazelrcDirectoryPath).pathString)
        let script = """
        #!/bin/sh
        project_path='\(directoryPathArgument)'
        bazelrc_path='\(bazelrcDirectoryPathArgument)'
        relative_project_path='\(relativeDirectoryPathArgument)'

        if [ ! -d "$project_path" ] || [ ! -f "$bazelrc_path/.bazelrc.tuist" ]; then
          workspace_path="$PWD"
          while [ "$workspace_path" != "/" ] && [ ! -f "$workspace_path/.bazelrc.tuist" ]; do
            workspace_path=${workspace_path%/*}
            [ -n "$workspace_path" ] || workspace_path=/
          done
          if [ -f "$workspace_path/.bazelrc.tuist" ]; then
            project_path="$workspace_path/$relative_project_path"
            bazelrc_path="$workspace_path"
          fi
        fi

        if [ -d "$project_path" ] && [ -f "$bazelrc_path/.bazelrc.tuist" ]; then
          exec tuist bazel credential-helper --path "$project_path" --bazelrc-path "$bazelrc_path" "$@"
        else
          exec tuist bazel credential-helper "$@"
        fi

        """
        try await fileSystem.writeText(script, at: scriptPath)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.pathString
        )
        return scriptPath
    }

    private func shellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func directoryIdentifier(
        directoryPath: AbsolutePath,
        bazelrcDirectoryPath: AbsolutePath
    ) -> String {
        let identity = directoryPath.pathString + "\0" + bazelrcDirectoryPath.pathString
        let hash = identity.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func canonicalPath(_ path: AbsolutePath) throws -> AbsolutePath {
        try AbsolutePath(validating: URL(fileURLWithPath: path.pathString).resolvingSymlinksInPath().path)
    }

    private func bazelWorkspacePath(startingAt directoryPath: AbsolutePath) async throws -> AbsolutePath? {
        var candidate = directoryPath
        let markers = ["MODULE.bazel", "REPO.bazel", "WORKSPACE.bazel", "WORKSPACE"]

        while true {
            for marker in markers where try await fileSystem.exists(candidate.appending(component: marker)) {
                return candidate
            }

            if try await fileSystem.exists(candidate.appending(component: ".git")) {
                return nil
            }

            let parent = candidate.parentDirectory
            guard parent != candidate else { return nil }
            candidate = parent
        }
    }
}

public enum BazelSetupCommandServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case missingFullHandle
    case invalidCacheEndpoint(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return
                "You are not authenticated. Refer to the documentation for authentication options: https://tuist.dev/en/docs/guides/server/authentication"
        case .missingFullHandle:
            return
                "The project full handle is required. Set 'project' in your tuist.toml or 'fullHandle' in your Tuist.swift."
        case let .invalidCacheEndpoint(endpoint):
            return "The cache endpoint \(endpoint) is invalid."
        }
    }
}
