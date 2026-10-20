import ArgumentParser
import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistProcess
@testable import TuistCargoCommand

struct CargoTests {
    @Test func preservesCargoArguments() throws {
        let args = ["+nightly", "--config", "build.jobs=2", "test", "--workspace", "--", "--exact", "tests::case"]
        let command = try CargoCommand.parse(args)
        #expect(command.arguments == args)
        let invocation = CargoInvocation(args)
        #expect(invocation.command == "test")
        #expect(invocation.commandIndex == 3)
    }

    @Test func separatesNextestExecutionFromBuildReports() {
        #expect(CargoInvocation(["nextest", "run"]).observesBuild)
        #expect(!CargoInvocation(["nextest", "run"]).reportsBuild)
        #expect(!CargoInvocation(["nextest", "list"]).reportsBuild)
        #expect(CargoInvocation(["build"]).reportsBuild)
        #expect(CargoInvocation(["test-build"]).reportsBuild)
    }

    @Test func preservesPlusPrefixedHarnessArguments() {
        let invocation = CargoInvocation(["+nightly", "test", "--", "+case"])
        #expect(invocation.toolchain == "nightly")
        #expect(invocation.cargoArguments == ["test", "--", "+case"])
        let config = CargoInvocation(["--config", "+config.toml", "build"])
        #expect(config.toolchain == nil)
        #expect(config.cargoArguments == ["--config", "+config.toml", "build"])
    }

    @Test(.inTemporaryDirectory) func preservesExitStatusAndSelectedToolchain() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let log = directory.appending(component: "arguments")
        let executable = directory.appending(component: "cargo")
        try "#!/bin/sh\nprintf '%s\\n' \"$RUSTUP_TOOLCHAIN\" \"$@\" > \(CargoInvocation.shellQuote(log.pathString))\nexit 23\n"
            .write(
                toFile: executable.pathString,
                atomically: true,
                encoding: .utf8
            )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.pathString)
        do {
            try await CargoCommandService().run(
                arguments: ["+nightly", "test", "--", "+case"],
                environment: [
                    "TUIST_CARGO_EXECUTABLE": executable.pathString,
                    "TUIST_CARGO_ACTIVE": "1",
                ],
                directory: directory
            )
            Issue.record("Cargo's failing exit status was lost")
        } catch let CommandError.terminated(code, _, _) { #expect(code == 23) }
        #expect(try String(contentsOfFile: log.pathString, encoding: .utf8) == "nightly\ntest\n--\n+case\n")
    }

    @Test(.inTemporaryDirectory) func observesCompilerFailuresWithoutReplacingTheCompilerWrapper() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let compiler = directory.appending(component: "compiler")
        let wrapper = directory.appending(component: "wrapper")
        let log = directory.appending(component: "wrapper-log")
        try "#!/bin/sh\necho '{\"level\":\"error\",\"message\":\"type mismatch\",\"spans\":[]}' >&2\nexit 7\n".write(
            toFile: compiler.pathString,
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/sh\necho invoked > \(CargoInvocation.shellQuote(log.pathString))\nexec \"$@\"\n".write(
            toFile: wrapper.pathString,
            atomically: true,
            encoding: .utf8
        )
        for path in [compiler, wrapper] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: path.pathString
            )
        }
        do {
            try await CargoCommandService().run(
                arguments: ["__compiler", compiler.pathString, "--crate-name", "widgets", "src/lib.rs"],
                environment: [
                    "TUIST_CARGO_INNER_WRAPPER": wrapper.pathString, "TUIST_CARGO_SESSION": directory.pathString,
                    "TUIST_CARGO_STARTED": String(Date().timeIntervalSince1970),
                ],
                directory: directory
            )
            Issue.record("The compiler's failing status was lost")
        } catch let CommandError.terminated(code, _, _) { #expect(code == 7) }
        #expect(FileManager.default.fileExists(atPath: log.pathString))
        let records = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: directory.pathString),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        let record = try #require(records.first)
        let compilation = try JSONDecoder().decode(CargoCompilation.self, from: Data(contentsOf: record))
        #expect(compilation.name == "widgets")
        #expect(compilation.status == "failure")
        #expect(compilation.diagnostics.first?.message == "type mismatch")
    }
}

