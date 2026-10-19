import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistProcess
import TuistTestSupport
@testable import TuistCargoCommand

struct CargoTestReportTests {
    private let targets = [
        CargoTestTarget(
            module: "store",
            name: "store",
            source: "/workspace/src/lib.rs",
            isLibrary: true,
            packageDirectory: "/workspace"
        ),
        CargoTestTarget(
            module: "store::api",
            name: "api",
            source: "/workspace/tests/api.rs",
            isLibrary: false,
            packageDirectory: "/workspace"
        ),
    ]

    private func summary(_ rows: String, passed: Int, failed: Int = 0, ignored: Int = 0, filtered: Int = 0) -> String {
        """
        running \(passed + failed + ignored) tests
        \(rows)

        test result: \(failed == 0 ? "ok" :
            "FAILED"). \(passed) passed; \(failed) failed; \(ignored) ignored; 0 measured; \(
            filtered
        ) filtered out; finished in 0.25s

        """
    }

    private func read(_ output: String, _ errors: String) -> CargoTestReport? {
        CargoTestReport.read(stdout: Data(output.utf8), stderr: Data(errors.utf8), targets: targets, directory: "/workspace")
    }

    @Test func reportsCompletedTestsWithoutInventingFilteredTestsOrTimings() throws {
        let report = try #require(read(summary("""
        test tests::passes ... ok
        test tests::fails ... FAILED
        test tests::ignored ... ignored, requires a database
        """, passed: 1, failed: 1, ignored: 1, filtered: 4), """
             Running unittests src/lib.rs (target/debug/deps/store-0123456789abcdef)
        """))
        #expect(report.duration == 250)
        #expect(report.modules[0]["name"] as? String == "store")
        #expect(report.modules[0]["status"] as? String == "failure")
        #expect(report.modules[0]["execution_mode"] == nil)
        let cases = try #require(report.modules[0]["test_cases"] as? [[String: Any]])
        #expect(cases.count == 3)
        #expect(cases.map { $0["status"] as? String } == ["success", "failure", "skipped"])
        #expect(cases.map { $0["test_suite_name"] as? String } == ["tests", "tests", "tests"])
        #expect(cases.allSatisfy { $0["duration"] as? Int == 0 })
    }

    @Test func attributesIntegrationTestsUsingMetadataNotArtifactHashes() throws {
        let output = summary("test authentication::passes ... ok", passed: 1)
        for hash in ["0123456789abcdef", "fedcba9876543210"] {
            let report = try #require(read(output, "Running tests/api.rs (target/debug/deps/api-\(hash))"))
            #expect(report.modules[0]["name"] as? String == "store::api")
        }
    }

    @Test func collectsMergedEdition2024DoctestsIncludingCompileFailAndShouldPanic() throws {
        let output = summary("test tests::unit ... ok", passed: 1)
            + summary("""
            test src/lib.rs - store (line 2) ... ok
            test src/lib.rs - store (line 6) - should panic ... ok
            test src/lib.rs - store (line 10) ... ignored
            """, passed: 2, ignored: 1)
            + summary("test src/lib.rs - store (line 14) - compile fail ... ok", passed: 1)
            + "all doctests ran in 1.00s; merged doctests compilation took 0.50s\n"
        let report = try #require(read(output, """
             Running unittests src/lib.rs (target/debug/deps/store-0123456789abcdef)
           Doc-tests store
        """))
        #expect(report.modules.map { $0["name"] as? String } == ["store", "store::doctest/store"])
        let cases = try #require(report.modules[1]["test_cases"] as? [[String: Any]])
        #expect(cases.count == 4)
        #expect(cases[1]["name"] as? String == "src/lib.rs - store (line 6)")
        #expect(cases[3]["name"] as? String == "src/lib.rs - store (line 14)")
        #expect(cases.allSatisfy { $0["test_suite_name"] as? String == "doctests" })
        #expect(report.modules[1]["duration"] as? Int == 500)
    }

    @Test func normalizesCompileOnlyDoctestNames() throws {
        let report = try #require(read(
            summary("test src/lib.rs - store (line 2) - compile ... ok", passed: 1),
            "Doc-tests store"
        ))
        let cases = try #require(report.modules[0]["test_cases"] as? [[String: Any]])
        #expect(cases[0]["name"] as? String == "src/lib.rs - store (line 2)")
    }

    @Test func resolvesPackageRelativeHeadingsWithoutPreferringTheWorkingDirectory() throws {
        let packages: [[String: Any]] = ["root", "member"].map { name in
            let root = name == "root" ? "/private/tmp/workspace" : "/private/tmp/workspace/crates/member"
            return ["name": name, "manifest_path": root + "/Cargo.toml", "targets": [
                ["name": "api", "src_path": root + "/tests/api.rs", "kind": ["test"]],
            ]]
        }
        let metadata: [String: Any] = ["packages": packages]
        let output = Data(summary("test member_test ... ok", passed: 1).utf8)
        let errors = Data("Running tests/api.rs (target/debug/deps/api-0123456789abcdef)".utf8)
        let targets = CargoTestTarget.read(metadata, arguments: ["test", "-p", "member"])
        #expect(targets.map(\.module) == ["member::api"])
        let report = try #require(CargoTestReport.read(
            stdout: output,
            stderr: errors,
            targets: targets,
            directory: "/tmp/workspace"
        ))
        #expect(report.modules[0]["name"] as? String == "member::api")
        #expect(CargoTestReport.read(
            stdout: output,
            stderr: errors,
            targets: CargoTestTarget.read(metadata),
            directory: "/tmp/workspace"
        ) == nil)
    }

    @Test func supportsSeparateDoctestInvocationsAndAnsiColor() throws {
        let output = summary("test src/lib.rs - store (line 2) ... \u{1B}[32mok\u{1B}[0m", passed: 1)
        let report = try #require(read(output, "\u{1B}[32m   Doc-tests\u{1B}[0m store"))
        #expect(report.modules[0]["name"] as? String == "store::doctest/store")
    }

    @Test func rejectsIncompleteMismatchedAndDuplicateResults() {
        let heading = "Running unittests src/lib.rs (target/debug/deps/store-0123456789abcdef)"
        #expect(read("running 2 tests\ntest one ... ok\n", heading) == nil)
        #expect(read(summary("test one ... ok", passed: 2), heading) == nil)
        #expect(read(summary("test one ... FAILED", passed: 1), heading) == nil)
        #expect(read(summary("test one ... ok\ntest one ... ok", passed: 2), heading) == nil)
        #expect(read(summary("test one ... ok", passed: 1), "") == nil)
        #expect(read(summary("test one ... ok", passed: 1), heading + "\nDoc-tests store") == nil)
    }

    @Test func doesNotAttributeUnknownOrAmbiguousTargets() {
        let output = summary("test one ... ok", passed: 1)
        #expect(read(output, "Running tests/other.rs (target/debug/deps/other-0123456789abcdef)") == nil)
        let ambiguous = targets + [CargoTestTarget(
            module: "other",
            name: "store",
            source: "/other/src/lib.rs",
            isLibrary: true,
            packageDirectory: "/other"
        )]
        #expect(CargoTestReport.read(
            stdout: Data(summary("test src/lib.rs - store (line 2) ... ok", passed: 1).utf8),
            stderr: Data("Doc-tests store".utf8), targets: ambiguous, directory: "/workspace"
        ) == nil)
    }

    @Test func rejectsOversizedSuitesAndAmbiguousMergedDoctestBoundaries() {
        #expect(read("running 100001 tests\n", "Doc-tests store") == nil)
        let output = (0 ..< 6).map { index in
            summary("test src/lib.rs - item (line \(index + 1)) ... ok", passed: 1)
                + ([2, 5].contains(index) ? "all doctests ran in 1.00s; merged doctests compilation took 0.50s\n" : "")
        }.joined()
        let libraries = ["one", "two", "three"].map {
            CargoTestTarget(
                module: $0,
                name: $0,
                source: "/workspace/\($0)/src/lib.rs",
                isLibrary: true,
                packageDirectory: "/workspace/\($0)"
            )
        }
        #expect(CargoTestReport.read(
            stdout: Data(output.utf8), stderr: Data("Doc-tests one\nDoc-tests two\nDoc-tests three\n".utf8),
            targets: libraries, directory: "/workspace"
        ) == nil)
    }

    @Test func leavesNonstandardHarnessesAndNonexecutingCommandsAlone() {
        for args in [
            ["test", "--no-run"], ["test", "--", "--list"], ["test", "--quiet"],
            ["test", "--", "--nocapture"], ["test", "--", "--no-capture"],
            ["test", "--", "--format", "terse"], ["test", "--", "--format=json"],
            ["test", "--message-format=json"], ["test", "--help"], ["nextest", "run"],
            ["test", "--verbose"], ["test", "-v"], ["test", "-vv"],
        ] {
            #expect(!CargoTestService.observes(CargoInvocation(args), environment: [:]))
        }
        #expect(!CargoTestService.observes(CargoInvocation(["test"]), environment: ["RUST_TEST_NOCAPTURE": "1"]))
        #expect(!CargoTestService.observes(CargoInvocation(["test"]), environment: ["CARGO_TERM_VERBOSE": "true"]))
        #expect(!CargoTestService.observes(CargoInvocation(["test"]), environment: ["CARGO_TERM_QUIET": "true"]))
        #expect(CargoTestService.observes(CargoInvocation(["test", "--doc"]), environment: [:]))
        #expect(CargoTestService.observes(
            CargoInvocation(["t", "--workspace", "--", "--exact", "tests::passes"]),
            environment: [:]
        ))
    }

    private func copyFixture(to directory: URL) throws {
        let fixture = TestPaths.fixturesDirectory.appending(component: "CargoTestReporting")
        for item in ["Cargo.toml", "src", "tests"] {
            try FileManager.default.copyItem(
                atPath: fixture.appending(component: item).pathString,
                toPath: directory.appendingPathComponent(item).path
            )
        }
    }

    @Test(.inTemporaryDirectory) func observesRealStableCargoTestsAndDoctests() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        try copyFixture(to: URL(fileURLWithPath: directory.pathString))
        let runner = CommandRunner()
        let process = CargoProcess(runner: runner)
        var environment = ProcessInfo.processInfo.environment
        environment["TUIST_CARGO_ACTIVE"] = "1"
        environment["TUIST_FIXTURE_FAIL"] = nil
        let executable = try await process.executable(
            invocation: CargoInvocation(["test"]),
            environment: environment,
            directory: directory
        )
        environment["RUSTUP_TOOLCHAIN"] = executable.toolchain ?? environment["RUSTUP_TOOLCHAIN"]
        let reporting = CargoReporting(
            process: process,
            directory: directory,
            environment: environment,
            handle: "test/project",
            serverURL: URL(string: "https://tuist.dev")!
        )
        for (args, fails, count) in [
            (["test"], false, 10), (["test", "--doc"], false, 5),
            (["test"], true, 3), (["test", "--no-fail-fast"], true, 10),
        ] {
            environment["TUIST_FIXTURE_FAIL"] = fails ? "1" : nil
            let context = CargoExecutionContext(
                executable: executable.path,
                directory: directory,
                arguments: args,
                environment: environment,
                reporting: reporting
            )
            var report: CargoTestReport?
            do {
                try await CargoTestService(runner: runner).execute(context) { report = $0 }
                #expect(!fails)
            } catch let CommandError.terminated(code, stderr, _) {
                #expect(fails)
                #expect(code == 101)
                #expect(stderr.isEmpty)
            }
            let modules = try #require(report?.modules)
            let cases = modules.flatMap { $0["test_cases"] as? [[String: Any]] ?? [] }
            #expect(cases.count == count)
            #expect(cases.contains { $0["status"] as? String == "failure" } == fails)
            let hasDoctests = modules
                .contains { $0["name"] as? String == "tuist-cargo-reporting-fixture::doctest/tuist_cargo_reporting_fixture" }
            #expect(hasDoctests == (!fails || args.contains("--no-fail-fast")))
        }
    }
}
