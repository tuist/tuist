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
     "cache_writer_branches":["main","release/*"],"inserted_at":"2026-10-15T10:00:00Z","updated_at":"2026-10-15T10:00:00Z"}
    """

    @Test func parsesRepeatedBranchesAndTheDefaultBranchFlag() throws {
        let command = try RunnerProfileUpdateCommand.parse([
            "ci", "--save-cache-from", "main", "--save-cache-from", "release/*", "--account", "acme", "--json",
        ])
        #expect(command.name == "ci")
        #expect(command.saveCacheFrom == ["main", "release/*"])
        #expect(!command.saveCacheFromDefaultBranch)
        #expect(command.options.account == "acme")
        #expect(command.options.json)

        let reset = try RunnerProfileUpdateCommand.parse(["ci", "--save-cache-from-default-branch"])
        #expect(reset.saveCacheFrom.isEmpty)
        #expect(reset.saveCacheFromDefaultBranch)
    }

    @Test func requiresExactlyOneBranchSource() {
        #expect(throws: (any Error).self) { try RunnerProfileUpdateCommand.parseAsRoot(["ci"]) }
        #expect(throws: (any Error).self) {
            try RunnerProfileUpdateCommand.parseAsRoot([
                "ci", "--save-cache-from", "main", "--save-cache-from-default-branch",
            ])
        }
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

        #expect(ui().contains(json ? "cache_writer_branches" : "main, release/*"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora, arguments: [["main", "release/*"], nil] as [[String]?])
    func updatesTheBranchesThatSaveCache(branches: [String]?) async throws {
        let service = MockUpdateRunnerProfileServicing()
        let json = branches == nil ? Self.profile.replacingOccurrences(
            of: "[\"main\",\"release/*\"]",
            with: "null"
        ) : Self.profile
        let response: RunnerProfileUpdateResult = try RunnerVolumeTestData.decode(json)
        given(service).updateCacheWriterBranches(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            profileName: .value("ci"),
            branches: .value(branches)
        ).willReturn(response)
        let subject = RunnerProfileUpdateCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            updateRunnerProfileService: service
        )

        try await subject.run(name: "ci", branches: branches, account: "acme", path: "/project", json: false)

        verify(service).updateCacheWriterBranches(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            profileName: .value("ci"),
            branches: .value(branches)
        ).called(1)
        #expect(ui().contains(branches == nil ? "default branch" : "main, release/*"))
    }
}