struct CargoReportingTests {
    @Test func distinguishesMeasuredNextestLabelsFromReservedCargoSchemes() {
        #expect(CargoNextestRun.scheme(label: nil) == "nextest")
        #expect(CargoNextestRun.scheme(label: "ci") == "ci")
        #expect(CargoNextestRun.scheme(label: "cargo test") == "cargo nextest run · cargo test")
        #expect(CargoNextestRun.scheme(label: "cargo test · ci") == "cargo nextest run · cargo test · ci")
        #expect(CargoNextestRun.scheme(label: "cargo nextest run · cargo test") == "cargo nextest run · cargo test")
    }

    @Test(.inTemporaryDirectory) func respectsConfiguredCompilerWrappers() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".cargo"), withIntermediateDirectories: true)
        try "[build]\nrustc-wrapper = './scripts/cache'\n".write(
            to: root.appendingPathComponent(".cargo/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        #expect(try CargoConfiguration.compilerWrapper(
            directory: root,
            arguments: ["build"],
            environment: ["CARGO_HOME": root.appendingPathComponent("home").path]
        ) == root.appendingPathComponent("scripts/cache").path)
        #expect(try CargoConfiguration
            .compilerWrapper(directory: root, arguments: ["build"], environment: ["RUSTC_WRAPPER": ""]) == nil)
        #expect(try CargoConfiguration.compilerWrapper(
            directory: root,
            arguments: ["build"],
            environment: ["CARGO_BUILD_RUSTC_WRAPPER": ""]
        ) == nil)
        #expect(try CargoConfiguration.compilerWrapper(
            directory: root,
            arguments: ["build", "--config", "build.rustc-wrapper=''"],
            environment: [:]
        ) == nil)
        #expect(try CargoConfiguration.compilerWrapper(
            directory: root,
            arguments: ["build"],
            environment: ["RUSTC_WRAPPER": "./scripts/cache"]
        ) == root.appendingPathComponent("scripts/cache").path)
    }

    @Test(.inTemporaryDirectory) func honorsUserNextestJUnitConfiguration() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".config"), withIntermediateDirectories: true)
        try "[profile.ci.junit]\npath = 'reports/results.xml'\n".write(
            to: root.appendingPathComponent(".config/nextest.toml"),
            atomically: true,
            encoding: .utf8
        )
        let target = root.appendingPathComponent("target")
        let fallback = root.appendingPathComponent("fallback.xml")
        #expect(try NextestConfiguration.junitPath(
            workspace: root,
            target: target,
            arguments: ["nextest", "run", "--profile", "ci"],
            environment: [:],
            fallback: fallback
        ) == target.appendingPathComponent("nextest/ci/reports/results.xml"))
    }

    @Test func enumerationRemovesRunnerOnlyOptions() {
        #expect(CargoCommandService.listArguments([
            "nextest",
            "list",
            "--workspace",
            "--retries=2",
            "--test-threads",
            "4",
            "-E",
            "none()",
            "--",
            "ignored",
        ]) == ["nextest", "list", "--workspace"])
    }

    @Test(.inTemporaryDirectory) func invalidReportingConfigurationDoesNotReplaceCargoFailure() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let executable = directory.appending(component: "cargo")
        try "#!/bin/sh\nexit 31\n".write(toFile: executable.pathString, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.pathString)
        do {
            try await CargoCommandService().run(arguments: ["build"], environment: [
                "TUIST_CARGO_EXECUTABLE": executable.pathString, "TUIST_PROJECT": "example/project", "TUIST_URL": "relative-url",
            ], directory: directory)
            Issue.record("Cargo's failing status was lost")
        } catch let CommandError.terminated(code, _, _) { #expect(code == 31) }
    }

    @Test(.inTemporaryDirectory) func pinsTheDefaultRustupToolchainBeforeCargoChangesDirectories() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let process = CargoProcess(runner: RustupProbeRunner())
        let resolved = try await process.executable(
            invocation: CargoInvocation(["build"]),
            environment: [:],
            directory: directory
        )
        #expect(resolved.path == "/toolchains/stable/bin/cargo")
        #expect(resolved.toolchain == "stable-aarch64-apple-darwin")
        let explicit = try await process.executable(
            invocation: CargoInvocation(["build"]),
            environment: ["RUSTUP_TOOLCHAIN": "nightly"],
            directory: directory
        )
        #expect(explicit.toolchain == nil)
        let custom = try await CargoProcess(runner: RustupProbeRunner(activeToolchain: "/toolchains/my rust")).executable(
            invocation: CargoInvocation(["build"]),
            environment: [:],
            directory: directory
        )
        #expect(custom.toolchain == "/toolchains/my rust")
    }

    @Test func forwardsNightlyDirectoryChangesWithoutReplacingTheirCompilerConfiguration() {
        let invocation = CargoInvocation(["+nightly", "-C", "member", "build"])
        #expect(invocation.command == "build")
        #expect(invocation.changesDirectory)
        #expect(!invocation.observesBuild)
    }

    @Test func cargoOwnsItsGlobalFlagsAndHarnessArguments() {
        #expect(CargoCommand.delegatedArguments(in: ["tuist", "cargo", "test", "--quiet", "--verbose", "--", "--json"]) == [
            "test",
            "--quiet",
            "--verbose",
            "--",
            "--json",
        ])
        #expect(CargoCommand.delegatedArguments(in: ["tuist", "--verbose", "cargo", "build", "--quiet"]) == ["build", "--quiet"])
        #expect(CargoCommand.delegatedArguments(in: ["tuist", "generate", "cargo", "--quiet"]) == nil)
    }

    @Test func passesThroughOtherCommands() {
        #expect(!CargoInvocation(["metadata", "--format-version", "1"]).observesBuild)
        #expect(!CargoInvocation(["build", "--help"]).observesBuild)
        #expect(CargoInvocation(["--color=never", "check"]).observesBuild)
        #expect(CargoInvocation(["nextest", "run"]).isNextestRun)
        #expect(!CargoInvocation(["nextest", "list"]).isNextestRun)
    }

    @Test func filtersAreExactAndEscaped() {
        #expect(CargoInvocation.filterset(modules: []) == "none()")
        #expect(CargoInvocation.filterset(modules: ["parser::tests"]) == "binary_id(=parser::tests)")
        #expect(CargoInvocation.shellQuote("a'b") == "'a'\\''b'")
        #expect(CargoInvocation.quote("a\"b") == "\"a\\\"b\"")
        #expect(CargoInvocation.filterLiteral("a(b,c)") == "a\\(b\\,c\\)")
    }

    @Test func shardFiltersIntersectUserFiltersInsteadOfBroadeningTheShard() {
        let args = CargoInvocation.restrictingToModules(
            ["parser"],
            arguments: ["nextest", "run", "-E", "all()", "--filterset=none()", "--", "--ignored"]
        )
        #expect(args == ["nextest", "run", "-E", "(binary_id(=parser)) and ((all()) or (none()))", "--", "--ignored"])
        #expect(CargoInvocation.restrictingToModules([], arguments: ["nextest", "run", "-Eall()"]) == [
            "nextest",
            "run",
            "-E",
            "(none()) and ((all()))",
        ])
    }

    @Test func parsesShardPlanningOptionsAndRejectsInvalidLimits() throws {
        let parsed = try CargoShardService.planningArguments([
            "--color=never",
            "test-build",
            "--workspace",
            "--shard-total=4",
            "--shard-max-duration",
            "60",
        ])
        #expect(parsed.arguments == ["--color=never", "nextest", "archive", "--workspace"])
        #expect(parsed.options == ["--shard-total": 4, "--shard-max-duration": 60])
        #expect(throws: (any Error).self) { try CargoShardService.planningArguments(["test-build", "--shard-total", "0"]) }
        #expect(throws: (any Error).self) { try CargoShardService.planningArguments([
            "test-build",
            "--shard-total=1",
            "--shard-total=2",
        ]) }
    }

    @Test(.inTemporaryDirectory) func doesNotMistakeAnUnchangedJUnitReportForNewExecution() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "report.xml").pathString)
        #expect(CargoNextestRun.fingerprint(url) == nil)
        try "<testsuites uuid='old' />".write(to: url, atomically: true, encoding: .utf8)
        let old = CargoNextestRun.fingerprint(url)
        #expect(old == CargoNextestRun.fingerprint(url))
        try "<testsuites uuid='new' />".write(to: url, atomically: true, encoding: .utf8)
        #expect(old != CargoNextestRun.fingerprint(url))
    }

    @Test func insertsBeforeHarnessSeparator() {
        #expect(CargoInvocation.inserting(["-E", "none()"], into: ["nextest", "run", "--", "--ignored"]) == [
            "nextest",
            "run",
            "-E",
            "none()",
            "--",
            "--ignored",
        ])
    }
}

