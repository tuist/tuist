import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistCAS

struct XcodeCacheInstallationStoreTests {
    @Test(.inTemporaryDirectory)
    func the_same_setup_version_does_not_warn() async throws {
        let fixture = try await Fixture()
        try await fixture.record()

        #expect(await fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func an_older_setup_warns_even_when_plugin_files_are_unchanged() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.212.0")

        let warning = try #require(await fixture.warning())
        #expect(warning.contains("Tuist 4.212.0"))
        #expect(warning.contains("current Tuist 4.213.0"))
        #expect(warning.contains("set up with an older Tuist"))
    }

    @Test(.inTemporaryDirectory)
    func an_older_checkout_does_not_request_a_downgrade() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")

        #expect(await fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func prerelease_versions_are_ordered_before_suppressing_downgrades() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.213.0-rc.1")

        #expect(await fixture.warning(version: "4.213.0-canary.31") == nil)
        #expect(await fixture.warning(version: "4.213.0") != nil)
    }

    @Test(.inTemporaryDirectory)
    func an_unparseable_version_does_not_silently_suppress_warnings() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "unknown")

        #expect(try #require(await fixture.warning()).contains("version could not be compared"))
    }

    @Test(.inTemporaryDirectory)
    func an_older_setup_cannot_reuse_a_newer_manifest_to_suppress_a_warning() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")
        let olderTuist = fixture.root.appending(component: "older-tuist")
        try await fixture.fileSystem.writeText("older CLI", at: olderTuist)
        try await fixture.writeAgent(program: olderTuist)

        let warning = try #require(await fixture.warning())
        #expect(warning.contains("legacy or changed setup"))
        #expect(!warning.contains("last set up with Tuist 4.214.0"))
    }

    @Test(.inTemporaryDirectory)
    func rewriting_the_agent_with_the_same_program_invalidates_the_record() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")
        try await fixture.writeAgent()

        #expect(try #require(await fixture.warning()).contains("legacy or changed setup"))
    }

    @Test(.inTemporaryDirectory)
    func replacing_the_launching_cli_in_place_invalidates_the_record() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")
        try await fixture.fileSystem.setFileTimes(
            of: fixture.program, lastAccessDate: nil, lastModificationDate: Date(timeIntervalSince1970: 100)
        )

        #expect(try #require(await fixture.warning()).contains("legacy or changed setup"))
    }

    @Test(.inTemporaryDirectory)
    func stale_metadata_does_not_hide_the_launch_agents_actual_xcode() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")
        try await fixture.writeAgent(xcode: fixture.root.appending(component: "OtherXcode"))

        let warning = try #require(await fixture.warning())
        #expect(warning.contains("legacy or changed setup"))
        #expect(warning.contains("different Xcode"))
    }

    @Test(.inTemporaryDirectory)
    func a_different_xcode_warns_even_when_the_installed_tuist_is_newer() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")

        let warning = try #require(await fixture.warning(developerDirectory: fixture.root.appending(component: "OtherXcode")))
        #expect(warning.contains("different Xcode"))
    }

    @Test(.inTemporaryDirectory)
    func an_in_place_xcode_update_warns_even_with_a_newer_setup() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")

        #expect(try #require(await fixture.warning(buildVersion: "17G200")).contains("setup-time Xcode build differs"))
    }

    @Test(.inTemporaryDirectory)
    func an_unknown_setup_time_xcode_build_is_not_assumed_current() async throws {
        let fixture = try await Fixture()
        try await fixture.store.record(pluginInstalled: true, xcodeBuildVersion: nil, tuistVersion: "4.213.0")

        #expect(try #require(await fixture.warning()).contains("Xcode build differs or was not recorded"))
    }

    @Test(.inTemporaryDirectory)
    func a_machine_without_setup_is_not_warned_or_modified() async throws {
        let fixture = try await Fixture()
        try await fixture.fileSystem.remove(fixture.installedPlugin)
        try await fixture.fileSystem.remove(fixture.launchAgent)

        #expect(await fixture.warning() == nil)
        #expect(try await !fixture.fileSystem.exists(fixture.manifest))
    }

    @Test(.inTemporaryDirectory)
    func intentional_teardown_does_not_warn_about_the_retained_plugin() async throws {
        let fixture = try await Fixture()
        try await fixture.record()
        try await fixture.store.invalidate()
        try await fixture.fileSystem.remove(fixture.launchAgent)

        #expect(try await fixture.fileSystem.exists(fixture.installedPlugin))
        #expect(await fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func legacy_installs_report_an_unknown_setup_version() async throws {
        let fixture = try await Fixture()

        #expect(try #require(await fixture.warning()).contains("legacy or changed setup"))
    }

    @Test(.inTemporaryDirectory)
    func corrupt_metadata_falls_back_to_the_launch_agent() async throws {
        let fixture = try await Fixture()
        try await fixture.fileSystem.writeText("not JSON", at: fixture.manifest)

        #expect(try #require(await fixture.warning()).contains("legacy or changed setup"))
        #expect(try #require(await fixture.warning(developerDirectory: fixture.root.appending(component: "OtherXcode")))
            .contains("different Xcode"))
    }

    @Test(.inTemporaryDirectory)
    func a_removed_launching_cli_is_reported_even_if_metadata_is_stale() async throws {
        let fixture = try await Fixture()
        try await fixture.record()
        try await fixture.fileSystem.remove(fixture.program)

        #expect(try #require(await fixture.warning())
            .contains("Tuist installation used to launch the cache proxy has been removed"))
    }

    @Test(.inTemporaryDirectory)
    func a_missing_launch_agent_is_reported_when_setup_was_not_torn_down() async throws {
        let fixture = try await Fixture()
        try await fixture.record()
        try await fixture.fileSystem.remove(fixture.launchAgent)

        #expect(try #require(await fixture.warning()).contains("LaunchAgent is missing"))
    }

    @Test(.inTemporaryDirectory, arguments: ["not a plist", "<?xml version=\"1.0\"?><plist><dict/></plist>"])
    func an_invalid_launch_agent_is_reported(configuration: String) async throws {
        let fixture = try await Fixture()
        try await fixture.fileSystem.writeText(configuration, at: fixture.launchAgent)

        #expect(try #require(await fixture.warning()).contains("LaunchAgent configuration could not be read"))
    }

    @Test(.inTemporaryDirectory)
    func a_missing_installed_plugin_is_reported() async throws {
        let fixture = try await Fixture()
        try await fixture.record()
        try await fixture.fileSystem.remove(fixture.installedPlugin)

        #expect(try #require(await fixture.warning()).contains("installed cache plugin is missing"))
    }

    @Test(.inTemporaryDirectory)
    func setup_without_a_shipped_plugin_does_not_report_a_missing_plugin() async throws {
        let fixture = try await Fixture()
        try await fixture.fileSystem.remove(fixture.installedPlugin)
        try await fixture.store.record(pluginInstalled: false, xcodeBuildVersion: "17F113", tuistVersion: "4.213.0")

        #expect(await fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func checking_a_stale_installation_does_not_write_any_files() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.212.0")
        let before = try await fixture.files()

        #expect(await fixture.warning() != nil)
        #expect(try await fixture.files() == before)
    }

    @Test(.inTemporaryDirectory)
    func successful_setup_records_configuration_without_copying_credentials() async throws {
        let fixture = try await Fixture()
        try await fixture.record()
        let installation: XcodeCacheInstallationStore.Installation = try await fixture.fileSystem
            .readJSONFile(at: fixture.manifest)

        #expect(installation.tuistVersion == "4.213.0")
        #expect(installation.xcodeBuildVersion == "17F113")
        #expect(installation.pluginInstalled)
        #expect(try await fixture.fileSystem.readTextFile(at: fixture.manifest).contains("secret-token") == false)
    }

    @Test(.inTemporaryDirectory)
    func failed_recording_after_invalidation_cannot_resurrect_old_metadata() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")
        try await fixture.store.invalidate()
        try await fixture.fileSystem.remove(fixture.launchAgent)

        await #expect(throws: (any Error).self) { try await fixture.record() }
        #expect(try await !fixture.fileSystem.exists(fixture.manifest))
    }

    @Test(.inTemporaryDirectory)
    func invalidating_a_missing_manifest_does_not_fail() async throws {
        let fixture = try await Fixture()

        try await fixture.store.invalidate()
        try await fixture.store.invalidate()

        #expect(try await !fixture.fileSystem.exists(fixture.manifest))
    }

    @Test(.inTemporaryDirectory)
    func a_failed_metadata_write_cannot_leave_a_trusted_previous_record() async throws {
        let fixture = try await Fixture()
        try await fixture.record(version: "4.214.0")
        try await fixture.store.invalidate()
        try await fixture.fileSystem.makeDirectory(at: fixture.manifest)

        await #expect(throws: (any Error).self) { try await fixture.record() }
        #expect(try #require(await fixture.warning()).contains("legacy or changed setup"))
    }
}

