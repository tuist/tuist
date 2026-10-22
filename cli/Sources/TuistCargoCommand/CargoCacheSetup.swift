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

    static func readOnlyMarker(environment: [String: String]) -> URL? {
        environment["TUIST_CARGO_CACHE_TOKEN_FILE"].map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("cache-read-only")
        }
    }

    private static func writeToken(_ token: String, file: URL) throws {
        let marker = file.deletingLastPathComponent().appendingPathComponent("cache-read-only")
        let parts = token.split(separator: ".")
        var readOnly = false
        // An advisory hint from the server-issued token; Kura still authorizes every request.
        if parts.count == 3, token.utf8.count <= 1_000_000 {
            var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            if let data = Data(base64Encoded: encoded),
               let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let grants = claims["cache_grants"] as? [String: Any],
               let project = grants["project"] as? [String: Any],
               let writes = project["write"] as? [String] { readOnly = writes.isEmpty }
        }
        if readOnly { try? Data().write(to: marker, options: .atomic) }
        try Data(token.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        if !readOnly { try? FileManager.default.removeItem(at: marker) }
    }
}
