import FileSystem
import Foundation
import Path
import TuistAlert
import TuistCAS
import TuistConfigLoader
import TuistEnvironment
import TuistHTTP
import TuistServer

public protocol BazelSetupCommandServicing {
    func run(
        directory: String?
    ) async throws
}

public struct BazelSetupCommandService: BazelSetupCommandServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheURLStore: CacheURLStoring
    private let fullHandleService: FullHandleServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        cacheURLStore: CacheURLStoring = CacheURLStore(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheURLStore = cacheURLStore
        self.fullHandleService = fullHandleService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
    }

    public func run(
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else {
            throw BazelSetupCommandServiceError.missingFullHandle
        }
        let (accountHandle, projectHandle) = try fullHandleService.parse(fullHandle)

        guard try await serverAuthenticationController.authenticationToken(serverURL: serverURL) != nil
        else {
            throw BazelSetupCommandServiceError.notAuthenticated
        }

        let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
        guard let host = cacheURL.host else {
            throw BazelSetupCommandServiceError.invalidCacheEndpoint(cacheURL.absoluteString)
        }
        let endpoint = if let port = cacheURL.port {
            "\(host):\(port)"
        } else {
            host
        }
        // Plaintext cache endpoints (e.g. local development deployments) expose
        // plaintext gRPC, while TLS endpoints terminate TLS for gRPC too.
        let remoteCacheScheme = cacheURL.scheme == "http" ? "grpc" : "grpcs"

        let credentialHelperPath = try await createCredentialHelperScriptIfNeeded()

        let bazelrcPath = directoryPath.appending(component: ".bazelrc.tuist")
        let bazelrcContent = """
        build --remote_cache=\(remoteCacheScheme)://\(endpoint)
        build --remote_header=x-tuist-account-handle=\(accountHandle)
        build --credential_helper=\(host)=\(credentialHelperPath.pathString)
        build --remote_instance_name=\(projectHandle)

        """
        try await fileSystem.writeText(bazelrcContent, at: bazelrcPath, encoding: .utf8, options: Set([.overwrite]))

        AlertController.current.success(
            .alert(
                "Generated \(bazelrcPath.pathString)",
                takeaways: [
                    "Add 'try-import %workspace%/.bazelrc.tuist' to your .bazelrc to enable the Tuist remote cache",
                ]
            )
        )
    }

    private func createCredentialHelperScriptIfNeeded() async throws -> AbsolutePath {
        let credentialsDirectory = Environment.current.configDirectory.appending(component: "credentials")
        let scriptPath = credentialsDirectory.appending(component: "tuist-bazel-credential-helper")

        if try await fileSystem.exists(scriptPath) {
            return scriptPath
        }

        if !(try await fileSystem.exists(credentialsDirectory)) {
            try await fileSystem.makeDirectory(at: credentialsDirectory)
        }

        let script = """
        #!/bin/sh
        exec tuist bazel credential-helper "$@"

        """
        try await fileSystem.writeText(script, at: scriptPath)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.pathString
        )
        return scriptPath
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
