import FileSystem
import FileSystemTesting
import Foundation
import Path
import TestCoverageAttribution
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistEnvironment
import TuistLoggerTesting
import TuistNooraTesting
import TuistSupport
import TuistTesting
import TuistXCResultService
import XCResultParser

@testable import TuistKit
@testable import TuistTestCommand

@Suite(.coverageAttribution)
struct TestAcceptanceTestiOSAppWithFrameworks {
    @Test(
        .disabled(),
        .withFixture("generated_ios_app_with_frameworks"),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func ios_app_with_frameworks() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
    }
}

@Suite(.coverageAttribution)
struct TestAcceptanceTestAppWithFrameworkAndTests {
    @Test(
        .disabled(),
        .withFixture("generated_app_with_framework_and_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func app_with_framework_and_tests() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString, "App"]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "--test-targets",
                "FrameworkTests/FrameworkTests",
            ]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "App",
                "--",
                "-testLanguage",
                "en",
            ]
        )
    }
}

@Suite(.coverageAttribution)
struct TestAcceptanceTestFrameworkWithSPMBundle {
    @Test(.disabled(), .withFixture("generated_framework_with_spm_bundle"), .inTemporaryDirectory)
    func with_framework_with_spm_bundle() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

@Suite(.coverageAttribution)
struct TestAcceptanceTestAppWithTestPlan {
    @Test(.disabled(), .withFixture("generated_app_with_test_plan"), .inTemporaryDirectory)
    func with_app_with_test_plan() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "App",
                "--test-plan",
                "All",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
    }
}

@Suite(.coverageAttribution)
struct TestAcceptanceTestAppWorkspaceWithTestPlan {
    @Test(.disabled(), .withFixture("generated_app_workspace_with_test_plan"), .inTemporaryDirectory)
    func with_app_workspace_with_test_plan() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            [
                "App",
                "--test-plan",
                "AppTestPlan",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
    }
}

@Suite(.coverageAttribution)
struct TestAcceptanceTestInvalidArguments {
    @Test(.withFixture("generated_app_with_framework_and_tests"), .inTemporaryDirectory)
    func with_invalid_arguments() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-scheme")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-scheme",
                    "App",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-project")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-project",
                    "App",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-workspace")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-workspace",
                    "App",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-testPlan")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-testPlan",
                    "TestPlan",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-test-configuration")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-skip-test-configuration",
                    "TestPlan",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-only-test-configuration")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-only-test-configuration",
                    "TestPlan",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-only-testing")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-only-testing",
                    "AppTests",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-testing")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-skip-testing",
                    "AppTests",
                ]
            )
        }
        await #expect(throws: Error.self) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-parallelizeTargets",
                    "YES",
                    "-enableAddressSanitizer",
                ]
            )
        }
        await #expect(throws: Error.self) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--configuration",
                    "Debug",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-configuration",
                    "Debug",
                ]
            )
        }
        await #expect(throws: TuistTestFlagError.passthroughActionVerbConflict("build-for-testing")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--build-only",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "build-for-testing",
                    "-configuration",
                    "Debug",
                ]
            )
        }
        await #expect(throws: TuistTestFlagError.passthroughActionVerbConflict("test")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "test",
                ]
            )
        }
    }
}

@Suite(.coverageAttribution)
struct TestAcceptanceTestMultiplatformApp {
    @Test(.withFixture("generated_multiplatform_app"), .inTemporaryDirectory)
    func with_multiplatform_app() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

/// Shards `MacFrameworkTests` from local test products (skipping the S3 upload), and doubles as the
/// regression guard for suite-granularity Swift Testing selection.
///
/// `MacFrameworkTests` mixes one XCTest class with two Swift Testing suites. The shard runs with
/// `--shard-granularity suite`, and the result bundle is parsed to assert the Swift Testing suites
/// actually executed. Earlier the per-suite selection was written into the bundle's `.xctestrun` as
/// `OnlyTestIdentifiers`, which can only ever *exclude* Swift Testing — so the suite ran zero tests
/// yet reported success. With `-only-testing` selection they run.
@Suite(.coverageAttribution)
struct TestAcceptanceTestShardWithLocalTestProducts {
    @Test(
        .withFixtureConnectedToCanary("generated_ios_app_with_tests", accountHandle: "tuist"),
        .inTemporaryDirectory
    ) func shard_with_local_test_products() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "MacFrameworkTests.xctestproducts")
        let shardReference = "acceptance-test-\(Int.random(in: 100_000 ... 999_999))"

        // Set CI env vars so ShardService can derive the shard reference
        Environment.mocked?.variables["GITHUB_ACTIONS"] = "true"
        Environment.mocked?.variables["GITHUB_RUN_ID"] = shardReference
        Environment.mocked?.variables["GITHUB_RUN_ATTEMPT"] = "1"
        let githubOutputPath = temporaryDirectory.appending(component: "github_output")
        try await FileSystem().writeText("", at: githubOutputPath)
        Environment.mocked?.variables["GITHUB_OUTPUT"] = githubOutputPath.pathString

