import Crypto
import FileSystem
import Foundation
import TuistCAS
import TuistServer
#if os(Linux)
    import TuistCoreCache
#else
    import TuistCore
#endif

struct CargoCacheSetup {
    private let cacheDirectoriesProvider: any CacheDirectoriesProviding
    private let fileSystem: any FileSysteming
    private let cacheURLStore: any CacheURLStoring
    private let getCacheTokenService: any GetCacheTokenServicing

    init(
        cacheDirectoriesProvider: any CacheDirectoriesProviding = CacheDirectoriesProvider(),
        fileSystem: any FileSysteming = FileSystem(),
        cacheURLStore: any CacheURLStoring = CacheURLStore(),
        getCacheTokenService: any GetCacheTokenServicing = GetCacheTokenService()
    ) {
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.fileSystem = fileSystem
        self.cacheURLStore = cacheURLStore
        self.getCacheTokenService = getCacheTokenService
    }

    struct Session {
        let environment: [String: String]
        let refresh: Task<Void, Never>?
    }

    func prepare(_ context: CargoExecutionContext, root: URL) async -> Session? {
        guard context.environment["TUIST_CARGO_INNER_WRAPPER"] == nil else { return nil }
        do {
            let identity = SHA256.hash(data: Data(
                "swift-cargo-v1/\(context.reporting.serverURL.absoluteString)/\(context.reporting.handle.lowercased())".utf8
            )).map { String(format: "%02x", $0) }.joined()
            let path = try cacheDirectoriesProvider.cacheDirectory(for: .cargo).appending(component: identity)
            try await fileSystem.makeDirectory(at: path)
            try? await SupportCachePruner(cacheDirectoriesProvider: cacheDirectoriesProvider, fileSystem: fileSystem).prune()
            let cache = URL(fileURLWithPath: path.pathString)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path)
            var environment = context.environment.filter { !$0.key.hasPrefix("TUIST_CARGO_CACHE_") }
            environment["TUIST_CARGO_CACHE_DIR"] = cache.path
            var refresh: Task<Void, Never>?
            do {
                let endpoint = try await cacheURLStore.getCacheURL(
                    for: context.reporting.serverURL,
                    accountHandle: context.reporting.handle.split(separator: "/").first.map(String.init)
                )
                let service = getCacheTokenService
                let token = try await service.getCacheToken(
                    serverURL: context.reporting.serverURL, fullHandle: context.reporting.handle
                )
                let file = root.appendingPathComponent("cache-token")
                try Self.writeToken(token.token, file: file)
                environment["TUIST_CARGO_CACHE_REMOTE_URL"] = endpoint.absoluteString
                environment["TUIST_CARGO_CACHE_NAMESPACE"] = context.reporting.handle.lowercased()
                environment["TUIST_CARGO_CACHE_TOKEN_FILE"] = file.path
                if environment["GITHUB_ACTIONS"] == "true", environment["GITHUB_EVENT_NAME"] == "push",
                   environment["GITHUB_REF_TYPE"] == "branch", environment["GITHUB_REF_PROTECTED"] == "true"
                {
                    environment["TUIST_CARGO_CACHE_UPLOAD"] = "1"
                }
                refresh = Task {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: .seconds(max(1, min(60, token.expiresIn / 2))))
                            let refreshed = try await service.getCacheToken(
                                serverURL: context.reporting.serverURL, fullHandle: context.reporting.handle
                            )
                            try Task.checkCancellation()
                            try Self.writeToken(refreshed.token, file: file)
                        } catch { if Task.isCancelled { return } }
                    }
                }
            } catch {}
            return Session(environment: environment, refresh: refresh)
        } catch { return nil }
    }

    private static func writeToken(_ token: String, file: URL) throws {
        try Data(token.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
