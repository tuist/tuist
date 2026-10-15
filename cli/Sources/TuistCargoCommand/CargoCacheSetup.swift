import Crypto
import Foundation
import TuistCAS
import TuistServer

struct CargoCacheSetup {
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
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
            let cache = caches.appendingPathComponent("tuist/cargo-swift/\(identity)")
            try FileManager.default.createDirectory(
                at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            var environment = context.environment.filter { !$0.key.hasPrefix("TUIST_CARGO_CACHE_") }
            environment["TUIST_CARGO_CACHE_DIR"] = cache.path
            var refresh: Task<Void, Never>?
            do {
                let endpoint = try await CacheURLStore().getCacheURL(
                    for: context.reporting.serverURL,
                    accountHandle: context.reporting.handle.split(separator: "/").first.map(String.init)
                )
                let service = GetCacheTokenService()
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
