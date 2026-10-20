import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistProcess
import TuistREAPI
@testable import TuistCargoCommand

struct CargoCompilationCacheTests {
    @Test func usesProjectNameAsREAPIInstanceWithinTheAccountTenant() throws {
        let scope = try #require(CargoCacheScope(fullHandle: "Acme/App"))
        #expect(scope.accountHandle == "acme")
        #expect(scope.instanceName == "app")
        for handle in ["acme", "/app", "acme/", "acme/app/other"] {
            #expect(CargoCacheScope(fullHandle: handle) == nil)
        }
    }

    @Test func preservesStandardREAPICompilerStreamsAndSymlinkFields() throws {
        let result = REAPI.ActionResult.with {
            $0.stdoutRaw = Data("compiler output".utf8)
            $0.stderrRaw = Data("compiler warning".utf8)
            $0.outputSymlinks = [.with { $0.path = "unsafe"; $0.target = "../escape" }]
        }
        let decoded = try REAPI.ActionResult(serializedBytes: result.serializedData())
        #expect(decoded == result)
        #expect(REAPIBlobUpload(available: []).uploaded == nil)
    }

    @Test(.inTemporaryDirectory) func restoresVerifiedLibraryOutputs() async throws {
        let fixture = try await fixture()
        let cache = try fixture.cache()
        try await cache.store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        #expect(try await cache.restore())
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(fixture.invocation.files[0])) == Data("library".utf8))
    }

    @Test(.inTemporaryDirectory) func successfulReuseRefreshesBlobRetention() async throws {
        let fixture = try await fixture()
        let cache = try fixture.cache()
        try await cache.store(stdout: Data(), stderr: Data())
        let blob = fixture.root.appendingPathComponent("cache/blobs/" + REAPI.digest(Data("library".utf8)).hash)
        let old = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: blob.path)
        try fixture.removeOutputs()
        #expect(try await cache.restore())
        let used = try #require(FileManager.default.attributesOfItem(atPath: blob.path)[.modificationDate] as? Date)
        #expect(used > old)
    }

    @Test(.inTemporaryDirectory) func cancelledRestorationDoesNotMaterializeOutputs() async throws {
        let fixture = try await fixture()
        let cache = try fixture.cache()
        try await cache.store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        let outputPath = fixture.invocation.output.appendingPathComponent(fixture.invocation.files[0]).path
        let restoration = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.restoreLocally()
        }
        await #expect(throws: CancellationError.self) { try await restoration.value }
        #expect(!FileManager.default.fileExists(atPath: outputPath))
    }

    @Test(.inTemporaryDirectory) func localProbeNeverContactsTheRemoteEvenForMissingBlobs() async throws {
        let fixture = try await fixture()
        try await fixture.cache().store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        let remote = CargoMemoryCache()
        let cache = try fixture.cache(remote: remote)
        #expect(try await cache.restoreLocally())
        try fixture.removeOutputs()
        let digest = REAPI.digest(Data("library".utf8))
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("cache/blobs/" + digest.hash))
        #expect(try await !cache.restoreLocally())
        #expect(await remote.reads == 0)
    }

    @Test(.inTemporaryDirectory) func restoresSplitDebugObjectsWithTheLibrary() async throws {
        let fixture = try await fixture()
        let name = "tiny-123.tiny.abc-cgu.0.rcgu.o"
        let object = fixture.output.appendingPathComponent(name)
        try Data("debug object".utf8).write(to: object)
        let cache = try fixture.cache()
        try await cache.store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        try FileManager.default.removeItem(at: object)
        #expect(try await cache.restore())
        #expect(try Data(contentsOf: object) == Data("debug object".utf8))
    }

    @Test(.inTemporaryDirectory) func producesReadableBoundedInspectionRecords() async throws {
        let fixture = try await fixture()
        let measurement = CargoCacheMeasurement(invocation: fixture.invocation)
        measurement.outcome(hit: true)
        measurement.timing("read", duration: 0.001)
        let digest = REAPI.digest(Data("artifact".utf8))
        measurement.reference(digest)
        measurement.transfer(digest, operation: "download", status: "downloaded", duration: 0.01)
        measurement.write()
        let session = URL(fileURLWithPath: try #require(fixture.invocation.environment["TUIST_CARGO_SESSION"]))
        let metrics = try #require(CargoCacheReport.read(root: session))
        let details = try #require(metrics["details"] as? [String: Any])
        #expect(metrics["hits"] as? UInt64 == 1)
        #expect((details["tasks"] as? [[String: Any]])?.count == 1)
        #expect((details["cas_outputs"] as? [[String: Any]])?.count == 1)
        #expect(details["truncated"] as? Bool == false)
    }

    @Test(.inTemporaryDirectory) func rejectsNativeTokensAndUninspectedMacroSources() async throws {
        let fixture = try await fixture()
        for source in [
            "#[cfg_attr(unix, link(name = \"native\"))] fn library() {}",
            "fn library() { asm /* comment */ !(\"nop\"); }",
            "include /* comment */ !(\"generated.txt\");",
            "macro_rules! generated { () => { ${concat(l, ink)} } }",
        ] {
            try Data(source.utf8).write(to: fixture.source)
            await #expect(throws: CargoCacheInvocation.CacheError.self) {
                try await fixture.prepare()
            }
        }
    }

    @Test(.inTemporaryDirectory) func acceptsPinnedRustupProxyAndTracksItsContents() async throws {
        let fixture = try await fixture()
        let bin = fixture.root.appendingPathComponent("proxy-bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let rustup = bin.appendingPathComponent("rustup")
        try "#!/bin/sh\nprintf '%s\\n' '\(fixture.invocation.toolchain.path)'\n".write(
            to: rustup,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rustup.path)
        let rustc = bin.appendingPathComponent("rustc")
        try FileManager.default.createSymbolicLink(at: rustc, withDestinationURL: rustup)
        var environment = fixture.invocation.environment
        environment["PATH"] = "\(bin.path):/usr/bin:/bin"
        environment["RUSTUP_TOOLCHAIN"] = "fixture"
        for executable in ["rustc", rustc.path] {
            let candidate = try #require(await fixture.prepare(
                arguments: [executable] + fixture.invocation.arguments.dropFirst(), environment: environment
            ))
            #expect(candidate.launcher == rustup.resolvingSymlinksInPath())
        }
        let candidate = try #require(await fixture.prepare(
            arguments: ["rustc"] + fixture.invocation.arguments.dropFirst(), environment: environment
        ))
        try "#!/bin/sh\nexit 99\n".write(to: rustup, atomically: true, encoding: .utf8)
        #expect(try candidate.fingerprint() != candidate.key)
    }

    @Test(.inTemporaryDirectory) func rejectsUnpinnedOrCustomRustcLaunchers() async throws {
        let fixture = try await fixture()
        let bin = fixture.root.appendingPathComponent("proxy-bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let rustc = bin.appendingPathComponent("rustc")
        try "#!/bin/sh\nprintf '%s\\n' '\(fixture.invocation.toolchain.path)'\n".write(
            to: rustc,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rustc.path)
        var environment = fixture.invocation.environment
        environment["PATH"] = "\(bin.path):/usr/bin:/bin"
        environment["RUSTUP_TOOLCHAIN"] = "fixture"
        #expect(try await fixture.prepare(
            arguments: ["rustc"] + fixture.invocation.arguments.dropFirst(),
            environment: environment
        ) == nil)
        let rustup = bin.appendingPathComponent("rustup")
        try FileManager.default.moveItem(at: rustc, to: rustup)
        try FileManager.default.createSymbolicLink(at: rustc, withDestinationURL: rustup)
        environment["RUSTUP_TOOLCHAIN"] = nil
        #expect(try await fixture.prepare(
            arguments: ["rustc"] + fixture.invocation.arguments.dropFirst(),
            environment: environment
        ) == nil)
    }

    @Test(.inTemporaryDirectory) func sourceResourcesEnvironmentAndCompilerInvalidateTheKey() async throws {
        let fixture = try await fixture()
        let original = fixture.invocation.key
        let resource = fixture.invocation.package.appendingPathComponent("resource.txt")
        try Data("one".utf8).write(to: resource)
        #expect(try fixture.invocation.fingerprint() != original)
        try FileManager.default.removeItem(at: resource)
        #expect(try fixture.invocation.fingerprint() == original)
        var environment = fixture.invocation.environment
        environment["RUSTFLAGS"] = "-C opt-level=3"
        #expect(try await fixture.prepare(environment: environment)?.key != original)
        environment = fixture.invocation.environment
        environment["TUIST_CARGO_SESSION"] = "/another/private/session"
        #expect(try await fixture.prepare(environment: environment)?.key == original)
        try Data("changed compiler".utf8).write(to: fixture.invocation.toolchain.appendingPathComponent("lib/compiler"))
        #expect(try fixture.invocation.fingerprint() != original)
    }

    @Test(.inTemporaryDirectory) func neverPublishesOutputsIfInputsChangedDuringCompilation() async throws {
        let fixture = try await fixture()
        try Data("pub fn changed() {}".utf8).write(to: fixture.source)
        try await fixture.cache().store(stdout: Data(), stderr: Data())
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("cache/actions").path))
    }

    @Test(.inTemporaryDirectory) func rejectsCorruptLocalArtifactsWithoutRestoringAnyOutputs() async throws {
        let fixture = try await fixture()
        let cache = try fixture.cache()
        try await cache.store(stdout: Data(), stderr: Data())
        let digest = REAPI.digest(Data("library".utf8))
        try Data("corrupt".utf8).write(to: fixture.root.appendingPathComponent("cache/blobs/" + digest.hash))
        try fixture.removeOutputs()
        #expect(try await !cache.restore())
        #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent(fixture.invocation.files[0]).path))
    }

    @Test(.inTemporaryDirectory) func excludesExternalInputsAndReferencesToPrivateSessionVariables() async throws {
        for dependency in ["/outside/undeclared.rs", "\(try #require(FileSystem.temporaryTestDirectory).pathString)/outside.rs"] {
            let fixture = try await fixture()
            try "artifact: \(dependency)\n".write(
                to: fixture.output.appendingPathComponent(fixture.invocation.files[2]), atomically: true, encoding: .utf8
            )
            do {
                try await fixture.cache().store(stdout: Data(), stderr: Data())
                Issue.record("An undeclared input was cached")
            } catch {}
        }
        let fixture = try await fixture()
        try "artifact: \(fixture.source.path)\n# env-dep:TUIST_CARGO_SESSION=private\n".write(
            to: fixture.output.appendingPathComponent(fixture.invocation.files[2]), atomically: true, encoding: .utf8
        )
        do {
            try await fixture.cache().store(stdout: Data(), stderr: Data())
            Issue.record("A private session-dependent output was cached")
        } catch {}
    }

    @Test func parsesEscapedDepInfoAndLineContinuations() throws {
        #expect(try CargoCacheInvocation.dependencies("out: /crate/a\\ b.rs \\\n /crate/c.rs\n\n/crate/c.rs:\n") == [
            "/crate/a b.rs", "/crate/c.rs",
        ])
        #expect(throws: (any Error).self) { try CargoCacheInvocation.dependencies("out: trailing\\") }
    }

    @Test(.inTemporaryDirectory) func bypassesUnsupportedCompilations() async throws {
        let fixture = try await fixture()
        for extra in [
            ["--extern", "some_macro=/tmp/libmacro.dylib"], ["-C", "incremental=/tmp/incremental"],
            ["--sysroot", "/another/toolchain"], ["--target", "custom.json"], ["--test"],
            ["-L", "native=/tmp/native"], ["@arguments"],
        ] {
            #expect(try await fixture.prepare(arguments: fixture.invocation.arguments + extra) == nil)
        }
        for variable in ["OUT_DIR", "RUSTC_WORKSPACE_WRAPPER", "TUIST_CARGO_INNER_WRAPPER"] {
            var environment = fixture.invocation.environment
            environment[variable] = "/some/wrapper/or/output"
            #expect(try await fixture.prepare(environment: environment) == nil)
        }
        var environment = fixture.invocation.environment
        environment["CARGO_MANIFEST_DIR"] = fixture.root.path
        #expect(try await fixture.prepare(environment: environment) == nil)
    }

    @Test(.inTemporaryDirectory) func rejectsSourceAndOutputSymlinks() async throws {
        let fixture = try await fixture()
        let link = fixture.invocation.package.appendingPathComponent("linked.rs")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.source)
        #expect(throws: (any Error).self) { try fixture.invocation.fingerprint() }
        try FileManager.default.removeItem(at: link)
        let output = fixture.output.appendingPathComponent(fixture.invocation.files[0])
        try FileManager.default.removeItem(at: output)
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: fixture.source)
        try await fixture.cache().store(stdout: Data(), stderr: Data())
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("cache/actions").path))
    }

    @Test(.inTemporaryDirectory) func remoteRoundTripUsesTheSharedREAPIAndVerifiedContent() async throws {
        let fixture = try await fixture()
        let remote = CargoMemoryCache()
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        #expect(await remote.publications == 1)
        try fixture.removeOutputs()
        let otherCache = try fixture.cache(remote: remote, directory: "other-cache")
        #expect(try await otherCache.restore())
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(fixture.invocation.files[0])) == Data("library".utf8))
    }

    @Test(.inTemporaryDirectory) func deniedRemoteWritesPreserveLocalCaching() async throws {
        let fixture = try await fixture()
        let remote = CargoMemoryCache(denyWrites: true)
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        #expect(await remote.publications == 0)
        try fixture.removeOutputs()
        #expect(try await fixture.cache().restoreLocally())
        #expect(try Data(contentsOf: fixture.output.appendingPathComponent(fixture.invocation.files[0])) == Data("library".utf8))
    }

    @Test(.inTemporaryDirectory) func partialUploadsNeverPublishAnActionResult() async throws {
        let fixture = try await fixture()
        let remote = CargoMemoryCache(rejectUploads: true)
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        #expect(await remote.publications == 0)
    }

    @Test(.inTemporaryDirectory) func rejectsUnsafeRemotePathsAndCorruptDownloads() async throws {
        let fixture = try await fixture()
        let remote = CargoMemoryCache()
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        await remote.corruptDownloads()
        #expect(try await !fixture.cache(remote: remote, directory: "corrupt-cache").restore())
        await remote.escapeOutputPath()
        #expect(try await !fixture.cache(remote: remote, directory: "unsafe-cache").restore())
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("escape").path))
    }

    @Test(.inTemporaryDirectory) func cacheFailureDoesNotReplaceCompilerExitStatus() async throws {
        let fixture = try await fixture()
        let script = "#!/bin/sh\nif [ \"$1\" = --print ]; then printf '%s' '\(fixture.invocation.toolchain.path)'; else exit 31; fi\n"
        try script.write(to: fixture.invocation.compiler, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.invocation.compiler.path)
        do {
            try await CargoCompilerObserver(runner: CommandRunner()).run(
                fixture.invocation.arguments, environment: fixture.invocation.environment, directory: fixture.invocation.directory
            )
            Issue.record("Compiler failure was lost")
        } catch let CommandError.terminated(code, _, _) { #expect(code == 31) }
    }

    private func fixture() async throws -> Fixture {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.appending(component: UUID().uuidString).pathString)
        let package = root.appendingPathComponent("cargo/registry/src/test/tiny")
        let toolchain = root.appendingPathComponent("toolchain")
        let output = root.appendingPathComponent("output")
        for folder in [package, toolchain.appendingPathComponent("lib"), toolchain.appendingPathComponent("bin"), output] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let source = package.appendingPathComponent("lib.rs")
        try Data("pub fn answer() -> u32 { 42 }".utf8).write(to: source)
        let compiler = toolchain.appendingPathComponent("bin/rustc")
        try "#!/bin/sh\nprintf '%s' '\(toolchain.path)'\n".write(to: compiler, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: compiler.path)
        try Data("compiler runtime".utf8).write(to: toolchain.appendingPathComponent("lib/compiler"))
        let environment = [
            "CARGO_HOME": root.appendingPathComponent("cargo").path, "CARGO_MANIFEST_DIR": package.path,
            "TUIST_CARGO_CACHE_DIR": root.appendingPathComponent("cache").path,
            "TUIST_CARGO_SESSION": root.appendingPathComponent("session").path,
            "TUIST_CARGO_STARTED": String(Date().timeIntervalSince1970),
        ]
        let arguments = [
            compiler.path,
            "--crate-name",
            "tiny",
            "--crate-type",
            "lib",
            "--emit=dep-info,metadata,link",
            "--out-dir",
            output.path,
            "-C",
            "extra-filename=-123",
            source.path,
        ]
        let invocation = try #require(await CargoCacheInvocation.prepare(
            arguments, environment: environment, directory: directory, process: CargoProcess(runner: CommandRunner())
        ))
        try Data("library".utf8).write(to: output.appendingPathComponent(invocation.files[0]))
        try Data("metadata".utf8).write(to: output.appendingPathComponent(invocation.files[1]))
        let escaped = source.path.replacingOccurrences(of: " ", with: "\\ ")
        try "artifact: \(escaped)\n".write(
            to: output.appendingPathComponent(invocation.files[2]),
            atomically: true,
            encoding: .utf8
        )
        return Fixture(root: root, source: source, output: output, invocation: invocation)
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let output: URL
        let invocation: CargoCacheInvocation

        func cache(remote: (any REAPICacheStoring)? = nil, directory: String = "cache") throws -> CargoCompilationCache {
            try CargoCompilationCache(
                invocation: invocation, root: root.appendingPathComponent(directory), remote: remote,
                measurement: CargoCacheMeasurement(invocation: invocation)
            )
        }

        func removeOutputs() throws {
            for file in invocation.files {
                try FileManager.default.removeItem(at: output.appendingPathComponent(file))
            }
        }

        func prepare(arguments: [String]? = nil, environment: [String: String]? = nil) async throws -> CargoCacheInvocation? {
            try await CargoCacheInvocation.prepare(
                arguments ?? invocation.arguments, environment: environment ?? invocation.environment,
                directory: invocation.directory, process: CargoProcess(runner: CommandRunner())
            )
        }
    }
}

