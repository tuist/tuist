import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import TuistCAS

struct XcodeCacheInstallationStoreTests {
    @Test(.inTemporaryDirectory)
    func the_same_setup_version_does_not_warn() throws {
        let fixture = try Fixture()
        try fixture.record()

        #expect(fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func an_older_setup_warns_even_when_plugin_and_proxy_files_are_unchanged() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.212.0")

        let warning = try #require(fixture.warning())
        #expect(warning.contains("Tuist 4.212.0"))
        #expect(warning.contains("current Tuist 4.213.0"))
        #expect(warning.contains("set up with an older Tuist"))
    }

    @Test(.inTemporaryDirectory)
    func an_older_checkout_does_not_request_a_downgrade() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")

        #expect(fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func prerelease_versions_are_ordered_before_suppressing_downgrades() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.213.0-rc.1")

        #expect(fixture.warning(version: "4.213.0-canary.31") == nil)
        #expect(fixture.warning(version: "4.213.0") != nil)
    }

    @Test(.inTemporaryDirectory)
    func an_unparseable_version_does_not_silently_suppress_warnings() throws {
        let fixture = try Fixture()
        try fixture.record(version: "unknown")

        #expect(try #require(fixture.warning()).contains("version could not be compared"))
    }

    @Test(.inTemporaryDirectory)
    func an_older_setup_cannot_reuse_a_newer_manifest_to_suppress_a_warning() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")
        let olderTuist = fixture.root.appendingPathComponent("older-tuist")
        try Data("older CLI".utf8).write(to: olderTuist)
        try fixture.writeAgent(program: olderTuist)

        let warning = try #require(fixture.warning())
        #expect(warning.contains("legacy or changed setup"))
        #expect(!warning.contains("last set up with Tuist 4.214.0"))
    }

    @Test(.inTemporaryDirectory)
    func rewriting_the_agent_with_the_same_program_invalidates_the_record() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")
        try fixture.writeAgent()

        #expect(try #require(fixture.warning()).contains("legacy or changed setup"))
    }

    @Test(.inTemporaryDirectory)
    func replacing_the_launching_cli_in_place_invalidates_the_record() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: fixture.program.path
        )

        #expect(try #require(fixture.warning()).contains("legacy or changed setup"))
    }

    @Test(.inTemporaryDirectory)
    func stale_metadata_does_not_hide_the_launch_agents_actual_xcode() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")
        try fixture.writeAgent(xcode: fixture.root.appendingPathComponent("OtherXcode"))

        let warning = try #require(fixture.warning())
        #expect(warning.contains("legacy or changed setup"))
        #expect(warning.contains("different Xcode"))
    }

    @Test(.inTemporaryDirectory)
    func a_different_xcode_warns_even_when_the_installed_tuist_is_newer() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")

        let warning = try #require(fixture.warning(developerDirectory: fixture.root.appendingPathComponent("OtherXcode")))
        #expect(warning.contains("different Xcode"))
    }

    @Test(.inTemporaryDirectory)
    func an_in_place_xcode_update_warns_even_with_a_newer_setup() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")

        #expect(try #require(fixture.warning(buildVersion: "17G200")).contains("setup-time Xcode build differs"))
    }

    @Test(.inTemporaryDirectory)
    func an_unknown_setup_time_xcode_build_is_not_assumed_current() throws {
        let fixture = try Fixture()
        try fixture.store.record(
            plugin: fixture.installedPlugin,
            proxy: fixture.proxy,
            xcodeBuildVersion: nil,
            tuistVersion: "4.213.0"
        )

        #expect(try #require(fixture.warning()).contains("Xcode build differs or was not recorded"))
    }

    @Test(.inTemporaryDirectory)
    func xcode_symlinks_do_not_cause_a_false_warning() throws {
        let fixture = try Fixture()
        let xcode = fixture.root.appendingPathComponent("SelectedXcode")
        try FileManager.default.createDirectory(at: fixture.xcode, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: xcode, withDestinationURL: fixture.xcode)
        try fixture.record()

        #expect(fixture.warning(developerDirectory: xcode) == nil)
    }

    @Test(.inTemporaryDirectory)
    func a_machine_without_setup_is_not_warned_or_modified() throws {
        let fixture = try Fixture()
        try FileManager.default.removeItem(at: fixture.installedPlugin)
        try FileManager.default.removeItem(at: fixture.launchAgent)

        #expect(fixture.warning() == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.manifest.path))
    }

    @Test(.inTemporaryDirectory)
    func intentional_teardown_does_not_warn_about_the_retained_plugin() throws {
        let fixture = try Fixture()
        try fixture.record()
        try FileManager.default.removeItem(at: fixture.launchAgent)
        try fixture.store.invalidate()

        #expect(FileManager.default.fileExists(atPath: fixture.installedPlugin.path))
        #expect(fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func legacy_installs_report_an_unknown_setup_version() throws {
        let fixture = try Fixture()

        #expect(try #require(fixture.warning()).contains("legacy or changed setup"))
    }

    @Test(.inTemporaryDirectory)
    func corrupt_metadata_falls_back_to_the_launch_agent() throws {
        let fixture = try Fixture()
        try Data("not JSON".utf8).write(to: fixture.manifest)

        #expect(try #require(fixture.warning()).contains("legacy or changed setup"))
        #expect(try #require(fixture.warning(developerDirectory: fixture.root.appendingPathComponent("OtherXcode")))
            .contains("different Xcode"))
    }

    @Test(.inTemporaryDirectory)
    func removed_proxy_installations_are_reported() throws {
        let fixture = try Fixture()
        try fixture.record()
        try FileManager.default.removeItem(at: fixture.proxy)

        #expect(try #require(fixture.warning()).contains("installation has been removed"))
    }

    @Test(.inTemporaryDirectory)
    func a_removed_launching_cli_is_reported_even_if_metadata_is_stale() throws {
        let fixture = try Fixture()
        try fixture.record()
        try FileManager.default.removeItem(at: fixture.program)

        #expect(try #require(fixture.warning()).contains("Tuist installation used to launch the cache proxy has been removed"))
    }

    @Test(.inTemporaryDirectory)
    func a_missing_launch_agent_is_reported_when_setup_was_not_torn_down() throws {
        let fixture = try Fixture()
        try fixture.record()
        try FileManager.default.removeItem(at: fixture.launchAgent)

        #expect(try #require(fixture.warning()).contains("LaunchAgent is missing"))
    }

    @Test(.inTemporaryDirectory, arguments: ["not a plist", "<?xml version=\"1.0\"?><plist><dict/></plist>"])
    func an_invalid_launch_agent_is_reported(configuration: String) throws {
        let fixture = try Fixture()
        try Data(configuration.utf8).write(to: fixture.launchAgent)

        #expect(try #require(fixture.warning()).contains("LaunchAgent configuration could not be read"))
    }

    @Test(.inTemporaryDirectory)
    func a_missing_installed_plugin_is_reported() throws {
        let fixture = try Fixture()
        try fixture.record()
        try FileManager.default.removeItem(at: fixture.installedPlugin)

        #expect(try #require(fixture.warning()).contains("installed cache plugin is missing"))
    }

    @Test(.inTemporaryDirectory)
    func setup_without_a_shipped_plugin_does_not_report_a_missing_plugin() throws {
        let fixture = try Fixture()
        try FileManager.default.removeItem(at: fixture.installedPlugin)
        try fixture.store.record(plugin: nil, proxy: fixture.proxy, xcodeBuildVersion: "17F113", tuistVersion: "4.213.0")

        #expect(fixture.warning() == nil)
    }

    @Test(.inTemporaryDirectory)
    func checking_a_stale_installation_does_not_write_any_files() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.212.0")
        let before = try fixture.files()

        #expect(fixture.warning() != nil)
        #expect(try fixture.files() == before)
    }

    @Test(.inTemporaryDirectory)
    func successful_setup_records_configuration_without_copying_credentials() throws {
        let fixture = try Fixture()
        try fixture.record()
        let data = try Data(contentsOf: fixture.manifest)
        let installation = try JSONDecoder().decode(XcodeCacheInstallationStore.Installation.self, from: data)

        #expect(installation.tuistVersion == "4.213.0")
        #expect(installation.launchAgentProgram == fixture.program.resolvingSymlinksInPath().path)
        #expect(installation.proxyPath == fixture.proxy.resolvingSymlinksInPath().path)
        #expect(installation.developerDirectory == fixture.xcode.resolvingSymlinksInPath().path)
        #expect(installation.xcodeBuildVersion == "17F113")
        #expect(installation.pluginInstalled)
        let metadata = try #require(String(data: data, encoding: .utf8))
        #expect(!metadata.contains("secret-token"))
    }

    @Test(.inTemporaryDirectory)
    func failed_recording_after_invalidation_cannot_resurrect_old_metadata() throws {
        let fixture = try Fixture()
        try fixture.record(version: "4.214.0")
        try fixture.store.invalidate()
        try FileManager.default.removeItem(at: fixture.launchAgent)

        #expect(throws: (any Error).self) { try fixture.record() }
        #expect(!FileManager.default.fileExists(atPath: fixture.manifest.path))
        try fixture.store.invalidate()
    }
}

