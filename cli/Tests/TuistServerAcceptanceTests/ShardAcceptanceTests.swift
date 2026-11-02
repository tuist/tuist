import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistAcceptanceTesting
import TuistEnvironment
import TuistTesting

@testable import TuistKit
@testable import TuistTestCommand

/// Builds and uploads shard test products, then runs a shard from them, the way a sharded CI
/// workflow does. The build phase starts uploading within a second of creating the plan, so a
/// server that reads the new plan back from a ClickHouse replica that has not fetched it yet fails
/// here.
struct ShardAcceptanceTests {
    @Test(
        .withFixtureConnectedToCanary("generated_ios_app_with_tests", accountHandle: "tuist"),
        .inTemporaryDirectory
    ) func shard_with_remote_test_products() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "MacFrameworkTests.xctestproducts")
        let shardReference = "acceptance-test-\(Int.random(in: 100_000 ... 999_999))"

        Environment.mocked?.variables["GITHUB_ACTIONS"] = "true"
        Environment.mocked?.variables["GITHUB_RUN_ID"] = shardReference
        Environment.mocked?.variables["GITHUB_RUN_ATTEMPT"] = "1"
        let githubOutputPath = temporaryDirectory.appending(component: "github_output")
        try await FileSystem().writeText("", at: githubOutputPath)
        Environment.mocked?.variables["GITHUB_OUTPUT"] = githubOutputPath.pathString

        // Build phase: build tests and upload shard archive to server
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--build-only",
                "--shard-total", "1",
                "--path", fixtureDirectory.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )

        // Test phase: download shard archive and run tests
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--without-building",
                "--shard-index", "0",
                "--path", fixtureDirectory.pathString,
                "--",
                "-destination", "platform=macOS",
            ]
        )
    }
}
