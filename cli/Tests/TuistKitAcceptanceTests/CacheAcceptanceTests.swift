import FileSystem
import Foundation
import Testing
import TuistAcceptanceTesting
import TuistCacheCommand
import TuistEnvironment
import TuistLoggerTesting
import TuistTesting

@testable import TuistKit

final class CacheAcceptanceTestiOSAppWithFrameworks: TuistAcceptanceTestCase {
    func test_ios_app_with_frameworks() async throws {
        try await withMockedDependencies {
            try await setUpFixture("generated_ios_app_with_frameworks")
            try await run(CacheCommand.self, "--print-hashes")
        }
    }
}

struct CacheConfigAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_app")
    )
    func cache_config_reads_project_and_url_from_tuist_toml() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)
        let fileSystem = FileSystem()
        let canaryURL = Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev"

        try await fileSystem.remove(fixtureDirectory.appending(component: "Tuist.swift"))
        try await fileSystem.writeText(
            """
            project = "\(fullHandle)"
            url = "\(canaryURL)"
            """,
            at: fixtureDirectory.appending(component: "tuist.toml"),
            options: Set([.overwrite])
        )

        try await TuistTest.run(
            CacheConfigCommand.self,
            ["--path", fixtureDirectory.pathString, "--json"]
        )

        let accountHandle = try #require(TuistTest.fixtureAccountHandle)
        TuistTest.expectLogs(accountHandle)
    }
}
