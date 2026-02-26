import FileSystem
import Foundation
import Testing
import TuistCacheCommand
import TuistEnvironment
import TuistNooraTesting
import TuistTesting

@testable import TuistKit

struct CacheAcceptanceTests {
    @Test(.withFixture("generated_ios_app_with_frameworks"), .withMockedDependencies())
    func ios_app_with_frameworks() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(
            CacheCommand.self,
            ["--print-hashes", "--path", fixtureDirectory.pathString]
        )
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
