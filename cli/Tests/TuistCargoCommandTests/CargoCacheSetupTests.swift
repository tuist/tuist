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

struct CargoCacheSetupTests {
    @Test(.inTemporaryDirectory) func preparesPrivateCredentialsAndUsesTheSharedCacheDirectory() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let setup = service(root)
        let context = context(root, environment: ["TUIST_CARGO_CACHE_STALE": "old"])
        let session = try #require(await setup.prepare(context, root: URL(fileURLWithPath: root.pathString)))
        defer { session.refresh?.cancel() }
        let path = try #require(session.environment["TUIST_CARGO_CACHE_DIR"])
        #expect(path.hasPrefix(root.appending(components: "cache", "Cargo").pathString + "/"))
        #expect(session.environment["TUIST_CARGO_CACHE_REMOTE_URL"] == "http://localhost:9000")
        #expect(session.environment["TUIST_CARGO_CACHE_NAMESPACE"] == "acme/app")
        #expect(session.environment["TUIST_CARGO_CACHE_STALE"] == nil)
        let file = try #require(session.environment["TUIST_CARGO_CACHE_TOKEN_FILE"])
        #expect(try String(contentsOfFile: file, encoding: .utf8) == "fixture-token")
        let permissions = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        let repeated = try #require(await setup.prepare(context, root: URL(fileURLWithPath: root.pathString)))
        defer { repeated.refresh?.cancel() }
        #expect(repeated.environment["TUIST_CARGO_CACHE_DIR"] == path)
    }

    @Test(.inTemporaryDirectory) func clearsTheObsoleteInheritedUploadFlag() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let session = try #require(await service(root).prepare(
            context(root, environment: ["TUIST_CARGO_CACHE_UPLOAD": "1"]), root: URL(fileURLWithPath: root.pathString)
        ))
        defer { session.refresh?.cancel() }
        #expect(session.environment["TUIST_CARGO_CACHE_UPLOAD"] == nil)
    }

    @Test(.inTemporaryDirectory) func readOnlyGrantHintIsClearedWhenServerTokenBecomesWritable() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let payload = Data(#"{"cache_grants":{"project":{"write":[]}}}"#.utf8).base64EncodedString()
        let session = try #require(await service(root, token: "header.\(payload).signature").prepare(
            context(root, environment: [:]), root: URL(fileURLWithPath: root.pathString)
        ))
        defer { session.refresh?.cancel() }
        let marker = try #require(CargoCacheSetup.readOnlyMarker(environment: session.environment))
        #expect(FileManager.default.fileExists(atPath: marker.path))
        for token in [
            "opaque-legacy-token",
            "header.\(Data(#"{"cache_grants":{"project":{"write":["acme/app"]}}}"#.utf8).base64EncodedString()).signature",
            "header.\(Data(#"{"cache_grants":{"project":{"write":"unknown-shape"}}}"#.utf8).base64EncodedString()).signature",
        ] {
            try Data().write(to: marker)
            let updated = try #require(await service(root, token: token).prepare(
                context(root, environment: [:]), root: URL(fileURLWithPath: root.pathString)
            ))
            updated.refresh?.cancel()
            #expect(!FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test(.inTemporaryDirectory) func preservesLocalCachingWhenRemoteSetupFails() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let session = try #require(await service(root, fails: true).prepare(
            context(root, environment: ["TUIST_CARGO_CACHE_REMOTE_URL": "http://stale"]),
            root: URL(fileURLWithPath: root.pathString)
        ))
        #expect(session.environment["TUIST_CARGO_CACHE_DIR"] != nil)
        #expect(session.environment["TUIST_CARGO_CACHE_REMOTE_URL"] == nil)
        #expect(session.refresh == nil)
    }

    @Test(.inTemporaryDirectory) func leavesExistingCompilerWrappersAuthoritative() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let session = await service(root).prepare(
            context(root, environment: ["TUIST_CARGO_INNER_WRAPPER": "/existing/wrapper"]),
            root: URL(fileURLWithPath: root.pathString)
        )
        #expect(session == nil)
    }

    private func service(_ root: AbsolutePath, fails: Bool = false, token: String = "fixture-token") -> CargoCacheSetup {
        CargoCacheSetup(
            cacheDirectoriesProvider: Directories(root: root.appending(component: "cache")),
            cacheURLStore: Endpoints(fails: fails), getCacheTokenService: Tokens(token: token)
        )
    }

    private func context(_ directory: AbsolutePath, environment: [String: String]) -> CargoExecutionContext {
        CargoExecutionContext(
            executable: "cargo", directory: directory, arguments: ["build"], environment: environment,
            reporting: CargoReporting(
                process: CargoProcess(runner: CommandRunner()), directory: directory, environment: environment,
                handle: "acme/app", serverURL: URL(string: "http://localhost:9001")!
            )
        )
    }

    private struct Directories: CacheDirectoriesProviding {
        let root: AbsolutePath
        func cacheDirectory() -> AbsolutePath { root }
        func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath { root
            .appending(component: category.directoryName)
        }
    }

    private struct Endpoints: CacheURLStoring {
        let fails: Bool
        func getCacheURL(for _: URL, accountHandle _: String?) async throws -> URL {
            if fails { throw CargoReportError(message: "Unavailable") }
            return URL(string: "http://localhost:9000")!
        }

        func getCacheEndpoints(for serverURL: URL, accountHandle: String?) async throws -> [URL] {
            [try await getCacheURL(for: serverURL, accountHandle: accountHandle)]
        }
    }

    private struct Tokens: GetCacheTokenServicing {
        let token: String
        func getCacheToken(serverURL _: URL, fullHandle _: String?) async throws -> CacheToken {
            CacheToken(token: token, expiresIn: 3600)
        }
    }
}