private struct Fixture {
    let root: URL
    let store: XcodeCacheInstallationStore
    let installedPlugin: URL
    let proxy: URL
    let program: URL
    let launchAgent: URL
    let manifest: URL
    let xcode: URL

    init() throws {
        root = try #require(FileSystem.temporaryTestDirectory).url
        installedPlugin = root.appendingPathComponent("libtuist_cas_plugin.dylib")
        proxy = root.appendingPathComponent("tuist-cas-proxy")
        program = root.appendingPathComponent("tuist")
        launchAgent = root.appendingPathComponent("proxy.plist")
        manifest = root.appendingPathComponent("cas-install.json")
        xcode = root.appendingPathComponent("Xcode")
        store = XcodeCacheInstallationStore(directory: root, launchAgent: launchAgent)
        for path in [installedPlugin, proxy, program] {
            try Data("component".utf8).write(to: path)
        }
        try writeAgent()
    }

    func writeAgent(program: URL? = nil, xcode: URL? = nil) throws {
        let previousDate = (try? FileManager.default.attributesOfItem(atPath: launchAgent.path)[.modificationDate]) as? Date
        let plist: [String: Any] = [
            "Program": (program ?? self.program).path,
            "EnvironmentVariables": ["DEVELOPER_DIR": (xcode ?? self.xcode).path, "TUIST_TOKEN": "secret-token"],
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: launchAgent)
        if let previousDate {
            try FileManager.default.setAttributes(
                [.modificationDate: previousDate.addingTimeInterval(2)],
                ofItemAtPath: launchAgent.path
            )
        }
    }

    func record(version: String = "4.213.0") throws {
        try store.record(plugin: installedPlugin, proxy: proxy, xcodeBuildVersion: "17F113", tuistVersion: version)
    }

    func warning(version: String = "4.213.0", developerDirectory: URL? = nil, buildVersion: String = "17F113") -> String? {
        store.warning(developerDirectory: developerDirectory ?? xcode, xcodeBuildVersion: buildVersion, tuistVersion: version)
    }

    func files() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
}
