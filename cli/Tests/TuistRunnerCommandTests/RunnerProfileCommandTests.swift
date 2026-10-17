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
     "runs_on_label":"tuist-ci","cache_writer_default_branch":true,"cache_writer_branches":["develop","release/*"],
     "inserted_at":"2026-10-15T10:00:00Z","updated_at":"2026-10-15T10:00:00Z"}
    """

    @Test func parsesUpdateOptionsAndKeepsOmittedOnes() throws {
        let command = try RunnerProfileUpdateCommand.parse([
            "ci", "--save-cache-from", "develop", "--save-cache-from", "release/*",
            "--no-save-cache-from-default-branch", "--vcpus", "12", "--memory-gb", "28",
            "--account", "acme", "--json",
        ])
        #expect(command.name == "ci")
        #expect(command.vcpus == 12)
        #expect(command.memoryGB == 28)
        #expect(command.cacheOptions.branches == ["develop", "release/*"])
        #expect(command.cacheOptions.saveCacheFromDefaultBranch == false)
        #expect(command.options.account == "acme")
        #expect(command.options.json)

        #expect(throws: (any Error).self) { try RunnerProfileUpdateCommand.parse(["ci"]) }

        let resized = try RunnerProfileUpdateCommand.parse(["ci", "--xcode-version", "26.4.1"])
        #expect(resized.changes == RunnerProfileChanges(xcodeVersion: "26.4.1"))

        let cleared = try RunnerProfileUpdateCommand.parse(["ci", "--clear-save-cache-from"])
        #expect(cleared.cacheOptions.branches == [])

        #expect(throws: (any Error).self) {
            try RunnerProfileUpdateCommand.parse(["ci", "--clear-save-cache-from", "--save-cache-from", "main"])
        }
    }

    @Test func requiresAnXcodeVersionForMacOSProfilesAndConfirmationToDelete() throws {
        #expect(throws: (any Error).self) {
            try RunnerProfileCreateCommand.parse(["ci", "--platform", "macos", "--vcpus", "6", "--memory-gb", "14"])
        }
        #expect(throws: (any Error).self) {
            try RunnerProfileCreateCommand.parse([
                "ci", "--platform", "linux", "--vcpus", "2", "--memory-gb", "8", "--xcode-version", "26.5",
            ])
        }
        let command = try RunnerProfileCreateCommand.parse([
            "ci", "--platform", "macos", "--vcpus", "6", "--memory-gb", "14", "--xcode-version", "26.5",
        ])
        #expect(command.platform == .macos)
        #expect(command.xcodeVersion == "26.5")

        #expect(throws: (any Error).self) { try RunnerProfileDeleteCommand.parse(["ci"]) }
        #expect(try RunnerProfileDeleteCommand.parse(["ci", "--yes"]).yes)
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

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func listsTheShapesAndXcodeVersionsProfilesCanUse() async throws {
        let service = MockListRunnerProfileOptionsServicing()
        let response: RunnerProfileOptionsResult = try RunnerVolumeTestData.decode("""
        {"shapes":[{"platform":"linux","vcpus":4,"memory_gb":8,"default":false},
                   {"platform":"macos","vcpus":6,"memory_gb":14,"default":true}],
         "xcode_versions":[{"xcode_version":"26.5","default":true},{"xcode_version":"26.4.1","default":false}]}
        """)
        given(service).listRunnerProfileOptions(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL)
        ).willReturn(response)
        let subject = RunnerProfileOptionsCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            listRunnerProfileOptionsService: service
        )

        try await subject.run(account: "acme", path: "/project", json: false)

        #expect(ui().contains("8 GB"))
        #expect(ui().contains("Xcode versions for macOS profiles: 26.5 (default), 26.4.1."))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func createsAProfileAndShowsItsRunsOnLabel() async throws {
        let service = MockCreateRunnerProfileServicing()
        let response: RunnerProfileCreateResult = try RunnerVolumeTestData.decode(Self.profile)
        given(service).createRunnerProfile(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            name: .value("ci"),
            platform: .value(.macos),
            vcpus: .value(6),
            memoryGB: .value(14),
            xcodeVersion: .value("26.5"),
            saveCacheFromDefaultBranch: .value(nil),
            saveCacheFromBranches: .value(["develop", "release/*"])
        ).willReturn(response)
        let subject = RunnerProfileCreateCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            createRunnerProfileService: service
        )

        try await subject.run(
            name: "ci",
            platform: .macos,
            vcpus: 6,
            memoryGB: 14,
            xcodeVersion: "26.5",
            saveCacheFromDefaultBranch: nil,
            saveCacheFromBranches: ["develop", "release/*"],
            account: "acme",
            path: "/project",
            json: false
        )

        #expect(ui().contains("Profile ci created with 6 vCPU, 14 GB, Xcode 26.5."))
        #expect(ui().contains("runs-on: tuist-ci"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func updatesTheShapeAndCacheBranches() async throws {
        let service = MockUpdateRunnerProfileServicing()
        let changes = RunnerProfileChanges(vcpus: 12, memoryGB: 28, saveCacheFromBranches: [])
        let response: RunnerProfileUpdateResult = try RunnerVolumeTestData.decode(
            Self.profile
                .replacingOccurrences(of: "\"vcpus\":6,\"memory_gb\":14", with: "\"vcpus\":12,\"memory_gb\":28")
                .replacingOccurrences(of: "[\"develop\",\"release/*\"]", with: "[]")
        )
        given(service).updateRunnerProfile(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            profileName: .value("ci"),
            changes: .value(changes)
        ).willReturn(response)
        let subject = RunnerProfileUpdateCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            updateRunnerProfileService: service
        )

        try await subject.run(name: "ci", changes: changes, account: "acme", path: "/project", json: false)

        #expect(ui().contains("Profile ci runs on 12 vCPU, 28 GB, Xcode 26.5 and saves cache from: Default branch."))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func deletesAProfile() async throws {
        let service = MockDeleteRunnerProfileServicing()
        given(service).deleteRunnerProfile(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            profileName: .value("ci")
        ).willReturn()
        let subject = RunnerProfileDeleteCommandService(
            configLoader: try await RunnerVolumeTestData.configLoader(),
            serverEnvironmentService: RunnerVolumeTestData.serverEnvironmentService(),
            deleteRunnerProfileService: service
        )

        try await subject.run(name: "ci", account: "acme", path: "/project", json: false)

        verify(service).deleteRunnerProfile(
            accountHandle: .value("acme"),
            serverURL: .value(RunnerVolumeTestData.serverURL),
            profileName: .value("ci")
        ).called(1)
        #expect(ui().contains("Profile ci deleted."))
    }
}
