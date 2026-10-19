import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistProcess
@testable import TuistCAS

struct XcodeCacheInstallationStoreTests {
    @Test(.inTemporaryDirectory)
    func generation_does_not_install_a_launcher() async throws {
        let fixture = try await Fixture()
        #expect(try await !fixture.update("4.213.0", onlyIfInstalled: true))
        #expect(try await !fixture.fileSystem.exists(fixture.directory))
    }

    @Test(.inTemporaryDirectory)
    func setup_installs_a_stable_launcher_and_target() async throws {
        let fixture = try await Fixture()
        #expect(try await fixture.update("4.213.0"))
        let target = try await fixture.target()
        #expect(target.tuistVersion == "4.213.0")
        #expect(target.executable == fixture.executable)
        #expect(try await fixture.fileSystem.readTextFile(at: fixture.launcher) == XcodeCacheInstallationStore.launcher)
    }

    @Test(.inTemporaryDirectory, arguments: ["4.213.1", "4.214.0-rc.1", "5.0.0"])
    func generation_moves_existing_target_forward(version: String) async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.213.0")
        let before = try await fixture.fileSystem.fileMetadata(at: fixture.launcher)
        #expect(try await fixture.update(version, onlyIfInstalled: true))
        #expect(try await fixture.target().tuistVersion == version)
        #expect(try await fixture.fileSystem.fileMetadata(at: fixture.launcher)?.lastModificationDate == before?
            .lastModificationDate)
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func neither_setup_nor_generation_downgrades_the_target(onlyIfInstalled: Bool) async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.214.0")
        #expect(try await !fixture.update("4.213.0", onlyIfInstalled: onlyIfInstalled))
        #expect(try await fixture.target().tuistVersion == "4.214.0")
    }

    @Test(.inTemporaryDirectory)
    func a_release_advances_past_its_prerelease() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.214.0-rc.1")
        #expect(try await fixture.update("4.214.0"))
        #expect(try await !fixture.update("4.214.0-rc.2"))
    }

    @Test(.inTemporaryDirectory)
    func the_same_version_does_not_switch_installations() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.214.0")
        #expect(try await !fixture.subject.update(executable: "/other/tuist", tuistVersion: "4.214.0", onlyIfInstalled: true))
        #expect(try await fixture.target().executable == fixture.executable)
    }

    @Test(.inTemporaryDirectory)
    func an_invalid_version_cannot_replace_the_target() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.214.0")
        await #expect(throws: XcodeCacheInstallationStoreError.invalidVersion("development")) {
            try await fixture.update("development")
        }
        #expect(try await fixture.target().tuistVersion == "4.214.0")
    }

    @Test(.inTemporaryDirectory)
    func missing_executable_preserves_the_previous_target() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.213.0")
        await #expect(throws: XcodeCacheInstallationStoreError.missingExecutable("/missing/tuist")) {
            try await fixture.subject.update(executable: "/missing/tuist", tuistVersion: "4.214.0", onlyIfInstalled: true)
        }
        #expect(try await fixture.target().tuistVersion == "4.213.0")
    }

    @Test(.inTemporaryDirectory)
    func corrupt_target_does_not_grant_permission_to_downgrade() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.214.0")
        try await fixture.fileSystem.writeText("broken", at: fixture.targetPath)
        await #expect(throws: (any Error).self) { try await fixture.update("4.213.0") }
        #expect(try await fixture.fileSystem.readTextFile(at: fixture.targetPath) == "broken")
    }

    @Test(.inTemporaryDirectory)
    func teardown_removes_launcher_and_prevents_generation_from_resurrecting_it() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.213.0")
        let plugin = fixture.directory.appending(component: "libtuist_cas_plugin.dylib")
        try await fixture.fileSystem.writeText("plugin", at: plugin)
        try await fixture.subject.invalidate()
        #expect(try await !fixture.update("4.214.0", onlyIfInstalled: true))
        #expect(try await !fixture.fileSystem.exists(fixture.launcher))
        #expect(try await !fixture.fileSystem.exists(fixture.targetPath))
        #expect(try await fixture.fileSystem.readTextFile(at: plugin) == "plugin")
    }

    @Test(.inTemporaryDirectory)
    func concurrent_updates_select_the_newest_version() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.210.0")
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for version in ["4.212.0", "4.214.0-rc.1", "4.211.0", "4.214.0", "4.213.0"] {
                group.addTask { try await fixture.update(version, onlyIfInstalled: true) }
            }
            for try await _ in group {}
        }
        #expect(try await fixture.target().tuistVersion == "4.214.0")
    }

    @Test(.inTemporaryDirectory)
    func stable_launcher_preserves_arguments_credentials_and_reads_the_latest_target() async throws {
        let fixture = try await Fixture()
        let executable = AbsolutePath("/bin/sh")
        _ = try await fixture.update("4.213.0")
        _ = try await fixture.subject.update(executable: executable, tuistVersion: "4.214.0", onlyIfInstalled: true)

        let output = try await CommandRunner().run(
            arguments: [
                "/bin/sh", fixture.launcher.pathString, fixture.targetPath.pathString,
                "-c", "printf '%s\\n' \"$TUIST_TOKEN\" \"$TUIST_CAS_PROXY_LAUNCH_TARGET\" \"$@\"",
                "cache-proxy", "--url", "https://custom.tuist.dev", "--account", "account with spaces",
            ],
            environment: ["TUIST_TOKEN": "process-scoped-token"]
        ).concatenatedString()

        #expect(output == [
            "process-scoped-token", fixture.targetPath.pathString, "--url", "https://custom.tuist.dev",
            "--account", "account with spaces", "",
        ].joined(separator: "\n"))
        #expect(try await fixture.target().executable == executable)
        #expect(try await !fixture.fileSystem.readTextFile(at: fixture.targetPath).contains("process-scoped-token"))
    }

    private struct Fixture: Sendable {
        let fileSystem = FileSystem()
        let directory: AbsolutePath
        let executable: AbsolutePath
        let subject: XcodeCacheInstallationStore
        var launcher: AbsolutePath { directory.appending(component: "cas-launcher.sh") }
        var targetPath: AbsolutePath { directory.appending(component: "cas-launch-target.json") }

        init() async throws {
            let root = try #require(FileSystem.temporaryTestDirectory)
            directory = root.appending(component: "state")
            executable = root.appending(component: "tuist with spaces")
            try await fileSystem.writeText("binary", at: executable)
            subject = XcodeCacheInstallationStore(fileSystem: fileSystem, directory: directory)
        }

        func update(_ version: String, onlyIfInstalled: Bool = false) async throws -> Bool {
            try await subject.update(executable: executable, tuistVersion: version, onlyIfInstalled: onlyIfInstalled)
        }

        func target() async throws -> XcodeCacheInstallationStore.Target {
            try await fileSystem.readJSONFile(at: targetPath)
        }
    }
}
