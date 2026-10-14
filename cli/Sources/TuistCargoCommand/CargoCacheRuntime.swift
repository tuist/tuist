import Crypto
import Foundation
import Path
import TuistCAS
import TuistHTTP
import TuistServer

struct CargoCacheRuntime {
    struct Session {
        let executable: String
        let environment: [String: String]
        let refresh: Task<Void, Never>?
    }

    let process: CargoProcess

    func prepare(_ context: CargoExecutionContext, root: URL) async -> Session? {
        guard context.environment["TUIST_CARGO_INNER_WRAPPER"] == nil,
              let own = try? CargoProcess.ownExecutable() else { return nil }
        let executable = URL(fileURLWithPath: own).deletingLastPathComponent().appendingPathComponent("tuist-cargo-cache").path
        guard FileManager.default.isExecutableFile(atPath: executable),
              let protocolVersion = try? await process.capture(
                  executable, arguments: ["__tuist_protocol"], environment: context.environment, directory: context.directory
              ), protocolVersion.trimmingCharacters(in: .whitespacesAndNewlines) == "tuist-cargo-cache 1"
        else { return nil }
        do {
            let identity = SHA256
                .hash(data: Data("reapi-v1/\(context.reporting.serverURL.absoluteString)/\(context.reporting.handle.lowercased())"
                        .utf8))
                .map { String(format: "%02x", $0) }.joined()
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
            let cache = caches.appendingPathComponent("tuist/cargo/\(identity)")
            try FileManager.default.createDirectory(
                at: cache,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let metrics = root.appendingPathComponent("cache-reports")
            try FileManager.default.createDirectory(
                at: metrics,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let details = root.appendingPathComponent("cache-details")
            try FileManager.default.createDirectory(
                at: details,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var environment = context.environment.filter { !$0.key.hasPrefix("TUIST_CARGO_CACHE_") }
            environment["TUIST_CARGO_NATIVE"] = "1"
            environment["CARGO"] = context.executable
            environment["TUIST_CARGO_CACHE_DIR"] = cache.path
            environment["TUIST_CARGO_CACHE_SCHEDULER"] = "false"
            environment["TUIST_CARGO_CACHE_DISPLAY"] = "plain"
            environment["TUIST_CARGO_CACHE_LEARNED_INCREMENTAL"] = "false"
            environment["TUIST_CARGO_CACHE_INCREMENTAL"] = "true"
            environment["TUIST_CARGO_CACHE_TARGET_VIEWS"] = "false"
            environment["TUIST_CARGO_CACHE_TARGET_LANES"] = "false"
            environment["TUIST_CARGO_CACHE_TARGET_SEED"] = "false"
            environment["TUIST_CARGO_CACHE_EVENTS"] = "false"
            environment["TUIST_CARGO_CACHE_SUMMARY"] = "off"
            environment["TUIST_CARGO_CACHE_SAVINGS"] = "off"
            environment["TUIST_CARGO_CACHE_USE_ENVIRONMENT_PROXY"] = String(HTTPSettings.current.useEnvironmentProxy)
            environment["TUIST_CARGO_CACHE_CA_CERTIFICATE"] = HTTPSettings.current.caCertificatePath
            environment["TUIST_CARGO_CACHE_REPORTS"] = metrics.path
            environment["TUIST_CARGO_CACHE_PUBLIC_REPORT_DIR"] = details.path
            var refresh: Task<Void, Never>?
            do {
                let endpoint = try await CacheURLStore().getCacheURL(
                    for: context.reporting.serverURL,
                    accountHandle: context.reporting.handle.split(separator: "/").first.map(String.init)
                )
                let service = GetCacheTokenService()
                let token = try await service.getCacheToken(
                    serverURL: context.reporting.serverURL,
                    fullHandle: context.reporting.handle
                )
                let file = root.appendingPathComponent("cache-token")
                try Self.writeToken(token.token, file: file)
                environment["TUIST_CARGO_CACHE_REMOTE_URL"] = endpoint.absoluteString
                environment["TUIST_CARGO_CACHE_REMOTE_NAMESPACE"] = context.reporting.handle.lowercased()
                environment["TUIST_CARGO_CACHE_REMOTE_TOKEN_FILE"] = file.path
                refresh = Task {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: .seconds(max(1, min(60, token.expiresIn / 2))))
                            let refreshed = try await service.getCacheToken(
                                serverURL: context.reporting.serverURL,
                                fullHandle: context.reporting.handle
                            )
                            try Task.checkCancellation()
                            try Self.writeToken(refreshed.token, file: file)
                        } catch { if Task.isCancelled { return } }
                    }
                }
            } catch {
                // Remote discovery/authentication failure leaves the isolated local cache usable.
            }
            return Session(executable: executable, environment: environment, refresh: refresh)
        } catch { return nil }
    }

    private static func writeToken(_ token: String, file: URL) throws {
        try Data(token.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