        // Build phase: build tests and create a suite-granularity shard plan, skip S3 upload
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--build-only",
                "--shard-total", "1",
                "--shard-granularity", "suite",
                "--shard-skip-upload",
                "--path", fixtureDirectory.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )

        // Test phase: run the shard using local test products, capturing a result bundle
        let resultBundlePath = temporaryDirectory.appending(component: "shard.xcresult")
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--without-building",
                "--shard-index", "0",
                "--path", fixtureDirectory.pathString,
                "--result-bundle-path", resultBundlePath.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )

        let summary = try await XCResultService().parse(path: resultBundlePath, rootDirectory: nil)
        let executedTestNames = Set(summary?.testCases.map(\.name) ?? [])
        #expect(
            executedTestNames.contains { $0.contains("greeting_isStable") },
            "Swift Testing suite MacFrameworkGreetingTests did not run"
        )
        #expect(
            executedTestNames.contains { $0.contains("greeting_isNotEmpty") },
            "Swift Testing suite MacFrameworkValueTests did not run"
        )
    }
}

/// A suite-granularity plan splits `MacFrameworkTests` across both shards. When the shard holding a
/// failing suite fails, the other shard passes its part of the target, and that part alone must not
/// let the next run skip the target. Once every shard holding the target passed, the next run skips it.
@Suite(.coverageAttribution)
struct TestAcceptanceTestShardSplitTargetSelectiveTesting {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH", "DEVELOPER_DIR", "TUIST_URL"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_tests")
    ) func split_target_is_skipped_only_once_every_shard_holding_it_passes() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MacFrameworkTests.xctestproducts")
        let githubOutputPath = temporaryDirectory.appending(component: "github_output")
        let runID = "acceptance-test-\(Int.random(in: 100_000 ... 999_999))"

        try await fileSystem.writeText(
            """
            import Foundation
            import XCTest

            final class MacFrameworkShardFailureTests: XCTestCase {
                func testFailsWhenAsked() {
                    XCTAssertNil(ProcessInfo.processInfo.environment["SHARD_FAILURE"])
                }
            }
            """,
            at: fixtureDirectory.appending(components: "MacFramework", "Tests", "MacFrameworkShardFailureTests.swift")
        )
        // Results are parsed, and so uploaded, relative to the project's root, which is found from the
        // working directory.
        try #require(Environment.mocked).currentWorkingDirectoryStub = fixtureDirectory
        // Suite inventories come from CI runs only.
        Environment.mocked?.variables["GITHUB_ACTIONS"] = "true"
        Environment.mocked?.variables["GITHUB_RUN_ATTEMPT"] = "1"
        Environment.mocked?.variables["GITHUB_OUTPUT"] = githubOutputPath.pathString
        Environment.mocked?.variables["TEST_RUNNER_SHARD_FAILURE"] = "1"
        let passthrough = ["--inspect-mode", "local", "--path", fixtureDirectory.pathString, "--"]

        // Suite plans are packed from the suites earlier runs recorded, so record them first.
        Environment.mocked?.variables["GITHUB_RUN_ID"] = "\(runID)-history"
        await #expect(throws: (any Error).self) {
            try await TuistTest.run(TestCommand.self, ["MacFrameworkTests"] + passthrough + ["-destination", "platform=macOS"])
        }

        func buildShards(attempt: Int) async throws -> Int {
            Environment.mocked?.variables["GITHUB_RUN_ID"] = "\(runID)-\(attempt)"
            try await fileSystem.writeText("", at: githubOutputPath, options: Set([.overwrite]))
            if try await fileSystem.exists(testProductsPath) {
                try await fileSystem.remove(testProductsPath)
            }
            try await TuistTest.run(
                TestCommand.self,
                ["MacFrameworkTests", "--build-only", "--shard-total", "2", "--shard-granularity", "suite", "--shard-skip-upload"]
                    + passthrough
                    + ["-testProductsPath", testProductsPath.pathString, "-destination", "platform=macOS"]
            )
            let output = try await fileSystem.readTextFile(at: githubOutputPath)
            let matrix = try #require(output.split(separator: "\n").last { $0.hasPrefix("matrix=") })
            let json = try #require(
                try JSONSerialization.jsonObject(with: Data(String(matrix.dropFirst("matrix=".count)).utf8)) as? [String: Any]
            )
            return try #require(json["shard"] as? [Int]).count
        }

        func runShard(_ index: Int) async -> Bool {
            do {
                try await TuistTest.run(
                    TestCommand.self,
                    ["MacFrameworkTests", "--without-building", "--shard-index", "\(index)"]
                        + passthrough
                        + ["-testProductsPath", testProductsPath.pathString, "-destination", "platform=macOS"]
                )
                return true
            } catch {
                return false
            }
        }

        try #require(try await buildShards(attempt: 1) == 2, "The server didn't plan the two shards this test is about")
        let firstAttempt = [await runShard(0), await runShard(1)]
        try #require(firstAttempt.filter { $0 }.count == 1, "Exactly one shard should hold the failing suite")

        // Rerunning the whole job after the failure must test the target again.
        Environment.mocked?.variables["TEST_RUNNER_SHARD_FAILURE"] = nil
        try #require(try await buildShards(attempt: 2) == 2, "A shard passing its part of the target let the rerun skip it")
        #expect(await runShard(0))
        #expect(await runShard(1))

        // Every shard holding the target passed, so the next run skips it.
        #expect(try await buildShards(attempt: 3) == 0)
    }
}
