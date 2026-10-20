import FileSystem
import Foundation
import Path
import TuistHTTP
import TuistServer
#if os(Linux)
    import TuistCoreCache
#else
    import TuistCore
#endif

struct CargoCacheRuntime {
    struct Session {
        let executable: String
        let environment: [String: String]
        let refresh: Task<Void, Never>?
        let keepAlive: Task<Void, Never>

        func cancel() {
            refresh?.cancel()
            keepAlive.cancel()
        }
    }

    let process: CargoProcess
    var setup = CargoCacheSetup(category: .cargoNative)
    var ownExecutable: () throws -> String = CargoProcess.ownExecutable

    func prepare(_ context: CargoExecutionContext, root: URL) async -> Session? {
        guard context.environment["TUIST_CARGO_INNER_WRAPPER"] == nil,
              let own = try? ownExecutable() else { return nil }
        let executable = URL(fileURLWithPath: own).deletingLastPathComponent().appendingPathComponent("tuist-cargo-cache").path
        guard FileManager.default.isExecutableFile(atPath: executable),
              let version = try? await process.capture(
                  executable, arguments: ["__tuist_protocol"], environment: context.environment, directory: context.directory
              ), version.trimmingCharacters(in: .whitespacesAndNewlines) == "tuist-cargo-cache 1",
              let session = await setup.prepare(context, root: root)
        else { return nil }
        do {
            let environment = try configure(session.environment, context: context, root: root)
            guard let directory = environment["TUIST_CARGO_CACHE_DIR"] else {
                throw CargoReportError(message: "Missing native Cargo cache directory.")
            }
            let path = try AbsolutePath(validating: directory)
            // The native collector owns entries and locks inside this project. Shared retention may
            // reclaim only an idle project, never a live session's lock directory.
            let keepAlive = Task<Void, Never> {
                let fileSystem = FileSystem()
                while !Task.isCancelled {
                    await fileSystem.markCacheEntryUsed(at: path)
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                }
            }
            return Session(executable: executable, environment: environment, refresh: session.refresh, keepAlive: keepAlive)
        } catch {
            session.refresh?.cancel()
            return nil
        }
    }

    private func configure(_ source: [String: String], context: CargoExecutionContext, root: URL) throws -> [String: String] {
        var environment = source
        for name in ["cache-reports", "cache-details"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        environment["TUIST_CARGO_NATIVE"] = "1"
        environment["CARGO"] = context.executable
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
        if environment["TUIST_DEBUG"] == "1" {
            environment["TUIST_CARGO_CACHE_LOG"] = "info,portable_pty=off,tuist_cargo_cache=debug,tuist_cargo_cache_core=debug"
        }
        environment["TUIST_CARGO_CACHE_USE_ENVIRONMENT_PROXY"] = String(HTTPSettings.current.useEnvironmentProxy)
        environment["TUIST_CARGO_CACHE_CA_CERTIFICATE"] = HTTPSettings.current.caCertificatePath
        environment["TUIST_CARGO_CACHE_REPORTS"] = root.appendingPathComponent("cache-reports").path
        environment["TUIST_CARGO_CACHE_PUBLIC_REPORT_DIR"] = root.appendingPathComponent("cache-details").path
        environment["TUIST_CARGO_CACHE_REMOTE_NAMESPACE"] = environment.removeValue(forKey: "TUIST_CARGO_CACHE_NAMESPACE")
        environment["TUIST_CARGO_CACHE_REMOTE_TOKEN_FILE"] = environment.removeValue(forKey: "TUIST_CARGO_CACHE_TOKEN_FILE")
        environment["TUIST_CARGO_CACHE_REMOTE_MODE"] = environment["TUIST_CARGO_CACHE_UPLOAD"] == "1" ? "read-write" : "read-only"
        if let budget = CacheBudget.supportCaches {
            environment["TUIST_CARGO_CACHE_GC_MAX_TOTAL_SIZE"] = "\(budget)B"
            environment["TUIST_CARGO_CACHE_GC_MAX_SIZE"] = "\(budget)B"
        }
        return environment
    }
}
