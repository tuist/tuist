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

        let (remoteCache, credentialHelperHost) = try await resolveRemoteCache(
            serverURL: serverURL,
            accountHandle: accountHandle
        )

        let credentialHelperPath = try await createCredentialHelperScriptIfNeeded()

        let bazelrcPath = directoryPath.appending(component: ".bazelrc.tuist")
        let bazelrcContent = """
        build --remote_cache=\(remoteCache)
        build --remote_header=x-tuist-account-handle=\(accountHandle)
        build --credential_helper=\(credentialHelperHost)=\(credentialHelperPath.pathString)
        build --remote_instance_name=\(projectHandle)

        """
        try await fileSystem.writeText(bazelrcContent, at: bazelrcPath, encoding: .utf8, options: Set([.overwrite]))

        AlertController.current.success(
            .alert(
                "Generated \(bazelrcPath.pathString)",
                takeaways: [
                    "Bazel remote cache: \(remoteCache)",
                    "Add 'try-import %workspace%/.bazelrc.tuist' to your .bazelrc to enable the Tuist remote cache",
                ]
            )
        )
    }

    /// Resolves the gRPC remote cache endpoint for the `--remote_cache` flag and
    /// the host the credential helper should be registered for.
    ///
    /// `TUIST_CACHE_GRPC_ENDPOINT` short-circuits resolution and is used verbatim
    /// as the remote cache. Otherwise the endpoint returned by `CacheURLStore` is
    /// converted to its gRPC form: the scheme becomes `grpc` (plaintext, e.g.
    /// local development deployments) or `grpcs` (TLS), and the host is prefixed
    /// with `grpc.` — e.g. `https://acme-eu-central-1.kura.tuist.dev` becomes
    /// `grpcs://grpc.acme-eu-central-1.kura.tuist.dev`.
    private func resolveRemoteCache(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> (remoteCache: String, credentialHelperHost: String) {
        if let grpcEndpoint = Environment.current.variables["TUIST_CACHE_GRPC_ENDPOINT"] {
            guard let url = URL(string: grpcEndpoint),
                  let host = url.host,
                  url.scheme == "grpc" || url.scheme == "grpcs"
            else {
                throw BazelSetupCommandServiceError.invalidCacheEndpoint(grpcEndpoint)
            }
            return (grpcEndpoint, host)
        }

        let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
        guard let host = cacheURL.host else {
            throw BazelSetupCommandServiceError.invalidCacheEndpoint(cacheURL.absoluteString)
        }
        let grpcHost = "grpc.\(host)"
        let endpoint = if let port = cacheURL.port {
            "\(grpcHost):\(port)"
        } else {
            grpcHost
        }
        let scheme = cacheURL.scheme == "http" ? "grpc" : "grpcs"
        return ("\(scheme)://\(endpoint)", grpcHost)
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
            return
                "The cache endpoint \(endpoint) is invalid. Expected a valid URL with a host; gRPC overrides (TUIST_CACHE_GRPC_ENDPOINT) must use the grpc:// or grpcs:// scheme."
        }
    }
}
