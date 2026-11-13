import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistProcess
import TuistTestSupport
@testable import TuistCargoCommand

struct CargoCoverageTests {
    @Test(arguments: [
        (["test"], false),
        (["test", "--workspace", "--no-fail-fast", "--features", "lib", "-j", "4"], false),
        (["test", "--release", "--", "--test-threads", "1", "--include-ignored"], false),
        (["+nightly", "test", "--target", "x86_64-unknown-linux-gnu"], false),
        (["nextest", "run", "--profile", "ci", "--retries", "2"], false),
        (["test", "cart"], true),
        (["test", "--", "cart::adds", "--exact"], true),
        (["test", "--", "--skip", "slow"], true),
        (["test", "--", "--ignored"], true),
        (["test", "-p", "store"], true),
        (["test", "-pstore"], true),
        (["test", "--package=store"], true),
        (["test", "--test", "api"], true),
        (["test", "--lib"], true),
        (["test", "--doc"], true),
        (["test", "--exclude", "store", "--workspace"], true),
        (["nextest", "run", "-E", "test(cart)"], true),
        (["nextest", "run", "--partition", "count:1/2"], true),
        (["nextest", "run", "--run-ignored", "only"], true),
        (["nextest", "run", "--run-ignored=default"], false),
        (["nextest", "run", "cart"], true),
    ])
    func narrowed(arguments: [String], expected: Bool) {
        #expect(CargoCoverage.narrowed(arguments) == expected)
    }

    @Test func partialWhenAFailureStoppedTheRun() {
        #expect(!CargoCoverage.partial(["test"], failed: false))
        #expect(CargoCoverage.partial(["test"], failed: true))
        #expect(!CargoCoverage.partial(["test", "--no-fail-fast"], failed: true))
        #expect(CargoCoverage.partial(["nextest", "run"], failed: true))
        #expect(!CargoCoverage.partial(["nextest", "run", "--max-fail", "all"], failed: true))
        #expect(CargoCoverage.partial(["test", "--no-fail-fast", "cart"], failed: false))
    }

