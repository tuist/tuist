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

    @Test func remappingFlagsAreTheSameWhereverTheCheckoutIs() {
        let sysroot = URL(fileURLWithPath: "/toolchains/1.99-aarch64-apple-darwin")
        func relocation(_ workspace: String) -> CargoRelocation {
            CargoRelocation(
                environment: [
                    "CARGO_HOME": "/home/cargo",
                    "TUIST_CARGO_WORKSPACE_ROOT": workspace,
                    "TUIST_CARGO_TARGET_DIR": workspace + "/target",
                ],
                sysroot: sysroot
            )
        }
        // One target directory is shorter than the sysroot, the other longer.
        let short = relocation("/tmp/w")
        let long = relocation("/tmp/a-checkout-whose-path-is-long")
        #expect(short.remapArguments.map { short.relative($0) } == long.remapArguments.map { long.relative($0) })
        #expect(short.relative("/private/tmp/w/target/debug/x /tmp/w/src") == "@@TUIST_TARGET@@/debug/x @@TUIST_WORKSPACE@@/src")
        // An empty compilation directory drops a crate's objects from a linked binary's debug map.
        #expect(short.remapArguments.contains("--remap-path-prefix=/tmp/w=."))
        #expect(short.debugPrefixMapArguments.contains("-fdebug-prefix-map=/tmp/w=."))
    }

    @Test func bundlesDebugInformationOnlyForLinksWhoseDebugMapNamesObjects() {
        let unpacked = ["rustc", "-C", "debuginfo=2", "-C", "split-debuginfo=unpacked"]
        #expect(CargoRecordedInvocation.hasDebugMap(unpacked))
        #expect(CargoRecordedInvocation.hasDebugMap(["rustc", "-Cdebuginfo=line-tables-only", "-Csplit-debuginfo=unpacked"]))
        #expect(!CargoRecordedInvocation.hasDebugMap(unpacked + ["-C", "debuginfo=0"]))
        #expect(!CargoRecordedInvocation.hasDebugMap(unpacked + ["-C", "strip=debuginfo"]))
        #expect(!CargoRecordedInvocation.hasDebugMap(["rustc", "-C", "debuginfo=2", "-C", "split-debuginfo=packed"]))
        #expect(!CargoRecordedInvocation.hasDebugMap(["rustc", "-C", "split-debuginfo=unpacked"]))
        #expect(!CargoRecordedInvocation.hasDebugMap(unpacked + ["-Cstrip=symbols"]))
        // The last of `-g` and `-C debuginfo` wins, as in rustc.
        #expect(CargoRecordedInvocation.hasDebugMap(["rustc", "-C", "debuginfo=0", "-g", "-C", "split-debuginfo=unpacked"]))
        #expect(!CargoRecordedInvocation.hasDebugMap(["rustc", "-g", "-C", "debuginfo=0", "-C", "split-debuginfo=unpacked"]))
        // rustc's other spellings of the same options.
        #expect(CargoRecordedInvocation.hasDebugMap(["rustc", "--codegen", "debuginfo=2", "--codegen=split_debuginfo=unpacked"]))
        #expect(!CargoRecordedInvocation.hasDebugMap(unpacked + ["--codegen", "split_debuginfo=packed"]))
    }

    @Test(.inTemporaryDirectory) func compilesAUnitWithoutIncrementalCompilationOnlyTheFirstTimeItsTargetCompilesIt() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        func unit(_ name: String, _ hash: String) -> [String] {
            ["rustc", "--crate-name", name, "-C", "incremental=target/debug/incremental", "-C", "extra-filename=-\(hash)"]
                + ["lib.rs"]
        }
        let library = unit("app", "0123456789abcdef")
        #expect(
            CargoCacheInputs.withoutFirstIncrementalSession(library, directory: directory)
                == ["rustc", "--crate-name", "app", "-C", "extra-filename=-0123456789abcdef", "lib.rs"]
        )
        // Its next compilation is the one an edit starts, which builds the session the following edits reuse.
        #expect(CargoCacheInputs.withoutFirstIncrementalSession(library, directory: directory) == library)
        // Another unit of the same crate, such as its tests, has its own first compilation.
        let tests = unit("app", "fedcba9876543210")
        #expect(CargoCacheInputs.withoutFirstIncrementalSession(tests, directory: directory) != tests)
        // A session from an earlier build is reused, including one of a crate whose name another crate's starts with.
        let sessions = URL(fileURLWithPath: directory.pathString).appendingPathComponent("target/debug/incremental")
        try FileManager.default.createDirectory(
            at: sessions.appendingPathComponent("core-1z2y3x"), withIntermediateDirectories: true
        )
        let core = unit("core", "00000000000000aa")
        #expect(CargoCacheInputs.withoutFirstIncrementalSession(core, directory: directory) == core)
        let plugins = unit("core_plugins", "00000000000000bb")
        #expect(CargoCacheInputs.withoutFirstIncrementalSession(plugins, directory: directory) != plugins)
    }

    @Test(.inTemporaryDirectory) func leavesOnlyTheDebugBundleOutOfTheRootScan() throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let workspace = root.appendingPathComponent("ws")
        let output = workspace.appendingPathComponent("target/debug/build/app/out")
        let relocation = CargoRelocation(
            environment: ["CARGO_HOME": root.appendingPathComponent("cargo").path, "TUIST_CARGO_WORKSPACE_ROOT": workspace.path],
            sysroot: root.appendingPathComponent("toolchain")
        )
        let files = ["app"] + CargoRecordedInvocation.debugBundleFiles("app") + ["app.d"]
        let invocation = CargoRecordedInvocation(
            arguments: ["rustc"], environment: [:], directory: try AbsolutePath(validating: workspace.path), output: output,
            name: "app", files: files, key: REAPI.emptyBlob, declared: REAPI.emptyBlob, reads: nil, relocation: relocation,
            inputHasher: CargoInputHasher(sessionDirectory: nil), recorder: "", toolchain: root, externs: [],
            linksWithSystemLinker: true, debugBundle: "app.dSYM", program: "rustc"
        )
        // Both name the checkout; only the binary's bytes can depend on it.
        for file in files.prefix(3) {
            let path = output.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("comp_dir \(workspace.path)/app/src".utf8).write(to: path)
        }
        #expect(try invocation.unkeyedRoots(in: output.appendingPathComponent(files[2])).isEmpty)
        // macOS names a temporary directory through `/var` and `/private/var`, so either spelling may be reported.
        let bound = try invocation.unkeyedRoots(in: output.appendingPathComponent(files[0]))
        #expect(!bound.isEmpty && Set(bound.map(relocation.relative)) == ["@@TUIST_WORKSPACE@@"])
    }

    @Test(.inTemporaryDirectory) func restoresALinkedBinaryWithItsDebugBundleReplacingAnEarlierOne() async throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let output = root.appendingPathComponent("out")
        let binary = LinkedBinary(output: output, files: ["app"] + CargoRecordedInvocation.debugBundleFiles("app") + ["app.d"])
        for file in binary.files {
            let path = output.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.utf8).write(to: path)
        }
        let cache = try CargoCompilationCache(
            invocation: binary, root: root.appendingPathComponent("cache"), remote: nil,
            measurement: CargoCacheMeasurement(invocation: binary)
        )
        try await cache.store(stdout: Data(), stderr: Data())

        // A link where the bundle goes is replaced, never written through.
        try FileManager.default.removeItem(at: output)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: output.appendingPathComponent("app.dSYM"), withDestinationURL: elsewhere)
        #expect(try await cache.restore())
        for file in binary.files {
            #expect(try Data(contentsOf: output.appendingPathComponent(file)) == Data(file.utf8))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
        #expect(FileManager.default.isExecutableFile(atPath: output.appendingPathComponent("app").path))

        // An earlier bundle's other files do not stay beside the restored ones.
        let stale = output.appendingPathComponent("app.dSYM/Contents/Resources/DWARF/old")
        try Data("stale".utf8).write(to: stale)
        #expect(try await cache.restore())
        #expect(!FileManager.default.fileExists(atPath: stale.path))
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

    @Test(.inTemporaryDirectory) func buildsCompilingTheSameKeyWaitForEachOtherWithinABound() async throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let owner = try #require(try await CargoFlight.join(root: root, key: "same"))
        #expect(owner.waited == 0)
        let other = try #require(try await CargoFlight.join(root: root, key: "other"), "another key must not wait")
        #expect(other.waited == 0)
        other.release()
        #expect(try await CargoFlight.join(root: root, key: "same", maximumWait: 0.05) == nil)
        let waiter = Task { try await CargoFlight.join(root: root, key: "same", maximumWait: 30) }
        try await Task.sleep(nanoseconds: 100_000_000)
        owner.release()
        let next = try #require(try await waiter.value, "a waiter must take the key over once its owner releases it")
        #expect(next.waited > 0)
        #expect(
            try await CargoFlight.join(root: root, key: "same", maximumWait: 0.05) == nil,
            "the build that took the key over must hold it against the next one"
        )
        next.release()
        #expect(try await CargoFlight.join(root: root, key: "same") != nil)
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
        // An incremental compilation leaves one object per codegen unit, 256 of them.
        let objects = (0 ..< 256).map { fixture.output.appendingPathComponent("tiny-123.tiny.abc\($0)-cgu.0.rcgu.o") }
        for (index, object) in objects.enumerated() {
            try Data("debug object \(index)".utf8).write(to: object)
        }
        let cache = try fixture.cache()
        try await cache.store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        for object in objects {
            try FileManager.default.removeItem(at: object)
        }
        #expect(try await cache.restore())
        #expect(try Data(contentsOf: objects[255]) == Data("debug object 255".utf8))
    }

    @Test(.inTemporaryDirectory) func recordedRunsLeaveOutWhatModeledProgramsStart() throws {
        // Without SIP, `/usr/bin/git` loads the recorder, runs Xcode's git, which forks a helper; the run also forks
        // and execs `xcrun` itself, whose answer must stay keyed.
        let directory = try #require(FileSystem.temporaryTestDirectory)
        func query(_ program: String, _ arguments: String...) -> String {
            ([program, "/work", ""] + arguments).joined(separator: "\u{1f}")
        }
        let events = [
            "100\tP\t/work/target/build/script", "100\tp\t99",
            "100\tQ\t" + query("/usr/bin/git", "git", "rev-parse", "HEAD"),
            "101\tP\t/usr/bin/git", "101\tp\t100",
            "101\tJ\t" + query("/xcode/bin/git", "git", "rev-parse", "HEAD"), "101\tF\t",
            "101\tP\t/xcode/bin/git", "101\tp\t100",
            "102\tJ\t" + query("/xcode/libexec/git-helper", "git-helper"), "102\tF\t",
            "102\tP\t/xcode/libexec/git-helper", "102\tp\t101", "102\tF\t", "101\tF\t",
            "103\tJ\t" + query("/usr/bin/xcrun", "xcrun", "--show-sdk-path"), "103\tF\t",
            "103\tP\t/usr/bin/xcrun", "103\tp\t100", "103\tF\t",
        ]
        // The recorder buffers events: a process that never logged `F` may have read more than its log says.
        let finished = events + ["100\tF\t"]
        func parse(_ events: [String]) throws -> CargoReadSet? {
            let log = URL(fileURLWithPath: directory.appending(component: UUID().uuidString).pathString)
            try Data((events.joined(separator: "\n") + "\n").utf8).write(to: log)
            return CargoReadSet.parse(
                log: log, relocation: CargoRelocation(environment: [:], sysroot: URL(fileURLWithPath: "/toolchain")),
                excludedRoots: [], targetDirectory: nil, allowedWrites: [], keyedEnvironment: { _ in true }
            )
        }
        let reads = try #require(try parse(finished))
        #expect(reads.entries.filter { $0.kind == "command" }.map { $0.name.split(separator: "\u{1f}")[0] }.sorted()
            == ["/usr/bin/git", "/usr/bin/xcrun"])
        #expect(try parse(finished + ["100\tX\t/bin/unrecorded"]) == nil)
        #expect(try parse(events) == nil)
        // A failed exec continues the program it sealed, which must finish again.
        #expect(try parse(finished + ["100\tZ\t/usr/bin/missing"]) == nil)
        #expect(try parse(finished + ["100\tZ\t/usr/bin/missing", "100\tF\t"]) != nil)
    }

    @Test(.inTemporaryDirectory) func recordedRunsKeyWhatTheyReadAsOfTheirStart() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory).pathString
        let workspace = directory + "/workspace"
        let git = workspace + "/.git"
        try FileManager.default.createDirectory(atPath: git, withIntermediateDirectories: true)
        try Data("7\n".utf8).write(to: URL(fileURLWithPath: workspace + "/value.txt"))
        let relocation = CargoRelocation(
            environment: ["TUIST_CARGO_WORKSPACE_ROOT": workspace], sysroot: URL(fileURLWithPath: "/toolchain")
        )
        #if os(Linux)
            // A placeholder must give back the path that was read: Linux has no `/private` spelling of a checkout.
            #expect(relocation.absolute(relocation.relative(workspace + "/value.txt")) == workspace + "/value.txt")
        #endif
        let log = URL(fileURLWithPath: directory + "/reads.log")
        func parse(_ lines: [String]) throws -> CargoReadSet? {
            try Data((["100\tP\t/toolchain/bin/rustc", "100\tp\t99"] + lines + ["100\tF\t"]).joined(separator: "\n").utf8
                + Data("\n".utf8)).write(to: log)
            return CargoReadSet.parse(
                log: log, relocation: relocation, excludedRoots: [], targetDirectory: nil, allowedWrites: [],
                keyedEnvironment: { _ in true }
            )
        }
        let reads = try #require(try parse([
            "100\tR\t\(workspace)/value.txt", "100\tS\t\(git)",
            // Thread-pool sizing on Linux, whose times are always now.
            "100\tR\t/proc/self/cgroup", "100\tD\t/proc/self/fd", "100\tA\t/sys/fs/cgroup/cpu.max", "100\tR\t/proc/cpuinfo",
            // The process's own variables, read as a file.
            "100\tR\t/proc/thread-self/environ",
        ]))
        #expect(reads.entries.map { "\($0.kind) \($0.name)" }.sorted() == [
            "environment *", "path /proc/cpuinfo", "path @@TUIST_WORKSPACE@@/.git", "path @@TUIST_WORKSPACE@@/value.txt",
        ])
        // Another process's view of the file system, which a lookup here would not see.
        #expect(try parse(["100\tR\t/proc/self/cwd/value.txt"]) == nil)
        #expect(try parse(["100\tS\t/proc/4242/root\(workspace)/value.txt"]) == nil)
        let created = workspace + "/created"
        let files = CargoReadSet(
            entries: reads.entries.filter { $0.name != "/proc/cpuinfo" }
                + [CargoReadSet.Entry(kind: "path", name: "@@TUIST_WORKSPACE@@/created")]
        )
        let started = Date()
        Thread.sleep(forTimeInterval: 0.01)
        // git creates files in `.git` while a query runs; a directory only looked up is not what the run read.
        try Data().write(to: URL(fileURLWithPath: git + "/index.lock"))
        #expect(files.changedInput(since: started, relocation: relocation) == nil)
        // A directory that appeared while the run read its path, which may then have named something else.
        try FileManager.default.createDirectory(atPath: created, withIntermediateDirectories: false)
        #expect(files.changedInput(since: started, relocation: relocation) == "@@TUIST_WORKSPACE@@/created")
        try FileManager.default.removeItem(atPath: created)
        try Data("9\n".utf8).write(to: URL(fileURLWithPath: workspace + "/value.txt"))
        #expect(files.changedInput(since: started, relocation: relocation) == "@@TUIST_WORKSPACE@@/value.txt")
    }

    @Test(.inTemporaryDirectory) func remembersOutputScansOnlyWhileTheOutputIsUnchanged() throws {
        // Publication and unit collection scan the same outputs; a rewritten output must be scanned again.
        let directory = try #require(FileSystem.temporaryTestDirectory).pathString
        let relocation = CargoRelocation(
            environment: ["CARGO_HOME": "/cargo-home", "TUIST_CARGO_WORKSPACE_ROOT": directory + "/workspace"],
            sysroot: URL(fileURLWithPath: "/toolchain")
        )
        let output = URL(fileURLWithPath: directory + "/libexample.rlib")
        try Data("path-free".utf8).write(to: output)
        #expect(try relocation.boundRoots(of: output).isEmpty)
        try Data("built in \(directory)/workspace/src".utf8).write(to: output)
        #expect(try relocation.boundRoots(of: output).map(\.placeholder) == ["@@TUIST_WORKSPACE@@"])
        #expect(try relocation.boundRoots(of: output).map(\.placeholder) == ["@@TUIST_WORKSPACE@@"])
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
        // Keys hold the entries of every directory holding a source, so not the fixture's root, which holds the cache.
        let generated = fixture.root.appendingPathComponent("generated/generated.rs")
        try FileManager.default.createDirectory(at: generated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pub fn generated() {}".utf8).write(to: generated)
        let report = "artifact: \(fixture.source.path) \(generated.path)\n"
        let arguments = fixture.invocation.arguments + [
            "--extern", "dependency=\(dependency.path)", "-L", "dependency=\(fixture.output.path)",
        ]
        let deferred = try #require(await fixture.prepare(arguments: arguments))
        #expect(deferred.isDeferred)
        let depInfo = fixture.output.appendingPathComponent(fixture.invocation.files[2])
        let fixtureDepInfo = try Data(contentsOf: depInfo)
        try report.write(to: depInfo, atomically: true, encoding: .utf8)
        let refreshed = deferred.refreshed()
        let original = try #require(refreshed.keyed)
        await deferred.remember(try #require(refreshed.sources), remote: nil)
        try fixtureDepInfo.write(to: depInfo)
        #expect(original.compilerInputs?.sources.map(\.lastPathComponent).sorted() == ["generated.rs", "lib.rs"])
        #expect(try await fixture.prepare(arguments: arguments)?.key == original.key)
        try Data("unrelated".utf8).write(to: dependency.deletingLastPathComponent().appendingPathComponent("unrelated.rlib"))
        #expect(try await fixture.prepare(arguments: arguments)?.key == original.key)
        try Data("pub fn changed() {}".utf8).write(to: generated)
        #expect(try await fixture.prepare(arguments: arguments)?.key != original.key)
        try Data("pub fn generated() {}".utf8).write(to: generated)
        try Data("changed dependency".utf8).write(to: dependency)
        await #expect(throws: CargoCacheInvocation.CacheError.self) { try await fixture.prepare(arguments: arguments) }
        try fixture.invocation.certifyOutputs()
        #expect(try await fixture.prepare(arguments: arguments)?.isDeferred == true)
    }

    @Test(.inTemporaryDirectory) func inspectsIncludedNonRustFilesBeforeCertifyingRegistryLibraries() async throws {
        let fixture = try await fixture()
        let included = fixture.source.deletingLastPathComponent().appendingPathComponent("generated.txt")
        try Data("include!(\"generated.txt\");".utf8).write(to: fixture.source)
        try "artifact: \(fixture.source.path) \(included.path)\n".write(
            to: fixture.output.appendingPathComponent(fixture.invocation.files[2]), atomically: true, encoding: .utf8
        )
        func keyed(_ content: Data) async throws -> CargoCacheInvocation? {
            try content.write(to: included)
            let invocation = try #require(await fixture.prepare())
            #expect(invocation.isDeferred)
            return invocation.keyedFromDepInfo()
        }
        #expect(try await keyed(Data("pub fn generated() {}".utf8)) != nil)
        #expect(try await keyed(Data("core::arch::global_asm!(\".include \\\"hidden.s\\\"\");".utf8)) == nil)
        #expect(try await keyed(Data(repeating: 65, count: 2_000_000)) != nil)
        #expect(try await keyed(Data(repeating: 65, count: 2_000_001)) == nil)
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
            // CI commonly sets it; Cargo already folds it into `-C metadata` where it changes outputs.
            "CARGO_INCREMENTAL",
        ] {
            var environment = fixture.invocation.environment
            environment[variable] = "another-invocation"
            #expect(try await fixture.prepare(environment: environment)?.key == fixture.invocation.key)
        }
    }

    @Test(.inTemporaryDirectory) func neverCachesCratesThatReadExcludedCredentialsOrCIMetadata() async throws {
        let fixture = try await fixture()
        for variable in [
            "TUIST_TOKEN", "TUIST_DEBUG", "GITHUB_RUN_ID", "CI_JOB_ID", "CI", "RUNNER_TRACKING_ID", "SHLVL", "CARGO_INCREMENTAL",
        ] {
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

    @Test(.inTemporaryDirectory) func incrementalCompilationsShareEntriesWithNonIncrementalOnes() async throws {
        let fixture = try await fixture()
        let incremental = try #require(await fixture.prepare(
            arguments: fixture.invocation.arguments + ["-C", "incremental=\(fixture.root.path)/incremental"]
        ))
        #expect(incremental.key == fixture.invocation.key)
        let joined = try #require(await fixture.prepare(
            arguments: fixture.invocation.arguments + ["-Cincremental=\(fixture.root.path)/elsewhere"]
        ))
        #expect(joined.key == fixture.invocation.key)
        let optimized = try #require(await fixture.prepare(arguments: fixture.invocation.arguments + ["-C", "opt-level=3"]))
        #expect(optimized.key != fixture.invocation.key)
        try await fixture.cache(invocation: incremental).store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        #expect(try await fixture.cache().restoreLocally())
    }

    @Test(.inTemporaryDirectory) func diagnosticsReplayOnlyAtTheirWidthAndUnexpectedStreamsAreNeverCached() async throws {
        let fixture = try await fixture()
        try await fixture.cache().store(stdout: Data(), stderr: Data("warning: terminal-specific rendering".utf8))
        #expect(try await fixture.cache().restoreLocally() == false)
        try await fixture.cache().store(stdout: Data("unexpected compiler output".utf8), stderr: Data())
        #expect(try await fixture.cache().restoreLocally() == false)
        let narrow = try #require(await fixture.prepare(arguments: fixture.invocation.arguments + ["--diagnostic-width=80"]))
        let diagnostic = Data(#"{"$message_type":"diagnostic","rendered":"warning: narrow terminal"}"#.utf8)
        try await fixture.cache(invocation: narrow).store(stdout: Data(), stderr: diagnostic)
        try fixture.removeOutputs()
        #expect(try await fixture.cache().restoreLocally() == false)
        #expect(try await fixture.cache(invocation: narrow).restoreLocally())
    }

    @Test(.inTemporaryDirectory) func renderedDiagnosticsKeepAnEntryPerWidth() async throws {
        let fixture = try await fixture()
        let warning = #"{"$message_type":"diagnostic","rendered":"warning: unused variable"}"#
        func cache(_ width: String?) async throws -> CargoCompilationCache {
            let options = width.map { ["--diagnostic-width=\($0)"] } ?? []
            return try fixture.cache(invocation: try #require(await fixture.prepare(
                arguments: fixture.invocation.arguments + options
            )))
        }
        // A piped build and terminals of two widths render the same warning; none replaces another's entry.
        for width in [nil, "80", "140"] {
            try await cache(width).store(stdout: Data(), stderr: Data(warning.utf8))
        }
        for width in [nil, "80", "140"] {
            try fixture.removeOutputs()
            var restoring = try await cache(width)
            var replayed = Data()
            restoring.replay = { _, stderr in replayed = stderr }
            #expect(try await restoring.restoreLocally())
            #expect(String(decoding: replayed, as: UTF8.self) == warning)
        }
        try fixture.removeOutputs()
        #expect(try await cache("100").restoreLocally() == false)

        // A future-incompatibility report holds rendered warnings too.
        let reported = try await self.fixture()
        let narrow = try #require(await reported.prepare(arguments: reported.invocation.arguments + ["--diagnostic-width=80"]))
        let report = #"{"$message_type":"future_incompat","future_incompat_report":[{"diagnostic":{"rendered":"warning: x"}}]}"#
        try await reported.cache(invocation: narrow).store(stdout: Data(), stderr: Data(report.utf8))
        try reported.removeOutputs()
        #expect(try await reported.cache().restoreLocally() == false)
        #expect(try await reported.cache(invocation: narrow).restoreLocally())
    }

    @Test(.inTemporaryDirectory) func frontEndThreadCountsShareEntries() async throws {
        let fixture = try await fixture()
        func prepared(_ options: [String]) async throws -> CargoCacheInvocation? {
            try await fixture.prepare(arguments: fixture.invocation.arguments + options)
        }
        let eight = try #require(await prepared(["-Zthreads=8"]))
        try await fixture.cache(invocation: eight).store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        for options in [["-Zthreads=1"], ["-Z", "threads=0"], ["-Zthreads=255"]] {
            #expect(try await prepared(options)?.key == eight.key)
        }
        #expect(try await fixture.cache(invocation: try #require(await prepared(["-Z", "threads=16"]))).restoreLocally())
        // A toolchain that rejects `-Z` fails with the option, so builds without it keep their own entries.
        #expect(eight.key != fixture.invocation.key)
        // rustc rejects these, and a cached success must not hide that; other unstable options stay unsupported.
        for options in [
            ["-Zthreads=256"], ["-Zthreads=x"], ["-Zthreads"], ["-Z", "threads"], ["-Zthreads=8", "-Zthreads=8"],
            ["-Zthreads=8", "-Zshare-generics=y"],
        ] {
            #expect(try await prepared(options) == nil)
        }
        // Recorded compilations admit other unstable options and key the same arguments.
        let keyed = CargoCacheInputs.keyArguments
        #expect(keyed(["-Zthreads=8", "-Zfoo"]) == keyed(["-Z", "threads=3", "-Zfoo"]))
        #expect(keyed(["-Zthreads=x"]) != keyed(["-Zthreads=8"]))
        #expect(keyed(["-Zthreads=8", "-Zthreads=8"]) != keyed(["-Zthreads=8"]))
        // rustc fails when the count exceeds a job limit, which `-Z unstable-options` makes available.
        for jobs in [["-j4"], ["-j", "4"], ["--jobs=4"], ["--jobs", "4"], ["--jobs-frontend=4"]] {
            let limited = ["-Zunstable-options"] + jobs
            #expect(keyed(limited + ["-Zthreads=2"]) != keyed(limited + ["-Zthreads=8"]))
            #expect(try await prepared(["-Zthreads=2"] + jobs) == nil)
        }
    }

    @Test(.inTemporaryDirectory) func packageMetadataKeysOnlyCratesThatReadIt() async throws {
        let fixture = try await fixture()
        var environment = fixture.invocation.environment
        // Outside Cargo home's registry, a crate is keyed by the sources and variables its dep-info names.
        environment["CARGO_HOME"] = fixture.root.appendingPathComponent("home").path
        environment["CARGO_PKG_DESCRIPTION"] = "first"
        environment["CARGO_PKG_AUTHORS"] = "someone"
        // A module other than the crate root, so editing it keeps the remembered source list.
        let module = fixture.source.deletingLastPathComponent().appendingPathComponent("about.rs")
        try Data("pub fn about() {}".utf8).write(to: module)
        let paths = [fixture.source, module].map { $0.path.replacingOccurrences(of: " ", with: "\\ ") }
        var depInfo = "artifact: \(paths.joined(separator: " "))\n"
        func writeOutputs() throws {
            try Data("library".utf8).write(to: fixture.output.appendingPathComponent(fixture.invocation.files[0]))
            try Data("metadata".utf8).write(to: fixture.output.appendingPathComponent(fixture.invocation.files[1]))
            try depInfo.write(
                to: fixture.output.appendingPathComponent(fixture.invocation.files[2]), atomically: true, encoding: .utf8
            )
        }
        func compile() async throws {
            try writeOutputs()
            let prepared = try #require(await fixture.prepare(environment: environment))
            let refreshed = prepared.refreshed()
            if let sources = refreshed.sources { await prepared.remember(sources, remote: nil) }
            try await fixture.cache(invocation: try #require(refreshed.keyed))
                .store(stdout: Data(), stderr: Data(), keyedAfterCompiling: true)
        }
        func restores() async throws -> Bool {
            let prepared = try #require(await fixture.prepare(environment: environment))
            for file in fixture.invocation.files {
                try? FileManager.default.removeItem(at: fixture.output.appendingPathComponent(file))
            }
            return try await fixture.cache(invocation: prepared).restoreLocally()
        }
        try await compile()
        environment["CARGO_PKG_DESCRIPTION"] = "second"
        environment["CARGO_PKG_AUTHORS"] = "someone else"
        environment["CARGO_PRIMARY_PACKAGE"] = "1"
        #expect(try await restores())
        // The crate starts embedding its description: the remembered sources are the same, the variables are not.
        try Data(#"pub const ABOUT: &str = env!("CARGO_PKG_DESCRIPTION");"#.utf8).write(to: module)
        depInfo += "# env-dep:CARGO_PKG_DESCRIPTION=second\n"
        // Keyed by the remembered list, which does not name the variable rustc says the crate read: never published.
        try writeOutputs()
        let stale = try #require(await fixture.prepare(environment: environment))
        #expect(!stale.isDeferred)
        await #expect(throws: CargoCacheInvocation.CacheError.self) {
            try await fixture.cache(invocation: stale).store(stdout: Data(), stderr: Data())
        }
        try await compile()
        environment["CARGO_PKG_DESCRIPTION"] = "third"
        #expect(try await restores() == false)
        environment["CARGO_PKG_DESCRIPTION"] = "second"
        #expect(try await restores())
        // rustc reads the version itself.
        environment["CARGO_PKG_VERSION_MINOR"] = "2"
        #expect(try await restores() == false)
    }

    @Test(.inTemporaryDirectory) func recordedCompilationsKeyPackageMetadataTheyRead() async throws {
        let fixture = try await fixture()
        func key(description: String, reading: Bool) async throws -> REAPI.Digest {
            var environment = fixture.invocation.environment
            environment["TUIST_CARGO_RECORDER"] = fixture.root.appendingPathComponent("recorder.dylib").path
            environment["CARGO_PKG_DESCRIPTION"] = description
            let invocation = try #require(await CargoRecordedInvocation.prepare(
                fixture.invocation.arguments, environment: environment, directory: fixture.invocation.directory,
                process: CargoProcess(runner: CommandRunner())
            ))
            // What the recorder logs when a proc macro calls `std::env::var("CARGO_PKG_DESCRIPTION")`.
            let events = ["100\tP\t\(fixture.invocation.compiler.path)"]
                + (reading ? ["100\tE\tCARGO_PKG_DESCRIPTION"] : []) + ["100\tF\t"]
            let log = fixture.root.appendingPathComponent(UUID().uuidString + ".log")
            try Data((events.joined(separator: "\n") + "\n").utf8).write(to: log)
            return try #require(invocation.recorded(log: log, started: Date())).key
        }
        #expect(try await key(description: "first", reading: false) == key(description: "second", reading: false))
        #expect(try await key(description: "first", reading: true) != key(description: "second", reading: true))
    }

    @Test(.inTemporaryDirectory) func cachesAndReplaysUnusedExternReports() async throws {
        let fixture = try await fixture()
        let report = #"{"$message_type":"unused_extern","lint_level":"force-warn","unused_extern_names":["itoa"]}"#
        try await fixture.cache().store(stdout: Data(), stderr: Data(report.utf8))
        try fixture.removeOutputs()
        var cache = try fixture.cache()
        var replayed = Data()
        cache.replay = { _, stderr in replayed = stderr }
        #expect(try await cache.restoreLocally())
        #expect(String(decoding: replayed, as: UTF8.self) == report)
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

    @Test(.inTemporaryDirectory) func remoteLookupsFindDiagnosticsRenderedAtTheirWidth() async throws {
        let fixture = try await fixture()
        let remote = CargoMemoryCache()
        let narrow = try #require(await fixture.prepare(arguments: fixture.invocation.arguments + ["--diagnostic-width=80"]))
        let piped = #"{"$message_type":"diagnostic","rendered":"warning: piped"}"#
        let rendered = #"{"$message_type":"diagnostic","rendered":"warning: at 80 columns"}"#
        func restores(_ invocation: CargoCacheInvocation, _ expected: String) async throws {
            // A machine with nothing local.
            try fixture.removeOutputs()
            var cache = try fixture.cache(invocation: invocation, remote: remote, directory: UUID().uuidString)
            var replayed = Data()
            cache.replay = { _, stderr in replayed = stderr }
            #expect(try await cache.restoreRemotely())
            #expect(String(decoding: replayed, as: UTF8.self) == expected)
        }
        try await fixture.cache(invocation: narrow, remote: remote).store(stdout: Data(), stderr: Data(rendered.utf8))
        // The key's own entry is missing, not merely unusable.
        try await restores(narrow, rendered)
        try await fixture.cache(remote: remote).store(stdout: Data(), stderr: Data(piped.utf8))
        // The key's entry holds the piped rendering, which a terminal build skips.
        try await restores(narrow, rendered)
        try await restores(fixture.invocation, piped)
        try fixture.removeOutputs()
        let wide = try #require(await fixture.prepare(arguments: fixture.invocation.arguments + ["--diagnostic-width=140"]))
        #expect(try await fixture.cache(invocation: wide, remote: remote, directory: "wide").restoreRemotely() == false)
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

    @Test(.inTemporaryDirectory) func admitsOnlyTheLoaderSearchPathCargoBuilds() async throws {
        let fixture = try await fixture()
        let toolchain = fixture.invocation.toolchain.path
        let target = fixture.root.appendingPathComponent("target").path
        let dylibUnit = target + "/debug/build/dylib/0123456789abcdef/out"
        let elsewhere = fixture.root.appendingPathComponent("elsewhere").path
        let linkedToolchain = fixture.root.appendingPathComponent("linked-toolchain").path
        let escaping = dylibUnit + "/native"
        for directory in [dylibUnit, elsewhere] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        // rustup names a linked toolchain through its link; a native search path inside the target can leave it.
        try FileManager.default.createSymbolicLink(atPath: linkedToolchain, withDestinationPath: toolchain)
        try FileManager.default.createSymbolicLink(atPath: escaping, withDestinationPath: elsewhere)
        let cases: [([String: String], Bool)] = [
            // Cargo started without rustup's proxy, through it, and with a dylib dependency's outputs.
            (["LD_LIBRARY_PATH": ""], true),
            (["LD_LIBRARY_PATH": toolchain + "/lib"], true),
            (["LD_LIBRARY_PATH": dylibUnit + ":" + toolchain + "/lib"], true),
            (["LD_LIBRARY_PATH": toolchain + "/lib/rustlib/host/lib"], true),
            (["LD_LIBRARY_PATH": linkedToolchain + "/lib"], true),
            (["LD_LIBRARY_PATH": escaping], false),
            (["LD_LIBRARY_PATH": dylibUnit + ";" + elsewhere], false),
            (["LD_LIBRARY_PATH": toolchain + "/lib;"], false),
            (["LD_LIBRARY_PATH": "/usr/local/lib:" + toolchain + "/lib"], false),
            (["LD_LIBRARY_PATH": toolchain], false),
            (["LD_LIBRARY_PATH": toolchain + "/lib/rustlib"], false),
            (["LD_LIBRARY_PATH": toolchain + "/lib:"], false),
            (["LD_LIBRARY_PATH": "lib"], false),
            (["LD_LIBRARY_PATH": target + "-other/out"], false),
            (["LD_LIBRARY_PATH": target + "/../elsewhere"], false),
            (["LD_LIBRARY_PATH": toolchain + "/lib", "LD_PRELOAD": toolchain + "/lib/compiler"], false),
            (["LD_AUDIT": toolchain + "/lib/compiler"], false),
            (["DYLD_FALLBACK_LIBRARY_PATH": toolchain + "/lib"], false),
        ]
        for (loader, admitted) in cases {
            let environment = fixture.invocation.environment
                .merging(["TUIST_CARGO_TARGET_DIR": target, "TUIST_CARGO_RECORDER": "/recorder"]) { $1 }
                .merging(loader) { $1 }
            #expect(try await (fixture.prepare(environment: environment) != nil) == admitted, "\(loader)")
            let recorded = try await CargoRecordedInvocation.prepare(
                fixture.invocation.arguments, environment: environment, directory: fixture.invocation.directory,
                process: CargoProcess(runner: CommandRunner())
            )
            #expect((recorded != nil) == admitted, "recorded \(loader)")
        }
        // Without a known target directory, no entry inside it is Cargo's.
        let unknown = fixture.invocation.environment.merging(["LD_LIBRARY_PATH": dylibUnit]) { $1 }
        #expect(try await fixture.prepare(environment: unknown) == nil)
    }

    @Test(.inTemporaryDirectory) func metadataOnlyCompilationsHaveTheirOwnCertifiedEntries() async throws {
        let fixture = try await fixture()
        let check = try #require(await fixture.prepare(arguments: fixture.checkArguments))
        #expect(check.files == ["libtiny-123.rmeta", "tiny-123.d"])
        #expect(check.key != fixture.invocation.key)
        try Data("check metadata".utf8).write(to: fixture.output.appendingPathComponent(check.files[0]))
        try await fixture.cache(invocation: check).store(stdout: Data(), stderr: Data())
        try fixture.removeOutputs()
        // A check never serves a compilation that links.
        #expect(try await fixture.cache().restoreLocally() == false)
        var environment = check.environment
        environment["TUIST_CARGO_SESSION"] = fixture.root.appendingPathComponent("next-session").path
        let restored = try #require(await fixture.prepare(arguments: fixture.checkArguments, environment: environment))
        #expect(try await fixture.cache(invocation: restored).restoreLocally())
        let metadata = fixture.output.appendingPathComponent(check.files[0])
        #expect(try Data(contentsOf: metadata) == Data("check metadata".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("libtiny-123.rlib").path))
        // Dependents in the new session accept the restored metadata as an extern.
        #expect(CargoCacheInputs.isCertified(try CargoInputHasher().digest(metadata), environment: environment))
    }

    @Test(.inTemporaryDirectory) func clippyCompilationsKeyTheDriverAndWhatItReads() async throws {
        let fixture = try await fixture()
        let driver = fixture.invocation.toolchain.appendingPathComponent("bin/clippy-driver")
        try "#!/bin/sh\necho 'clippy 0.1.99 (test)'\n".write(to: driver, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: driver.path)
        let check = try #require(await fixture.prepare(arguments: fixture.checkArguments))
        var environment = fixture.invocation.environment
        environment["RUSTC_WORKSPACE_WRAPPER"] = driver.path
        environment["CLIPPY_ARGS"] = "-W__CLIPPY_HACKERY__clippy::pedantic__CLIPPY_HACKERY__"
        // Cargo starts dependencies as rustc, which reads neither variable: they keep the entries of `cargo check`.
        #expect(try await fixture.prepare(arguments: fixture.checkArguments, environment: environment)?.key == check.key)
        func clippy(_ environment: [String: String], emit: [String]? = nil) async throws -> REAPI.Digest? {
            try await fixture.prepare(
                arguments: [environment["RUSTC_WORKSPACE_WRAPPER"] ?? driver.path] + (emit ?? fixture.checkArguments),
                environment: environment
            )?.key
        }
        var keys = [check.key, try #require(await clippy(environment))]
        environment["CLIPPY_ARGS"] = "-D__CLIPPY_HACKERY__clippy::pedantic__CLIPPY_HACKERY__"
        keys.append(try #require(await clippy(environment)))
        environment["CLIPPY_DISABLE_DOCS_LINKS"] = "1"
        keys.append(try #require(await clippy(environment)))
        // The configuration Clippy finds above the package, then a changed one.
        let configuration = fixture.invocation.package.deletingLastPathComponent().appendingPathComponent("clippy.toml")
        try "msrv = \"1.70\"\n".write(to: configuration, atomically: true, encoding: .utf8)
        keys.append(try #require(await clippy(environment)))
        try "msrv = \"1.80\"\n".write(to: configuration, atomically: true, encoding: .utf8)
        keys.append(try #require(await clippy(environment)))
        #expect(Set(keys).count == keys.count)
        #expect(try await clippy(environment) == keys.last)
        // Lints that run `cargo metadata`, a driver that links, and other workspace wrappers stay uncached.
        for lints in [
            "-W__CLIPPY_HACKERY__clippy::cargo__CLIPPY_HACKERY__", "-Wclippy::cargo__CLIPPY_HACKERY__",
            "-D__CLIPPY_HACKERY__clippy::multiple-crate-versions__CLIPPY_HACKERY__",
        ] {
            var cargoLints = environment
            cargoLints["CLIPPY_ARGS"] = lints
            #expect(try await clippy(cargoLints) == nil)
        }
        // The driver would compile against the standard library `SYSROOT` names.
        var sysroot = environment
        sysroot["SYSROOT"] = fixture.root.path
        #expect(try await clippy(sysroot) == nil)
        #expect(try await clippy(environment, emit: fixture.invocation.arguments) == nil)
        var other = environment
        other["RUSTC_WORKSPACE_WRAPPER"] = fixture.root.appendingPathComponent("clippy-driver").path
        try FileManager.default.copyItem(at: driver, to: URL(fileURLWithPath: try #require(other["RUSTC_WORKSPACE_WRAPPER"])))
        #expect(try await clippy(other) == nil)
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

        /// The invocation's arguments as `cargo check` passes them.
        var checkArguments: [String] {
            invocation.arguments.map { $0 == "--emit=dep-info,metadata,link" ? "--emit=dep-info,metadata" : $0 }
        }

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

/// A linked binary's compilation, keyed by nothing but its name.
private struct LinkedBinary: CargoCacheAction {
    let output: URL
    let files: [String]
    var cacheVersion: String { "test" }
    var arguments: [String] { ["rustc"] }
    var key: REAPI.Digest { REAPI.digest(Data("app".utf8)) }
    var environment: [String: String] { [:] }
    var name: String { "app" }
    var kind: String { "rust" }
    var executableOutput: String? { files[0] }
    func fingerprint() throws -> REAPI.Digest { key }
    func validateDependencies(restoring _: Bool) async throws {}
    func certifyOutputs(metadataOnly _: Bool) throws {}
    func outputFiles() throws -> [String] { files }
    func acceptsOutput(_ file: String) -> Bool { files.contains(file) }
}

private actor CargoMemoryCache: REAPICacheStoring {
    private var results: [REAPI.Digest: REAPI.ActionResult] = [:]
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

    func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult? {
        reads += 1
        return results[digest]
    }

    func containsActionResult(for digest: REAPI.Digest) async throws -> Bool { results[digest] != nil }

    func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws {
        results[digest] = result
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
        for digest in results.keys {
            results[digest]?.stdoutRaw = stdout
            results[digest]?.stderrRaw = stderr
        }
    }

    func corruptDownloads(_ enabled: Bool = true) { corrupt = enabled }
    func failDownloads() { unavailable = true }
    func escapeOutputPath() {
        for digest in results.keys {
            results[digest]?.outputFiles[0].path = "../escape"
        }
    }
}