private actor CargoMemoryCache: REAPICacheStoring {
    private var result: REAPI.ActionResult?
    private var blobs: [REAPI.Digest: Data] = [:]
    private let rejectUploads: Bool
    private let denyWrites: Bool
    private var corrupt = false
    private(set) var publications = 0
    private(set) var reads = 0

    init(rejectUploads: Bool = false, denyWrites: Bool = false) {
        self.rejectUploads = rejectUploads
        self.denyWrites = denyWrites
    }

    func actionResult(for _: REAPI.Digest) async throws -> REAPI.ActionResult? {
        reads += 1
        return result
    }

    func containsActionResult(for _: REAPI.Digest) async throws -> Bool { result != nil }

    func storeActionResult(_ result: REAPI.ActionResult, for _: REAPI.Digest) async throws {
        self.result = result
        publications += 1
    }

    func uploadAvailableBlobs(_ files: [REAPI.Digest: URL]) async throws -> REAPIBlobUpload {
        if denyWrites { throw REAPICacheError.uploadFailed(reason: "Permission denied") }
        if rejectUploads { return REAPIBlobUpload(available: []) }
        for (digest, file) in files {
            blobs[digest] = try Data(contentsOf: file)
        }
        return REAPIBlobUpload(available: Set(files.keys), uploaded: Set(files.keys))
    }

    func uploadBlobs(_ files: [REAPI.Digest: URL]) async throws { _ = try await uploadAvailableBlobs(files) }
    func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        reads += 1
        let data = try #require(blobs[digest])
        try (corrupt ? Data("corrupt".utf8) : data).write(to: path)
    }

    func corruptDownloads() { corrupt = true }
    func escapeOutputPath() { result?.outputFiles[0].path = "../escape" }
}