    @Test func instrumentationKeepsTheProjectsFlags() {
        #expect(CargoCoverage.instrumented([:])["CARGO_BUILD_RUSTFLAGS"] == "-C instrument-coverage")
        #expect(
            CargoCoverage.instrumented(["CARGO_BUILD_RUSTFLAGS": "--cfg ci"])["CARGO_BUILD_RUSTFLAGS"]
                == "--cfg ci -C instrument-coverage"
        )
        // RUSTFLAGS replaces every configured flag, so the flag joins it rather than `build.rustflags`.
        let rustflags = CargoCoverage.instrumented(["RUSTFLAGS": "-D warnings"])
        #expect(rustflags["RUSTFLAGS"] == "-D warnings -C instrument-coverage")
        #expect(rustflags["CARGO_BUILD_RUSTFLAGS"] == nil)
        #expect(
            CargoCoverage.instrumented(["CARGO_ENCODED_RUSTFLAGS": "-D\u{1F}warnings"])["CARGO_ENCODED_RUSTFLAGS"]
                == "-D\u{1F}warnings\u{1F}-C\u{1F}instrument-coverage"
        )
        #expect(CargoCoverage
            .instrumented(["CARGO_ENCODED_RUSTFLAGS": ""])["CARGO_ENCODED_RUSTFLAGS"] == "-C\u{1F}instrument-coverage")
        #expect(
            CargoCoverage.instrumented(["RUSTFLAGS": "-C instrument-coverage"])["RUSTFLAGS"] == "-C instrument-coverage"
        )
    }

    @Test func requestedByConfigurationUnlessTheEnvironmentSaysOtherwise() {
        #expect(!CargoCoverage.requested(upload: false, environment: [:]))
        #expect(CargoCoverage.requested(upload: true, environment: [:]))
        #expect(!CargoCoverage.requested(upload: true, environment: ["TUIST_COVERAGE_UPLOAD": "0"]))
        #expect(CargoCoverage.requested(upload: false, environment: ["TUIST_COVERAGE_UPLOAD": "1"]))
    }

    @Test func identifiersEncodeSlashesInsideTheirParts() {
        #expect(
            CargoCoverage.identifier(module: "app::bin/tool", suite: "doctests", name: "src/lib.rs - add (line 4)")
                == "app::bin%2Ftool/doctests/src%2Flib.rs - add (line 4)"
        )
        #expect(CargoCoverage.identifier(module: "app", suite: "cart::tests", name: "adds_100%") == "app/cart::tests/adds_100%25")
    }

    @Test func rangesFlattenConsecutiveLines() {
        #expect(CargoCoverage.ranges([3, 4, 5, 9, 11, 12]) == [3, 5, 9, 9, 11, 12])
        #expect(CargoCoverage.ranges([]) == [])
    }

    @Test(arguments: [
        ("_RNvCshnd9XvarvH6_11cov_fixture3add", "cov_fixture::add", "cov_fixture::add"),
        ("_RINvCshnd9XvarvH6_11cov_fixture5applyppEB2_", "cov_fixture::apply::<_, _>", "cov_fixture::apply"),
        (
            "_RNvMNtCshnd9XvarvH6_11cov_fixture6shapesNtB2_6Square4area",
            "<cov_fixture::shapes::Square>::area",
            "<cov_fixture::shapes::Square>::area"
        ),
        (
            "_RINvCsk6n2xfjCQ68_11cov_fixture5applylNCNvNtCs5XdXOshBfAE_3api6common6helper0EBG_",
            "cov_fixture::apply::<i32, api::common::helper::{closure#0}>",
            "cov_fixture::apply"
        ),
        (
            "_RNvNtNtCshnd9XvarvH6_11cov_fixture6shapes5testss_4area",
            "cov_fixture::shapes::tests::area",
            "cov_fixture::shapes::tests::area"
        ),
        ("_ZN11cov_fixture3add17h0123456789abcdefE", "cov_fixture::add", "cov_fixture::add"),
        ("src/lib.rs;_RNvCshnd9XvarvH6_11cov_fixture3add", "cov_fixture::add", "cov_fixture::add"),
        ("not_a_rust_symbol", "not_a_rust_symbol", "not_a_rust_symbol"),
    ])
    func demangles(symbol: String, demangled: String, function: String) {
        #expect(CargoSymbol.demangle(symbol) == demangled)
        #expect(CargoSymbol.function(symbol) == function)
    }

    @Test(.inTemporaryDirectory) func filesMergeInstantiationsAndLeaveTestCodeOut() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory).pathString
        for file in ["src/lib.rs", "tests/api.rs"] {
            try FileManager.default.createDirectory(
                atPath: directory + "/" + (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: directory + "/" + file, contents: Data())
        }
        // A relative path is the workspace's, as the compilation cache's remapping writes it.
        let lcov = """
        SF:src/lib.rs
        FN:3,_RINvCshnd9XvarvH6_11cov_fixture5applyppEB2_
        FN:3,_RINvCsk6n2xfjCQ68_11cov_fixture5applylNCNvNtCs5XdXOshBfAE_3api6common6helper0EBG_
        FN:8,_RNvCshnd9XvarvH6_11cov_fixture3add
        FNDA:0,_RINvCshnd9XvarvH6_11cov_fixture5applyppEB2_
        FNDA:2,_RINvCsk6n2xfjCQ68_11cov_fixture5applylNCNvNtCs5XdXOshBfAE_3api6common6helper0EBG_
        FNDA:0,_RNvCshnd9XvarvH6_11cov_fixture3add
        DA:1,7
        DA:3,2
        DA:4,2
        DA:8,0
        DA:9,0
        end_of_record
        SF:\(directory)/tests/api.rs
        DA:2,1
        end_of_record
        SF:/rustc/58cf8f9c35b355199727627d07ae34a4e2846d67/library/core/src/option.rs
        DA:1,1
        end_of_record
        """
        let resolver = CargoCoverage.Resolver(
            packages: [CargoCoverage.Package(name: "cov-fixture", directory: directory, testSources: [])],
            workspaceRoot: directory, repositoryRoot: directory, workingDirectory: "/"
        )
        let files = CargoCoverage.files(CargoCoverage.LCOVFile.parse(Data(lcov.utf8)), resolver: resolver)

        #expect(files.map { $0["path"] as? String } == ["src/lib.rs", "tests/api.rs"])
        let library = files[0]
        #expect(library["targets"] as? [String] == ["cov-fixture"])
        #expect(library["is_test"] as? Bool == false)
        #expect(library["covered_lines"] as? Int == 3)
        #expect(library["executable_lines"] as? Int == 5)
        #expect(library["line_numbers"] as? [Int] == [1, 3, 4, 8, 9])
        #expect(library["execution_counts"] as? [Int] == [7, 2, 2, 0, 0])
        let functions = try #require(library["functions"] as? [[String: Any]])
        // Line 1 starts before any function, so no function owns it.
        #expect(functions.map { $0["name"] as? String } == ["cov_fixture::apply", "cov_fixture::add"])
        #expect(functions.map { $0["execution_count"] as? Int } == [2, 0])
        #expect(functions.map { $0["covered_lines"] as? Int } == [2, 0])
        #expect(functions.map { $0["executable_lines"] as? Int } == [2, 2])

        let tests = files[1]
        #expect(tests["is_test"] as? Bool == true)
        #expect(tests["covered_lines"] as? Int == 1)
        #expect(tests["line_numbers"] as? [Int] == [])
    }

    @Test(.inTemporaryDirectory) func archiveBuiltInAnotherCheckoutResolvesToThisOne() throws {
        let temporary = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString).path
        // The build job's checkout, spelled as Cargo spells it (`/private/var/...` on macOS), and this worker's.
        let spelled = !temporary.hasPrefix("/private/") && FileManager.default.fileExists(atPath: "/private" + temporary)
            ? "/private" + temporary : temporary
        let build = spelled + "/build/ws"
        let directory = temporary + "/worker"
        for path in ["crates/a/src/lib.rs", "crates/b/src/lib.rs", "shared/util.rs"] {
            for root in [build, directory] {
                let url = URL(fileURLWithPath: "\(root)/\(path)")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: url)
            }
        }
        let listing = """
        {"rust-suites": {
          "a": {"binary-id": "a", "binary-path": "/x/a-1", "package-id": "path+file://\(build)/crates/a#0.1.0",
                "cwd": "\(directory)/crates/a", "testcases": {}},
          "b::api": {"binary-id": "b::api", "binary-path": "/x/api-2", "package-id": "path+file://\(build)/crates/b#b@0.1.0",
                     "cwd": "\(directory)/crates/b", "testcases": {}}
        }}
        """
        let inventory = try JSONDecoder().decode(NextestInventory.self, from: Data(listing.utf8))
        #expect(inventory.sourceRemaps.map { "\($0.from) -> \($0.to)" } == ["\(build) -> \(directory)"])

        let lcov = """
        SF:\(build)/crates/a/src/lib.rs
        DA:1,1
        end_of_record
        SF:\(build)/crates/b/src/lib.rs
        DA:1,0
        end_of_record
        SF:\(build)/shared/util.rs
        DA:1,2
        end_of_record
        SF:/elsewhere/shared/util.rs
        DA:1,2
        end_of_record
        """
        let resolver = CargoCoverage.Resolver(
            packages: [
                CargoCoverage.Package(name: "a", directory: "\(directory)/crates/a", testSources: []),
                CargoCoverage.Package(name: "b", directory: "\(directory)/crates/b", testSources: []),
            ],
            workspaceRoot: directory, repositoryRoot: directory, workingDirectory: directory,
            remaps: inventory.sourceRemaps
        )
        let files = CargoCoverage.files(CargoCoverage.LCOVFile.parse(Data(lcov.utf8)), resolver: resolver)

        #expect(files.map { $0["path"] as? String } == ["crates/a/src/lib.rs", "crates/b/src/lib.rs", "shared/util.rs"])
        #expect(files.map { $0["targets"] as? [String] ?? [] } == [["a"], ["b"], []])
        #expect(files.map { $0["covered_lines"] as? Int } == [1, 0, 1])
    }

    @Test(.inTemporaryDirectory) func processesAreMatchedToTheBinariesTheRunReported() throws {
        let directory = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let processes = directory.appendingPathComponent("processes")
        try FileManager.default.createDirectory(at: processes, withIntermediateDirectories: true)
        func record(_ name: String, _ arguments: [String], profiles: Int = 1) throws {
            try Data(arguments.map { $0 + "\0" }.joined().utf8).write(to: processes.appendingPathComponent(name))
            for index in 0 ..< profiles {
                FileManager.default.createFile(
                    atPath: processes.appendingPathComponent("\(name)-\(index)-1_0.profraw").path,
                    contents: Data()
                )
            }
        }
        try record("aaaaaaaa", ["/other/target/debug/deps/api-1111", "--exact", "cart::adds", "--nocapture"], profiles: 2)
        try record("bbbbbbbb", ["/other/target/debug/deps/api-1111", "--list", "--format", "terse"])
        try record("cccccccc", ["/workspace/target/debug/deps/store-2222"])
        try record("dddddddd", ["/tmp/rustdoctest1/rust_out"])

        let found = CargoCoverage.processes(in: directory, binaries: [
            "/workspace/target/debug/deps/api-1111": "store::api",
            "/workspace/target/debug/deps/store-2222": "store",
        ])

        // An archive's binaries run from where it was extracted: the file name, hash included, identifies them.
        #expect(found.map(\.module) == ["store::api", "store"])
        #expect(found.map(\.test) == ["cart::adds", nil])
        #expect(found.map(\.binary) == ["/other/target/debug/deps/api-1111", "/workspace/target/debug/deps/store-2222"])
        #expect(found.map(\.profiles.count) == [2, 1])
    }

    @Test func storedDeflateBlocksSpanLargeInputs() throws {
        let data = Data((0 ..< 150_000).map { UInt8($0 % 251) })
        let deflated = CargoCoverage.deflate(data)
        #expect(!deflated.isEmpty)
        #expect(deflated != data)
    }

    // MARK: - Real Cargo

    static let hasLLVMTools: Bool = {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["rustc", "--print", "sysroot"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let sysroot = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        let rustlib = URL(fileURLWithPath: sysroot).appendingPathComponent("lib/rustlib")
        let hosts = (try? FileManager.default.contentsOfDirectory(atPath: rustlib.path)) ?? []
        return hosts
            .contains { FileManager.default.isExecutableFile(atPath: rustlib.appendingPathComponent("\($0)/bin/llvm-cov").path) }
    }()

    @Test(.inTemporaryDirectory, .enabled(if: hasLLVMTools)) func collectsRealCargoAndNextestCoverage() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        let fixture = TestPaths.fixturesDirectory.appending(component: "CargoCoverage")
        for item in ["Cargo.toml", "src", "tests"] {
            try FileManager.default.copyItem(
                atPath: fixture.appending(component: item).pathString, toPath: root.appendingPathComponent(item).path
            )
        }
        let canonical = CargoCoverage.Resolver.canonical(directory.pathString)
        let runner = CommandRunner()
        let process = CargoProcess(runner: runner)
        var environment = ProcessInfo.processInfo.environment
        environment["TUIST_CARGO_ACTIVE"] = "1"
        for name in ["RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_BUILD_RUSTFLAGS", "LLVM_PROFILE_FILE"] {
            environment[name] = nil
        }
        let executable = try await process.executable(
            invocation: CargoInvocation(["test"]),
            environment: environment,
            directory: directory
        )
        environment["RUSTUP_TOOLCHAIN"] = executable.toolchain ?? environment["RUSTUP_TOOLCHAIN"]
        let reporting = CargoReporting(
            process: process, directory: directory, environment: environment, handle: "test/project",
            serverURL: URL(string: "https://tuist.dev")!
        )
        let packages = [CargoCoverage.Package(
            name: "cov-fixture", directory: directory.pathString, testSources: [root.appendingPathComponent("tests/api.rs").path]
        )]

        // Plain `cargo test`: a binary's tests share its process, so each binary gets target evidence only.
        let session = root.appendingPathComponent("session")
        let prepared = await CargoCoverage.prepare(
            invocation: CargoInvocation(["test"]), environment: environment, directory: directory, root: session,
            cacheDirectory: session, process: process
        )
        let coverage = try #require(prepared.coverage)
        #expect(coverage.attributes)
        var result: CargoTestResult?
        try await CargoTestService(runner: runner).execute(CargoExecutionContext(
            executable: executable.path, directory: directory, arguments: ["test"], environment: prepared.environment,
            reporting: reporting
        )) { result = $0 }
        let report = try #require(result?.report)
        #expect(Set(report.binaries.values) == ["cov-fixture", "cov-fixture::bin/tool", "cov-fixture::api"])
        let collected = try #require(await coverage.collect(
            binaries: report.binaries,
            tests: [("cov-fixture::api", "", "grows"), ("cov-fixture::api", "", "applies"), ("cov-fixture", "tests", "adds")],
            packages: packages, workspaceRoot: directory.pathString, repositoryRoot: canonical,
            workingDirectory: directory.pathString, partial: false
        ))
        let files = Dictionary(uniqueKeysWithValues: collected.files.map { ($0["path"] as! String, $0) })
        let library = try #require(files["src/lib.rs"])
        let counts = Dictionary(
            uniqueKeysWithValues: zip(library["line_numbers"] as! [Int], library["execution_counts"] as! [Int])
        )
        // `classify` ran for a negative number (the library's tests) and zero (the binary's), never a positive one.
        #expect(counts[13] == 1)
        #expect(counts[15] == 1)
        #expect(counts[17] == 0)
        let functions = (library["functions"] as! [[String: Any]]).map { $0["name"] as! String }
        #expect(functions.filter { $0 == "cov_fixture::apply" }.count == 1)
        #expect(files["tests/api.rs"]?["is_test"] as? Bool == true)
        #expect(files["tests/common/mod.rs"]?["is_test"] as? Bool == true)
        #expect(files["src/shapes.rs"]?["targets"] as? [String] == ["cov-fixture"])

        let evidence = try #require(collected.evidence)
        #expect(evidence["status"] as? String == "collected")
        let paths = evidence["paths"] as! [String]
        let scopes = evidence["scopes"] as! [[String: Any]]
        #expect(Set(scopes.map { $0["kind"] as! String }) == ["target"])
        func lines(of module: String, kind: String = "target", name: String = "", in file: String) -> Set<Int>? {
            guard let scope = scopes.first(where: {
                $0["module"] as? String == module && $0["kind"] as? String == kind && $0["name"] as? String == name
            }), let index = paths.firstIndex(of: file),
            let position = (scope["files"] as! [Int]).firstIndex(of: index)
            else { return nil }
            let ranges = (scope["lines"] as! [[Int]])[position]
            return Set(stride(from: 0, to: ranges.count, by: 2).flatMap { ranges[$0] ... ranges[$0 + 1] })
        }
        // Only the integration tests grow a square.
        #expect(lines(of: "cov-fixture::api", in: "src/shapes.rs")?.contains(9) == true)
        #expect(lines(of: "cov-fixture", in: "src/shapes.rs")?.contains(9) == false)
        #expect(lines(of: "cov-fixture::bin/tool", in: "src/shapes.rs") == nil)
        let overlapped = (evidence["overlapped_tests"] as? [[String: Any]] ?? []).map { $0["name"] as! String }
        #expect(Set(overlapped) == ["grows", "applies", "adds"])

        // Nextest: each test runs in its own process, so each test gets evidence of its own.
        guard (try? await process.capture(
            executable.path,
            arguments: ["nextest", "--version"],
            environment: environment,
            directory: directory
        )) != nil
        else { return }
        let nextestSession = root.appendingPathComponent("nextest-session")
        let nextestPrepared = await CargoCoverage.prepare(
            invocation: CargoInvocation(["nextest", "run"]), environment: environment, directory: directory,
            root: nextestSession, cacheDirectory: nextestSession, process: process
        )
        let nextestCoverage = try #require(nextestPrepared.coverage)
        let context = CargoExecutionContext(
            executable: executable.path, directory: directory, arguments: ["nextest", "run"],
            environment: nextestPrepared.environment, reporting: reporting
        )
        let run = try await CargoNextestService(runner: runner).prepare(context, root: nextestSession)
        try await process.execute(
            executable.path,
            arguments: run.arguments,
            environment: context.environment,
            directory: directory
        )
        let inventory = try #require(run.inventory)
        let nextestCollected = try #require(await nextestCoverage.collect(
            binaries: inventory.binaries, tests: [], packages: packages,
            workspaceRoot: directory.pathString, repositoryRoot: canonical, workingDirectory: directory.pathString,
            partial: false
        ))
        let nextestEvidence = try #require(nextestCollected.evidence)
        let nextestPaths = nextestEvidence["paths"] as! [String]
        let nextestScopes = nextestEvidence["scopes"] as! [[String: Any]]
        func testLines(_ name: String, suite: String = "", module: String, in file: String) -> Set<Int>? {
            guard let scope = nextestScopes.first(where: {
                $0["kind"] as? String == "test" && $0["module"] as? String == module && $0["suite"] as? String == suite
                    && $0["name"] as? String == name
            }), let index = nextestPaths.firstIndex(of: file),
            let position = (scope["files"] as! [Int]).firstIndex(of: index)
            else { return nil }
            let ranges = (scope["lines"] as! [[Int]])[position]
            return Set(stride(from: 0, to: ranges.count, by: 2).flatMap { ranges[$0] ... ranges[$0 + 1] })
        }
        #expect(testLines("grows", module: "cov-fixture::api", in: "src/shapes.rs")?.contains(9) == true)
        #expect(testLines("applies", module: "cov-fixture::api", in: "src/shapes.rs") == nil)
        #expect(testLines("applies", module: "cov-fixture::api", in: "src/lib.rs")?.contains(22) == true)
        #expect(testLines("classifies_negative", suite: "tests", module: "cov-fixture", in: "src/lib.rs")?.contains(13) == true)
        #expect(testLines("classifies_negative", suite: "tests", module: "cov-fixture", in: "src/lib.rs")?.contains(15) == false)
        #expect(nextestEvidence["overlapped_tests"] == nil)
        #expect(Set(nextestScopes.filter { $0["kind"] as? String == "target" }.map { $0["module"] as! String })
            == ["cov-fixture", "cov-fixture::bin/tool", "cov-fixture::api"])
    }
}
