import ArgumentParser
import Foundation
import Mockable
import Testing
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer
@testable import TuistRunnerCommand

struct RunnerProfileCommandTests {
    private static let profile = """
    {"id":1,"name":"ci","platform":"macos","vcpus":6,"memory_gb":14,"xcode_version":"26.5","protected":false,
     "cache_writer_default_branch":true,"cache_writer_branches":["develop","release/*"],
     "inserted_at":"2026-10-15T10:00:00Z","updated_at":"2026-10-15T10:00:00Z"}
    """

    @Test func parsesRepeatedBranchesAndDefaultsToTheDefaultBranch() throws {
        let command = try RunnerProfileUpdateCommand.parse([
            "ci", "--save-cache-from", "develop", "--save-cache-from", "release/*",
            "--no-save-cache-from-default-branch", "--account", "acme", "--json",
        ])
        #expect(command.name == "ci")
        #expect(command.saveCacheFrom == ["develop", "release/*"])
        #expect(!command.saveCacheFromDefaultBranch)
        #expect(command.options.account == "acme")
        #expect(command.options.json)

        let reset = try RunnerProfileUpdateCommand.parse(["ci"])
        #expect(reset.saveCacheFrom.isEmpty)
        #expect(reset.saveCacheFromDefaultBranch)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: [false, true])
    func listsProfilesWithTheirCacheBranches(json: Bool) async throws {
        let service = MockListRunnerProfilesServicing()
        let response: RunnerProfileListResult = try RunnerVolumeTestData.decode(
            "{\"profiles\":[\(Self.profile)]}"
        )
        given(service).listRunnerProfiles(
            accountHandle: .value("resolved-account"),
            serverURL: .value(RunnerVolumeTestData.serverURL)
        ).willReturn(response)
        let subject = RunnerProfileListCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            listRunnerProfilesService: service
        )

        try await subject.run(account: nil, path: "/project", json: json)

        #expect(ui().contains(json ? "cache_writer_default_branch" : "Default branch, develop, release/*"))
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedNoora,
        arguments: [
            (true, ["develop", "release/*"], "Default branch, develop, release/*"),
            (false, [], "No branches"),
        ] as [(Bool, [String], String)]
    )
    func updatesTheBranchesThatSaveCache(defaultBranch: Bool, branches: [String], output: String) async throws {
        let service = MockUpdateRunnerProfileServicing()
        let json = Self.profile
            .replacingOccurrences(
                of: "\"cache_writer_default_branch\":true",
                with: "\"cache_writer_default_branch\":\(defaultBranch)"
            )
            .replacingOccurrences(
                of: "[\"develop\",\"release/*\"]",
                with: "[\(branches.map { "\"\($0)\"" }.joined(separator: ","))]"
            )
        let response: RunnerProfileUpdateResult = try RunnerVolumeTestData.decode(json)
        given(service).updateCacheWriterPolicy(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            profileName: .value("ci"),
            defaultBranch: .value(defaultBranch),
            branches: .value(branches)
        ).willReturn(response)
        let subject = RunnerProfileUpdateCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            updateRunnerProfileService: service
        )

        try await subject.run(
            name: "ci",
            defaultBranch: defaultBranch,
            branches: branches,
            account: "acme",
            path: "/project",
            json: false
        )

        verify(service).updateCacheWriterPolicy(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            profileName: .value("ci"),
            defaultBranch: .value(defaultBranch),
            branches: .value(branches)
        ).called(1)
        #expect(ui().contains("Profile ci saves cache from: \(output)."))
    }
}