@Suite
struct CargoNextestReportTests {
    @Test func separatesRustNamespaceFromName() {
        let nested = NextestReport.identity("tests::parser::unicode")
        #expect(nested.suite == "tests::parser")
        #expect(nested.name == "unicode")
        #expect(NextestReport.identity("top_level").suite.isEmpty)
    }

    @Test(.inTemporaryDirectory) func parsesFailuresAndRetries() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "junit.xml").pathString)
        try """
        <testsuites time="0.03"><testsuite name="parser::integration">
          <testcase name="tests::flaky" time="0.012"><flakyFailure time="0.02" message="first attempt failed" /></testcase>
          <testcase name="tests::failed" time="0.005"><failure message="assertion">expected a</failure></testcase>
          <testcase name="ignored" time="0"><skipped /></testcase>
        </testsuite></testsuites>
        """.write(to: url, atomically: true, encoding: .utf8)
        let report = try NextestReport.read(url)
        #expect(report.tests.count == 3)
        #expect(report.duration == 30)
        #expect(report.tests[0].status == "success")
        #expect(report.tests[0].retries.count == 1)
        #expect(report.tests[0].retries[0].duration == 20)
        #expect(report.tests[1].status == "failure")
        #expect(report.tests[2].status == "skipped")
        let cases = try #require(report.modules[0]["test_cases"] as? [[String: Any]])
        #expect(cases[0]["test_suite_name"] as? String == "tests")
        #expect((cases[0]["repetitions"] as? [[String: Any]])?.count == 2)
    }

    @Test(.inTemporaryDirectory) func measuresParallelBinaryWallTimeAndRetryGaps() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "parallel.xml").pathString)
        try """
        <testsuites time="30">
          <testsuite name="store::lib">
            <testcase name="tests::one" time="10" timestamp="2026-10-07T12:00:00.000Z" />
            <testcase name="tests::two" time="10" timestamp="2026-10-07T12:00:00Z" />
            <testcase name="tests::ignored" time="0"><skipped /></testcase>
          </testsuite>
          <testsuite name="store::test/api">
            <testcase name="api::flaky" time="1" timestamp="2026-10-07T12:00:10.000Z">
              <flakyFailure time="1" timestamp="2026-10-07T12:00:00.000Z" />
            </testcase>
          </testsuite>
          <testsuite name="store::test/serial">
            <testcase name="serial::one" time="2" timestamp="2026-10-07T12:00:00Z" />
            <testcase name="serial::two" time="2" timestamp="2026-10-07T12:00:03Z" />
          </testsuite>
        </testsuites>
        """.write(to: url, atomically: true, encoding: .utf8)
        let report = try NextestReport.read(url)
        let modules = report.modules
        #expect(report.duration == 30000)
        #expect(modules.map { $0["duration"] as? Int } == [10000, 11000, 5000])
        #expect(modules.allSatisfy { $0["execution_mode"] as? String == "parallel" })
        let suites = try #require(modules[0]["test_suites"] as? [[String: Any]])
        #expect(suites[0]["duration"] as? Int == 10000)
        let cases = try #require(modules[1]["test_cases"] as? [[String: Any]])
        #expect(cases[0]["duration"] as? Int == 2000)
    }

    @Test(.inTemporaryDirectory) func doesNotCalibrateConcurrencyWithoutCompleteTimestamps() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "unmeasured.xml").pathString)
        try """
        <testsuites time="10"><testsuite name="store::lib">
          <testcase name="one" time="3" timestamp="2026-10-07T12:00:00Z" />
          <testcase name="two" time="3" />
        </testsuite></testsuites>
        """.write(to: url, atomically: true, encoding: .utf8)
        let report = try NextestReport.read(url)
        #expect(report.modules[0]["duration"] as? Int == 6000)
        #expect(report.modules[0]["execution_mode"] == nil)
    }

    @Test(.inTemporaryDirectory) func rejectsEntitiesAndMalformedReports() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "report.xml").pathString)
        try "<!DOCTYPE x [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><x>&secret;</x>".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        #expect(throws: (any Error).self) { try NextestReport.read(url) }
        try "<testsuites><testsuite>".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try NextestReport.read(url) }
    }

    @Test func parsesInventoryWithoutArtifactIdentities() throws {
        let data = Data("""
        {"rust-suites":{"hash-does-not-matter":{"binary-id":"parser::integration","testcases":{
        "tests::enabled":{"ignored":false,"filter-match":{"status":"matches"}},
        "ignored":{"ignored":true,"filter-match":{"status":"mismatch"}}
        }}}}
        """.utf8)
        let inventory = try JSONDecoder().decode(NextestInventory.self, from: data)
        #expect(inventory.modules == ["parser::integration"])
        #expect(inventory.enumeration.count == 2)
    }
}