private struct Fixture {
    let root: AbsolutePath
    let fileSystem = FileSystem()
    let store: XcodeCacheInstallationStore
    let installedPlugin: AbsolutePath
    let program: AbsolutePath
    let launchAgent: AbsolutePath
    let manifest: AbsolutePath
    let xcode: AbsolutePath

    init() async throws {
        root = try #require(FileSystem.temporaryTestDirectory)
        installedPlugin = root.appending(component: "libtuist_cas_plugin.dylib")
        program = root.appending(component: "tuist")
        launchAgent = root.appending(component: "proxy.plist")
        manifest = root.appending(component: "cas-install.json")
        xcode = root.appending(component: "Xcode")
        store = XcodeCacheInstallationStore(fileSystem: fileSystem, directory: root, launchAgentPath: launchAgent)
        for path in [installedPlugin, program] {
            try await fileSystem.writeText("component", at: path)
        }
        try await writeAgent()
    }

    func writeAgent(program: AbsolutePath? = nil, xcode: AbsolutePath? = nil) async throws {
        let previousDate = try await fileSystem.fileMetadata(at: launchAgent)?.lastModificationDate
        let agent = LaunchAgentFixture(
            program: program ?? self.program,
            environmentVariables: ["DEVELOPER_DIR": (xcode ?? self.xcode).pathString, "TUIST_TOKEN": "secret-token"]
        )
        try await fileSystem.writeAsPlist(agent, at: launchAgent)
        if let previousDate {
            try await fileSystem.setFileTimes(
                of: launchAgent,
                lastAccessDate: nil,
                lastModificationDate: previousDate.addingTimeInterval(2)
            )
        }
    }

    func record(version: String = "4.213.0") async throws {
        try await store.record(pluginInstalled: true, xcodeBuildVersion: "17F113", tuistVersion: version)
    }

    func warning(
        version: String = "4.213.0",
        developerDirectory: AbsolutePath? = nil,
        buildVersion: String = "17F113"
    ) async -> String? {
        await store.warning(
            developerDirectory: developerDirectory ?? xcode,
            xcodeBuildVersion: buildVersion,
            tuistVersion: version
        )
    }

    func files() async throws -> [AbsolutePath: Data] {
        var files: [AbsolutePath: Data] = [:]
        for path in try await fileSystem.glob(directory: root, include: ["*"]).collect() {
            files[path] = try await fileSystem.readFile(at: path)
        }
        return files
    }
}

private struct LaunchAgentFixture: Encodable {
    let program: AbsolutePath
    let environmentVariables: [String: String]

    enum CodingKeys: String, CodingKey {
        case program = "Program"
        case environmentVariables = "EnvironmentVariables"
    }
}
