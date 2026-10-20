import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCAS
import TuistCore
import TuistProcess
import TuistServer
@testable import TuistCargoCommand

struct CargoCacheRuntimeTests {
    @Test(.inTemporaryDirectory) func preparesTheBundledRuntimeWithoutInheritingItsPolicy() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let service = try runtime(root, protocolVersion: "tuist-cargo-cache 1")
        let context = context(root, environment: [
            "TUIST_CARGO_CACHE_TARGET_VIEWS": "true", "TUIST_CARGO_CACHE_REMOTE_TOKEN": "inherited-secret",
            "GITLAB_CI": "true", "CI_PIPELINE_SOURCE": "push", "CI_COMMIT_REF_PROTECTED": "true",
        ])
        let session = try #require(await service.prepare(context, root: URL(fileURLWithPath: root.pathString)))
        defer { session.cancel() }
        #expect(session.executable == root.appending(component: "tuist-cargo-cache").pathString)
        #expect(session.environment["CARGO"] == "/toolchains/cargo")
        #expect(session.environment["TUIST_CARGO_NATIVE"] == "1")
        #expect(session.environment["TUIST_CARGO_CACHE_DIR"]?.contains("/CargoNative/") == true)
        #expect(session.environment["TUIST_CARGO_CACHE_REMOTE_NAMESPACE"] == "acme/app")
        #expect(session.environment["TUIST_CARGO_CACHE_REMOTE_TOKEN_FILE"] != nil)
        #expect(session.environment["TUIST_CARGO_CACHE_TOKEN_FILE"] == nil)
        #expect(session.environment["TUIST_CARGO_CACHE_REMOTE_TOKEN"] == nil)
        #expect(session.environment["TUIST_CARGO_CACHE_REMOTE_MODE"] == "read-only")
        #expect(session.environment["TUIST_CARGO_CACHE_TARGET_VIEWS"] == "false")
        #expect(session.environment["TUIST_CARGO_CACHE_SCHEDULER"] == "false")
        #expect(session.environment["RUSTC_WRAPPER"] == nil)
        #expect(FileManager.default.fileExists(atPath: root.appending(component: "cache-reports").pathString))
        #expect(FileManager.default.fileExists(atPath: root.appending(component: "cache-details").pathString))
    }

    @Test(.inTemporaryDirectory) func onlyProtectedGitHubPushesEnableRemotePublication() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let service = try runtime(root, protocolVersion: "tuist-cargo-cache 1")
        let session = try #require(await service.prepare(context(root, environment: [
            "GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "push", "GITHUB_REF_TYPE": "branch",
            "GITHUB_REF_PROTECTED": "true",
        ]), root: URL(fileURLWithPath: root.pathString)))
        defer { session.cancel() }
        #expect(session.environment["TUIST_CARGO_CACHE_REMOTE_MODE"] == "read-write")
    }

    @Test(.inTemporaryDirectory) func unavailableOrIncompatibleHelpersAllowTheSwiftFallback() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        var service = try runtime(root, protocolVersion: "tuist-cargo-cache 999")
        #expect(await service.prepare(context(root), root: URL(fileURLWithPath: root.pathString)) == nil)
        try FileManager.default.removeItem(atPath: root.appending(component: "tuist-cargo-cache").pathString)
        #expect(await service.prepare(context(root), root: URL(fileURLWithPath: root.pathString)) == nil)
        service.ownExecutable = { throw CargoReportError(message: "Unavailable") }
        #expect(await service.prepare(context(root), root: URL(fileURLWithPath: root.pathString)) == nil)
    }

    @Test(.inTemporaryDirectory) func existingWrappersRemainAuthoritative() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let service = try runtime(root, protocolVersion: "tuist-cargo-cache 1")
        #expect(await service.prepare(
            context(root, environment: ["TUIST_CARGO_INNER_WRAPPER": "/existing/wrapper"]),
            root: URL(fileURLWithPath: root.pathString)
        ) == nil)
    }

    @Test(.inTemporaryDirectory) func nativeSubprocessesGetIndependentAggregateReports() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let output = root.appending(component: "reports")
        let arguments = ["-c", "printf '%s\\n' \"$TUIST_CARGO_CACHE_STATS_REPORT\""]
        let process = CargoProcess(runner: CommandRunner())
        let environment = ["TUIST_CARGO_NATIVE": "1", "TUIST_CARGO_CACHE_REPORTS": output.pathString]
        let first = try await process.capture("/bin/sh", arguments: arguments, environment: environment, directory: root)
        let second = try await process.capture("/bin/sh", arguments: arguments, environment: environment, directory: root)
        #expect(first != second)
        #expect(first.hasPrefix(output.pathString + "/"))
        #expect(first.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(".json"))
        let ordinary = try await process.capture("/bin/sh", arguments: arguments, environment: [:], directory: root)
        #expect(ordinary == "\n")
    }

    private func runtime(_ root: AbsolutePath, protocolVersion: String) throws -> CargoCacheRuntime {
        let helper = root.appending(component: "tuist-cargo-cache")
        try "#!/bin/sh\nprintf '%s\\n' '\(protocolVersion)'\n".write(
            toFile: helper.pathString, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.pathString)
        return CargoCacheRuntime(
            process: CargoProcess(runner: CommandRunner()),
            setup: CargoCacheSetup(
                cacheDirectoriesProvider: Directories(root: root.appending(component: "cache")),
                cacheURLStore: Endpoints(), getCacheTokenService: Tokens(), category: .cargoNative
            ),
            ownExecutable: { root.appending(component: "tuist").pathString }
        )
    }

    private func context(_ directory: AbsolutePath, environment: [String: String] = [:]) -> CargoExecutionContext {
        CargoExecutionContext(
            executable: "/toolchains/cargo", directory: directory, arguments: ["build"], environment: environment,
            reporting: CargoReporting(
                process: CargoProcess(runner: CommandRunner()), directory: directory, environment: environment,
                handle: "acme/app", serverURL: URL(string: "http://localhost:9001")!
            )
        )
    }

    private struct Directories: CacheDirectoriesProviding {
        let root: AbsolutePath
        func cacheDirectory() -> AbsolutePath { root }
        func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath {
            root.appending(component: category.directoryName)
        }
    }

    private struct Endpoints: CacheURLStoring {
        func getCacheURL(for _: URL, accountHandle _: String?) async throws -> URL {
            URL(string: "http://localhost:9000")!
        }

        func getCacheEndpoints(for serverURL: URL, accountHandle: String?) async throws -> [URL] {
            [try await getCacheURL(for: serverURL, accountHandle: accountHandle)]
        }
    }

    private struct Tokens: GetCacheTokenServicing {
        func getCacheToken(serverURL _: URL, fullHandle _: String?) async throws -> CacheToken {
            CacheToken(token: "fixture-token", expiresIn: 3600)
        }
    }
}
