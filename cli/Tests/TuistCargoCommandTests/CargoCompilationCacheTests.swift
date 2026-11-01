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

    @Test(.inTemporaryDirectory) func rejectsAssemblyAndProbesPreviouslyUninspectedSources() async throws {
        let fixture = try await fixture()
        for source in [
            "fn library() { asm /* comment */ !(\"nop\"); }",
            "core::arch::global_asm!(\"nop\");",
            "#[unsafe(naked)] pub extern \"C\" fn library() { core::arch::naked_asm!(\"ret\"); }",
            "#[link(name = \"hidden\")] unsafe extern \"C\" {}",
            "#![feature(link_args)]",
            "macro_rules! library { () => { concat_idents!(global_, asm) } }",
            "macro_rules! library { () => { core::arch::${concat(global_, a, sm)}!(\"nop\"); } }",
            "macro_rules! library { () => { $\u{2003}{\u{2003}concat(global_, a, sm)} } }",
            "#![feature(macro_metavar_expr_concat)]\nmacro_rules! library { () => { ${ /* gap */ concat(global_, a, sm)} } }",
            "pub const OPEN: &str = \"/*\"; core::arch::global_asm!(\"nop\");",
            "pub const QUOTE: char = '\"'; core::arch::global_asm!(\"nop\");",
            "pub const RAW: &str = r#\"\"// \"#; core::arch::global_asm!(\"nop\");",
            "/* unterminated asm",
        ] {
            try Data(source.utf8).write(to: fixture.source)
            await #expect(throws: CargoCacheInvocation.CacheError.self) {
                try await fixture.prepare()
            }
        }
        for source in [
            "pub fn library() -> &'static str { concat!(\"tracked\", \" input\") }",
            "pub use core::concat;",
            "pub fn library() -> Vec<u8> { [b\"tracked\", b\" input\"].concat() }",
            "pub fn blink() {} pub use core::concat;",
            "pub fn éasmé() {} pub use core::concat;",
            "/// Follows a symbolic link, like the `asm` file type.\npub fn library<'a>(link: &'a str) -> &'a str { link }",
            "pub const TYPES: &[&str] = &[\"asm\", r#\"link(\"#]; /* naked_asm /* nested */ */ pub use core::concat;",
        ] {
            try Data(source.utf8).write(to: fixture.source)
            #expect(try await fixture.prepare()?.compilerInputs != nil)
        }
    }

    @Test(.inTemporaryDirectory) func tracksResolvedSourcesAndCertifiedDependenciesWithoutHashingOutputDirectories() async throws {
        let fixture = try await fixture()
        let dependency = fixture.output.appendingPathComponent(fixture.invocation.files[0])
        try fixture.invocation.certifyOutputs()
        let generated = fixture.root.appendingPathComponent("generated.rs")
        try Data("pub fn generated() {}".utf8).write(to: generated)
        let report = "artifact: \(fixture.source.path) \(generated.path)\n"
        try report.write(to: fixture.root.appendingPathComponent("probe.d"), atomically: true, encoding: .utf8)
        let arguments = fixture.invocation.arguments + [
            "--extern", "dependency=\(dependency.path)", "-L", "dependency=\(fixture.output.path)",
        ]
        let original = try #require(await fixture.prepare(arguments: arguments))
        try Data("unrelated".utf8).write(to: dependency.deletingLastPathComponent().appendingPathComponent("unrelated.rlib"))
        #expect(try await fixture.prepare(arguments: arguments)?.key == original.key)
        try Data("pub fn changed() {}".utf8).write(to: generated)
        #expect(try await fixture.prepare(arguments: arguments)?.key != original.key)
        try Data("pub fn generated() {}".utf8).write(to: generated)
        try Data("changed dependency".utf8).write(to: dependency)
        await #expect(throws: CargoCacheInvocation.CacheError.self) { try await fixture.prepare(arguments: arguments) }
        try fixture.invocation.certifyOutputs()
        #expect(try await fixture.prepare(arguments: arguments)?.key != original.key)
    }

    @Test(.inTemporaryDirectory) func inspectsIncludedNonRustFilesBeforeCertifyingRegistryLibraries() async throws {
        let fixture = try await fixture()
        let included = fixture.source.deletingLastPathComponent().appendingPathComponent("generated.txt")
        try Data("include!(\"generated.txt\");".utf8).write(to: fixture.source)
        try "artifact: \(fixture.source.path) \(included.path)\n".write(
            to: fixture.root.appendingPathComponent("probe.d"), atomically: true, encoding: .utf8
        )
        try Data("pub fn generated() {}".utf8).write(to: included)
        #expect(try await fixture.prepare()?.compilerInputs != nil)
        try Data("core::arch::global_asm!(\".include \\\"hidden.s\\\"\");".utf8).write(to: included)
        await #expect(throws: CargoCacheInvocation.CacheError.self) { try await fixture.prepare() }
        try Data(repeating: 65, count: 2_000_000).write(to: included)
        #expect(try await fixture.prepare()?.compilerInputs != nil)
        try Data(repeating: 65, count: 2_000_001).write(to: included)
        await #expect(throws: CargoCacheInvocation.CacheError.self) { try await fixture.prepare() }
    }

    @Test(.inTemporaryDirectory) func rejectsUncertifiedDependenciesAndProceduralMacros() async throws {
        let fixture = try await fixture()
        for name in ["libunknown.rlib", "libmacro.dylib"] {
            let dependency = fixture.output.appendingPathComponent(name)
            try Data("uninspected dependency".utf8).write(to: dependency)
            await #expect(throws: CargoCacheInvocation.CacheError.self) {
                try await fixture.prepare(arguments: fixture.invocation.arguments + ["--extern", "dependency=\(dependency.path)"])
            }
        }
    }

    @Test(.inTemporaryDirectory) func tracksGeneratedInputsAndRejectsDependencySetChangesDuringCompilation() async throws {
        let fixture = try await fixture()
        var environment = fixture.invocation.environment
        environment["OUT_DIR"] = fixture.root.path
        let original = try #require(await fixture.prepare(environment: environment))
        try "artifact: \(fixture.source.path) \(fixture.root.path)/new-input.rs\n".write(
            to: fixture.output.appendingPathComponent(original.files[2]), atomically: true, encoding: .utf8
        )
        await #expect(throws: CargoCacheInvocation.CacheError.self) {
            try await fixture.cache(invocation: original).store(stdout: Data(), stderr: Data())
        }
    }

    @Test(.inTemporaryDirectory) func acceptsPinnedRustupProxyAndTracksItsContents() async throws {
        let fixture = try await fixture()
        let bin = fixture.root.appendingPathComponent("proxy-bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let rustup = bin.appendingPathComponent("rustup")
        try "#!/bin/sh\nprintf '%s\\n' '\(fixture.invocation.toolchain.path)' '\(fixture.invocation.hostTarget.path)/lib'\n"
            .write(
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
        try "#!/bin/sh\nprintf '%s\\n' '\(fixture.invocation.toolchain.path)' '\(fixture.invocation.hostTarget.path)/lib'\n"
            .write(
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
        #expect(try await fixture.prepare()?.key != original)
    }

    @Test(.inTemporaryDirectory) func credentialsAndCIRunMetadataDoNotInvalidateTheKey() async throws {
        let fixture = try await fixture()
        for variable in [
            "TUIST_TOKEN", "TUIST_DEBUG", "TUIST_CACHE_ENDPOINT", "GITHUB_RUN_ID", "GITLAB_USER_ID",
            "CI_JOB_ID", "CI", "BUILDKITE_BUILD_ID", "CIRCLE_WORKFLOW_ID", "RUNNER_TRACKING_ID", "ACTIONS_RUNTIME_TOKEN",
            "SHLVL", "OLDPWD", "_", "TERM_SESSION_ID", "INVOCATION_ID",
        ] {
            var environment = fixture.invocation.environment
            environment[variable] = "another-invocation"
            #expect(try await fixture.prepare(environment: environment)?.key == fixture.invocation.key)
        }
    }

    @Test(.inTemporaryDirectory) func neverCachesCratesThatReadExcludedCredentialsOrCIMetadata() async throws {
        let fixture = try await fixture()
        for variable in ["TUIST_TOKEN", "TUIST_DEBUG", "GITHUB_RUN_ID", "CI_JOB_ID", "CI", "RUNNER_TRACKING_ID", "SHLVL"] {
            for value in ["", "=observed-value"] {
                try "artifact: \(fixture.source.path)\n# env-dep:\(variable)\(value)\n".write(
                    to: fixture.output.appendingPathComponent(fixture.invocation.files[2]),
                    atomically: true, encoding: .utf8
                )
                await #expect(throws: CargoCacheInvocation.CacheError.self) {
                    try await fixture.cache().store(stdout: Data(), stderr: Data())
                }
            }
        }
    }

    @Test(.inTemporaryDirectory) func terminalPresentationDoesNotInvalidateDiagnosticFreeEntries() async throws {
        let fixture = try await fixture()
        for options in [
            ["--diagnostic-width=80"],
            ["--diagnostic-width", "140"],
        ] {
            let invocation = try #require(await fixture.prepare(arguments: fixture.invocation.arguments + options))
            #expect(invocation.key == fixture.invocation.key)
        }
        for options in [
            ["--diagnostic-width", "invalid"], ["--diagnostic-width=-0"], ["--color=invalid"], ["--color"],
            ["--diagnostic-width=80", "--diagnostic-width=140"],
        ] {
            let invocation = try #require(await fixture.prepare(arguments: fixture.invocation.arguments + options))
            #expect(invocation.key != fixture.invocation.key)
        }
        let artifacts = Data(#"{"$message_type":"artifact","artifact":"libtiny.rlib","emit":"link"}"#.utf8)
        try await fixture.cache().store(stdout: Data(), stderr: artifacts)
        try fixture.removeOutputs()
        #expect(try await fixture.cache().restoreLocally())
    }

    @Test(.inTemporaryDirectory) func renderedDiagnosticsAndUnexpectedStreamsAreNeverCached() async throws {
        let fixture = try await fixture()
        for diagnostic in [
            Data("warning: terminal-specific rendering".utf8),
            Data(#"{"$message_type":"diagnostic","rendered":"warning: narrow terminal"}"#.utf8),
        ] {
            try await fixture.cache().store(stdout: Data(), stderr: diagnostic)
            #expect(try await fixture.cache().restoreLocally() == false)
        }
        try await fixture.cache().store(stdout: Data("unexpected compiler output".utf8), stderr: Data())
        #expect(try await fixture.cache().restoreLocally() == false)
    }

    @Test(.inTemporaryDirectory) func neverReplaysTerminalSpecificRemoteCompilerStreams() async throws {
        let fixture = try await fixture()
        let remote = CargoMemoryCache()
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        for (stdout, stderr) in [
            (Data(), Data(#"{"$message_type":"diagnostic","rendered":"terminal-specific warning"}"#.utf8)),
            (Data("unexpected output".utf8), Data()),
        ] {
            await remote.setCompilerStreams(stdout: stdout, stderr: stderr)
            #expect(try await fixture.cache(remote: remote, directory: "consumer").restore() == false)
        }
    }

    @Test(.inTemporaryDirectory) func readOnlyGrantHintSkipsUploadsWithoutDisablingLocalCaching() async throws {
        let fixture = try await fixture()
        let marker = try #require(CargoCacheSetup.readOnlyMarker(environment: fixture.invocation.environment))
        try Data().write(to: marker)
        let remote = CargoMemoryCache()
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        #expect(await remote.uploadAttempts == 0)
        #expect(await remote.publications == 0)
        try fixture.removeOutputs()
        #expect(try await fixture.cache().restoreLocally())
        try FileManager.default.removeItem(at: marker)
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        #expect(await remote.uploadAttempts == 1)
        #expect(await remote.publications == 1)
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
            ["-C", "incremental=/tmp/incremental"],
            ["--sysroot", "/another/toolchain"], ["--target", "custom.json"], ["--test"],
            ["-L", "framework=/tmp/native"], ["-L", "native=/tmp/native"], ["@arguments"],
            ["--library-path=native=/tmp/native"], ["--codegen=target-cpu=native"],
            ["-lstatic=native"], ["-l", "native"], ["-o/tmp/another-output"],
        ] {
            #expect(try await fixture.prepare(arguments: fixture.invocation.arguments + extra) == nil)
        }
        for variable in ["RUSTC_WORKSPACE_WRAPPER", "TUIST_CARGO_INNER_WRAPPER"] {
            var environment = fixture.invocation.environment
            environment[variable] = "/some/wrapper/or/output"
            #expect(try await fixture.prepare(environment: environment) == nil)
        }
        var environment = fixture.invocation.environment
        environment["CARGO_MANIFEST_DIR"] = fixture.root.path
        #expect(try await fixture.prepare(environment: environment)?.compilerInputs != nil)
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

    @Test(.inTemporaryDirectory) func localMaterializationFailureDoesNotMarkTheRemoteUnhealthy() async throws {
        let fixture = try await fixture()
        let remote = CargoMemoryCache()
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        let consumer = fixture.root.appendingPathComponent("consumer")
        try FileManager.default.createDirectory(at: consumer, withIntermediateDirectories: true)
        let obstruction = consumer.appendingPathComponent("staging")
        try Data("local obstruction".utf8).write(to: obstruction)
        let measurement = CargoCacheMeasurement(invocation: fixture.invocation)
        let cache = try CargoCompilationCache(
            invocation: fixture.invocation, root: consumer, remote: remote, measurement: measurement
        )
        #expect(try await !cache.restoreRemotely())
        #expect(!measurement.hasRemoteFailure)
        try FileManager.default.removeItem(at: obstruction)
        #expect(try await cache.restoreRemotely())
        #expect(!measurement.hasRemoteFailure)
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
        let cache = try fixture.cache(remote: remote, directory: "corrupt-cache")
        #expect(try await !cache.restore())
        #expect(!cache.measurement.hasRemoteFailure)
        await remote.corruptDownloads(false)
        #expect(try await cache.restore())
        try fixture.removeOutputs()
        await remote.failDownloads()
        let unavailable = try fixture.cache(remote: remote, directory: "unavailable-cache")
        #expect(try await !unavailable.restore())
        #expect(unavailable.measurement.hasRemoteFailure)
        await remote.escapeOutputPath()
        #expect(try await !fixture.cache(remote: remote, directory: "unsafe-cache").restore())
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("escape").path))
    }

    @Test(.inTemporaryDirectory) func cacheFailureDoesNotReplaceCompilerExitStatus() async throws {
        let fixture = try await fixture()
        let script = "#!/bin/sh\nif [ \"$1\" = --print ]; then printf '%s\\n' '\(fixture.invocation.toolchain.path)' '\(fixture.invocation.hostTarget.path)/lib'; else exit 31; fi\n"
        try script.write(to: fixture.invocation.compiler, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.invocation.compiler.path)
        do {
            try await CargoCompilerObserver(runner: CommandRunner()).run(
                fixture.invocation.arguments, environment: fixture.invocation.environment, directory: fixture.invocation.directory
            )
            Issue.record("Compiler failure was lost")
        } catch let CommandError.terminated(code, _, _) { #expect(code == 31) }
    }

    #if os(macOS) && arch(arm64)
        @Test(.inTemporaryDirectory) func nativeShimPreservesLateCompilerSelectionsAndCurrentPATH() async throws {
            let fixture = try await nativeShimFixture()
            let process = CargoProcess(runner: CommandRunner())
            let root = URL(fileURLWithPath: fixture.directory.pathString)
            let bin = root.appendingPathComponent("later bin")
            let shim = fixture.wrapper.deletingLastPathComponent().path
            let alias = root.appendingPathComponent("shim alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.wrapper.deletingLastPathComponent())
            try FileManager.default.copyItem(at: bin.appendingPathComponent("cc"), to: root.appendingPathComponent("cc"))
            let relative = root.appendingPathComponent("-tools")
            try FileManager.default.createDirectory(at: relative, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: bin.appendingPathComponent("cc"), to: relative.appendingPathComponent("cc"))
            let arguments = ["-c", "input.c", "-o", "object with spaces.o", "", "*.[ch]", "quote'\""]
            for (path, expectedPATH) in [
                ("\(shim):\(bin.path):/usr/bin:/bin", "\(bin.path):/usr/bin:/bin"),
                ("\(bin.path):\(shim):/usr/bin:/bin", "\(bin.path):\(shim):/usr/bin:/bin"),
                ("\(shim):\(alias.path):\(shim)/:\(bin.path):/usr/bin:/bin", "\(bin.path):/usr/bin:/bin"),
                ("\(shim):later bin::/usr/bin:/bin:", "later bin::/usr/bin:/bin:"),
                ("\(shim)::/usr/bin:/bin", ":/usr/bin:/bin"),
                ("\(shim):-tools:/usr/bin:/bin", "-tools:/usr/bin:/bin"),
            ] {
                var environment = fixture.environment
                environment["PATH"] = path
                let actual = try await process.captureOutput(
                    "cc", arguments: arguments, environment: environment, directory: fixture.directory
                )
                #expect(actual.stdout == Data((["cc", expectedPATH] + arguments).joined(separator: "\0").utf8) + Data([0]))
                #expect(actual.stderr.isEmpty)
            }
            for (variable, compiler) in [("CC", "cc"), ("HOST_CC", "cc"), ("CARGO_ENCODED_RUSTFLAGS", "clang")] {
                var environment = fixture.environment
                environment["PATH"] = "\(shim):\(bin.path):/usr/bin:/bin"
                environment[variable] = variable == "CARGO_ENCODED_RUSTFLAGS" ? "-Clinker-plugin-lto"
                    : bin.appendingPathComponent(compiler).path
                // cc-rs checks target-specific CC before HOST_CC/CC, and otherwise prefers clang for linker-plugin-lto.
                let actual = try await process.captureOutput(
                    "/bin/sh", arguments: [
                        "-c", "exec \"${CC_aarch64_apple_darwin:-${HOST_CC:-${CC:-clang}}}\" \"$@\"", "cc-rs",
                    ] + arguments, environment: environment, directory: fixture.directory
                )
                let expected = [compiler, try #require(environment["PATH"])] + arguments
                #expect(actual.stdout == Data(expected.joined(separator: "\0").utf8) + Data([0]))
                #expect(actual.stderr.isEmpty)
            }
            let probe = root.appendingPathComponent("compiler-argv.c")
            try Data("#include <stdio.h>\nint main(int argc, char **argv) { fputs(argv[0], stdout); }\n".utf8).write(to: probe)
            _ = try await process.captureOutput(
                "/usr/bin/cc", arguments: [probe.path, "-o", bin.appendingPathComponent("cc").path],
                environment: fixture.environment, directory: fixture.directory
            )
            var environment = fixture.environment
            environment["PATH"] = "\(bin.path):/usr/bin:/bin"
            let control = try await process.captureOutput(
                "cc", arguments: arguments, environment: environment, directory: fixture.directory
            )
            #expect(control.stdout == Data("cc".utf8))
            environment["PATH"] = "\(shim):\(bin.path):/usr/bin:/bin"
            let actual = try await process.captureOutput(
                "cc", arguments: arguments, environment: environment, directory: fixture.directory
            )
            #expect(actual.stdout == control.stdout)
            let startup = root.appendingPathComponent("bash startup")
            try Data("exit 29\n".utf8).write(to: startup)
            environment["BASH_ENV"] = startup.path
            try FileManager.default.removeItem(at: relative.appendingPathComponent("cc"))
            try FileManager.default.copyItem(at: bin.appendingPathComponent("cc"), to: relative.appendingPathComponent("cc"))
            environment["PATH"] = "\(shim):-tools:/usr/bin:/bin"
            let relativeActual = try await process.captureOutput(
                "cc", arguments: arguments, environment: environment, directory: fixture.directory
            )
            #expect(relativeActual.stdout == control.stdout)
            #expect(relativeActual.stderr.isEmpty)
            let portable = try await process.captureOutput(
                "/bin/dash", arguments: [fixture.wrapper.path] + arguments,
                environment: environment, directory: fixture.directory
            )
            #expect(portable.stdout == control.stdout)
            #expect(portable.stderr.isEmpty)
        }

        @Test(.inTemporaryDirectory, .timeLimit(.minutes(1)))
        func nativeShimSkipsCompilerFileAliasesWithoutLosingHelpersOrInheritedExports() async throws {
            let fixture = try await nativeShimFixture()
            let process = CargoProcess(runner: CommandRunner())
            let root = URL(fileURLWithPath: fixture.directory.pathString)
            let bin = root.appendingPathComponent("later bin")
            let shim = fixture.wrapper.deletingLastPathComponent().path
            let alias = root.appendingPathComponent("file alias")
            let chain = root.appendingPathComponent("chained alias")
            let retained = root.appendingPathComponent("retained hard link")
            let secondRetained = root.appendingPathComponent("second retained hard link")
            for folder in [alias, chain, retained, secondRetained] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try FileManager.default.createSymbolicLink(
                at: alias.appendingPathComponent("cc"),
                withDestinationURL: fixture.wrapper
            )
            try FileManager.default.createSymbolicLink(
                at: chain.appendingPathComponent("cc"), withDestinationURL: alias.appendingPathComponent("cc")
            )
            try FileManager.default.linkItem(at: fixture.wrapper, to: retained.appendingPathComponent("cc"))
            var setupEnvironment = fixture.environment
            setupEnvironment["PATH"] = "/usr/bin:/bin"
            _ = try await CargoClangInvocation.configure(
                environment: setupEnvironment, directory: fixture.directory, process: process
            )
            try FileManager.default.linkItem(at: fixture.wrapper, to: secondRetained.appendingPathComponent("cc"))
            _ = try await CargoClangInvocation.configure(
                environment: setupEnvironment, directory: fixture.directory, process: process
            )
            let helper = alias.appendingPathComponent("cc-helper")
            try "#!/bin/sh\nprintf '%s' 'alias helper' > \"$HELPER_LOG\"\n".write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            try """
            #!/bin/sh
            printf '%s\\0' "$compiler" "$remaining" "$entry" "$compiler_path" "$input" "$size" "$separator" "$more" > "$EXPORTS_LOG"
            cc-helper
            exec "$compiler" "$@"

            """.write(to: bin.appendingPathComponent("cc"), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bin.appendingPathComponent("cc").path)
            var environment = fixture.environment
            let variables = ["compiler", "remaining", "entry", "compiler_path", "input", "size", "separator", "more"]
            let values = [bin.appendingPathComponent("clang").path] + variables.dropFirst().map { "inherited \($0)" }
            for (name, value) in zip(variables, values) {
                environment[name] = value
            }
            environment["SHELLOPTS"] = "errexit:noglob:nounset"
            environment["EXPECT_SHELL_OPTIONS"] = "1"
            let exports = root.appendingPathComponent("exports")
            let helperLog = root.appendingPathComponent("helper log")
            environment["EXPORTS_LOG"] = exports.path
            environment["HELPER_LOG"] = helperLog.path
            let arguments = ["argument with spaces", "", "*.[ch]", "quote'\""]
            for (path, expectedPATH) in [
                (
                    "\(shim):\(alias.path):\(chain.path):\(bin.path):/usr/bin:/bin",
                    "\(alias.path):\(chain.path):\(bin.path):/usr/bin:/bin"
                ),
                ("\(alias.path):\(shim):\(bin.path):/usr/bin:/bin", "\(alias.path):\(bin.path):/usr/bin:/bin"),
                ("\(shim):\(bin.path):\(alias.path):/usr/bin:/bin", "\(bin.path):\(alias.path):/usr/bin:/bin"),
                (
                    "\(shim):\(retained.path):\(alias.path):\(bin.path):/usr/bin:/bin",
                    "\(retained.path):\(alias.path):\(bin.path):/usr/bin:/bin"
                ),
                (
                    "\(shim):\(retained.path):\(secondRetained.path):\(alias.path):\(bin.path):/usr/bin:/bin",
                    "\(retained.path):\(secondRetained.path):\(alias.path):\(bin.path):/usr/bin:/bin"
                ),
                (
                    "\(secondRetained.path):\(retained.path):\(shim):\(alias.path):\(bin.path):/usr/bin:/bin",
                    "\(secondRetained.path):\(retained.path):\(alias.path):\(bin.path):/usr/bin:/bin"
                ),
            ] {
                environment["PATH"] = path
                let actual = try await process.captureOutput(
                    "cc", arguments: arguments, environment: environment, directory: fixture.directory
                )
                #expect(actual.stdout == Data((["clang", expectedPATH] + arguments).joined(separator: "\0").utf8) + Data([0]))
                #expect(actual.stderr.isEmpty)
                #expect(try Data(contentsOf: exports) == Data(values.joined(separator: "\0").utf8) + Data([0]))
                #expect(try String(contentsOf: helperLog, encoding: .utf8) == "alias helper")
            }
            environment["PATH"] = "\(alias.path):\(shim):/usr/bin:/bin"
            _ = try await process.captureOutput(
                "cc", arguments: ["-c", "input.c", "-o", "alias.o"], environment: environment, directory: fixture.directory
            )
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("alias.o").path))
            environment["PATH"] = "\(shim):\(retained.path):\(secondRetained.path):\(alias.path):\(chain.path)"
            do {
                _ = try await process.captureOutput(
                    "cc",
                    arguments: arguments,
                    environment: environment,
                    directory: fixture.directory
                )
                Issue.record("Compiler aliases without a real compiler did not fail")
            } catch let CommandError.terminated(code, _, _) { #expect(code == 127) }
        }

        @Test(.inTemporaryDirectory) func nativeShimPreservesCompilerFailuresAndInheritedShellOptions() async throws {
            let fixture = try await nativeShimFixture()
            let process = CargoProcess(runner: CommandRunner())
            let root = URL(fileURLWithPath: fixture.directory.pathString)
            var environment = fixture.environment
            environment["SHELLOPTS"] = "errexit:noglob:nounset"
            let arguments = ["-c", "input.c", "-o", "object with spaces.o"]
            _ = try await process.captureOutput(
                "cc",
                arguments: arguments,
                environment: environment,
                directory: fixture.directory
            )
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("object with spaces.o").path))
            for custom in [false, true] {
                var failing = environment
                if custom {
                    failing["PATH"] = fixture.wrapper.deletingLastPathComponent().path + ":" + root
                        .appendingPathComponent("later bin").path
                    failing["COMPILER_EXIT"] = "31"
                    failing["EXPECT_SHELL_OPTIONS"] = "1"
                } else {
                    try Data("#error selected Apple cc\n".utf8).write(to: root.appendingPathComponent("input.c"))
                }
                do {
                    _ = try await process.captureOutput(
                        "cc",
                        arguments: arguments,
                        environment: failing,
                        directory: fixture.directory
                    )
                    Issue.record("The selected compiler's failure was lost")
                } catch let CommandError.terminated(code, stderr, _) {
                    #expect(code == (custom ? 31 : 1))
                    #expect(stderr.contains(custom ? "selected compiler failed" : "selected Apple cc"))
                }
            }
            let denied = root.appendingPathComponent("nonexecutable bin")
            try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: denied.appendingPathComponent("cc"))
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: denied.appendingPathComponent("cc").path
            )
            for (path, expectedCode) in [
                (fixture.wrapper.deletingLastPathComponent().path, Int32(127)),
                (root.appendingPathComponent("missing bin").path, Int32(127)),
                (fixture.wrapper.deletingLastPathComponent().path + ":" + denied.path, Int32(126)),
            ] {
                environment["PATH"] = path
                do {
                    _ = try await process.captureOutput(
                        fixture.wrapper.path, arguments: arguments, environment: environment, directory: fixture.directory
                    )
                    Issue.record("An unavailable compiler was replaced with the outer command's compiler")
                } catch let CommandError.terminated(code, _, _) { #expect(code == expectedCode) }
            }
        }

        @Test(.inTemporaryDirectory) func colonContainingCachePathsNeverChangeCompilerLookup() async throws {
            let fixture = try await nativeShimFixture()
            let process = CargoProcess(runner: CommandRunner())
            let root = URL(fileURLWithPath: fixture.directory.pathString)
            let cache = root.appendingPathComponent("later bin").path + ":" + root.appendingPathComponent("colon cache").path
            let environment = try await CargoClangInvocation.configure(
                environment: ["PATH": "/usr/bin:/bin", "TUIST_CARGO_CACHE_DIR": cache],
                directory: fixture.directory, process: process
            )
            let actual = try await process.captureOutput(
                "cc", arguments: ["-c", "input.c", "-o", "colon.o"], environment: environment, directory: fixture.directory
            )
            #expect(actual.stdout.isEmpty)
            #expect(actual.stderr.isEmpty)
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("colon.o").path))
            #expect(!FileManager.default
                .fileExists(atPath: URL(fileURLWithPath: cache).appendingPathComponent("wrappers/cc").path))
        }

        private func nativeShimFixture() async throws -> (environment: [String: String], directory: AbsolutePath, wrapper: URL) {
            let directory = try #require(FileSystem.temporaryTestDirectory)
            let root = URL(fileURLWithPath: directory.pathString)
            let cache = root.appendingPathComponent("compiler's cache")
            let bin = root.appendingPathComponent("later bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data("int value(void) { return 42; }\n".utf8).write(to: root.appendingPathComponent("input.c"))
            for name in ["cc", "clang"] {
                let compiler = bin.appendingPathComponent(name)
                try """
                #!/bin/sh
                if [ -n "${EXPECT_SHELL_OPTIONS:-}" ]; then
                  for flag in e f u; do
                    case "$-" in *"$flag"*) ;; *) exit 97 ;; esac
                  done
                fi
                printf '%s\\0' "${0##*/}" "$PATH" "$@"
                if [ "${COMPILER_EXIT:-0}" != 0 ]; then
                  printf '%s\\n' 'selected compiler failed' >&2
                  exit "$COMPILER_EXIT"
                fi

                """.write(to: compiler, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: compiler.path)
            }
            let environment = try await CargoClangInvocation.configure(
                environment: [
                    "PATH": "/usr/bin:/bin", "TUIST_CARGO_CACHE_DIR": cache.path,
                    "TUIST_CARGO_CACHE_REMOTE_URL": "http://unused.invalid",
                ], directory: directory, process: CargoProcess(runner: CommandRunner())
            )
            let wrapper = cache.appendingPathComponent("wrappers/cc")
            #expect(FileManager.default.isExecutableFile(atPath: wrapper.path))
            return (environment, directory, wrapper)
        }
    #endif

    private func fixture() async throws -> Fixture {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.appending(component: UUID().uuidString).pathString)
        let package = root.appendingPathComponent("cargo/registry/src/test/tiny")
        let toolchain = root.appendingPathComponent("toolchain")
        let output = root.appendingPathComponent("output")
        let hostLibraries = toolchain.appendingPathComponent("lib/rustlib/host/lib")
        for folder in [package, hostLibraries, toolchain.appendingPathComponent("bin"), output] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let source = package.appendingPathComponent("lib.rs")
        try Data("pub fn answer() -> u32 { 42 }".utf8).write(to: source)
        let compiler = toolchain.appendingPathComponent("bin/rustc")
        let escaped = source.path.replacingOccurrences(of: " ", with: "\\ ")
        try "artifact: \(escaped)\n".write(to: root.appendingPathComponent("probe.d"), atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        if [ "$1" = --print ]; then printf '%s\\n' '\(toolchain.path)' '\(hostLibraries.path)'; exit 0; fi
        for argument in "$@"; do
          case "$argument" in
            --emit=dep-info=*)
              paths=${argument#--emit=dep-info=}
              cp '\(root.path)/probe.d' "$paths"
              ;;
          esac
        done

        """.write(to: compiler, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: compiler.path)
        try Data("compiler runtime".utf8).write(to: toolchain.appendingPathComponent("lib/compiler"))
        let environment = [
            "CARGO_HOME": root.appendingPathComponent("cargo").path, "CARGO_MANIFEST_DIR": package.path,
            "TUIST_CARGO_CACHE_DIR": root.appendingPathComponent("cache").path,
            "TUIST_CARGO_CACHE_TOKEN_FILE": root.appendingPathComponent("cache-token").path,
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

        func cache(
            invocation: CargoCacheInvocation? = nil, remote: (any REAPICacheStoring)? = nil, directory: String = "cache"
        ) throws -> CargoCompilationCache {
            let invocation = invocation ?? self.invocation
            return try CargoCompilationCache(
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
    private var unavailable = false
    private(set) var uploadAttempts = 0
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
        uploadAttempts += 1
        if denyWrites { throw REAPICacheError.uploadFailed(reason: "Permission denied") }
        if rejectUploads { return REAPIBlobUpload(available: []) }
        for (digest, file) in files {
            blobs[digest] = try Data(contentsOf: file)
        }
        return REAPIBlobUpload(available: Set(files.keys), uploaded: Set(files.keys))
    }

    func uploadBlobs(_ files: [REAPI.Digest: URL]) async throws { _ = try await uploadAvailableBlobs(files) }
    func downloadBlobs(_ files: [REAPI.Digest: URL]) async throws -> REAPIBlobDownload {
        if unavailable { return REAPIBlobDownload(available: [], remoteFailures: Set(files.keys)) }
        return try await REAPIBlobDownload(available: downloadAvailableBlobs(files))
    }

    func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        reads += 1
        let data = try #require(blobs[digest])
        try (corrupt ? Data("corrupt".utf8) : data).write(to: path)
    }

    func setCompilerStreams(stdout: Data, stderr: Data) {
        result?.stdoutRaw = stdout
        result?.stderrRaw = stderr
    }

    func corruptDownloads(_ enabled: Bool = true) { corrupt = enabled }
    func failDownloads() { unavailable = true }
    func escapeOutputPath() { result?.outputFiles[0].path = "../escape" }
}
