#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
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
    func missing_newer_target_can_be_repaired_by_older_setup() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.214.0")
        try await fixture.fileSystem.remove(fixture.executable)
        #expect(try await fixture.subject.update(executable: "/bin/sh", tuistVersion: "4.213.0", onlyIfInstalled: false))
        #expect(try await fixture.target().tuistVersion == "4.213.0")
    }

    @Test(.inTemporaryDirectory)
    func nonexecutable_target_can_be_repaired() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.214.0")
        #expect(chmod(fixture.executable.pathString, 0o644) == 0)
        #expect(try await fixture.subject.update(executable: "/bin/sh", tuistVersion: "4.213.0", onlyIfInstalled: false))
    }

    @Test(.inTemporaryDirectory)
    func startup_high_water_mark_prevents_a_checkout_from_downgrading_an_in_place_upgrade() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.213.0")
        try await fixture.fileSystem.writeAsJSON(
            XcodeCacheInstallationStore.Target(
                executable: fixture.executable, tuistVersion: "4.215.0", highestTuistVersion: "4.215.0"
            ),
            at: fixture.targetPath
        )
        #expect(try await !fixture.update("4.214.0"))
        #expect(try await fixture.target().tuistVersion == "4.215.0")
    }

    @Test(.inTemporaryDirectory)
    func reinstalling_the_highest_version_advances_a_reconciled_rollback() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.update("4.213.0")
        try await fixture.fileSystem.writeAsJSON(
            XcodeCacheInstallationStore.Target(
                executable: fixture.executable, tuistVersion: "4.213.0", highestTuistVersion: "4.215.0"
            ),
            at: fixture.targetPath
        )
        #expect(try await fixture.update("4.215.0", onlyIfInstalled: true))
        #expect(try await fixture.target().tuistVersion == "4.215.0")
    }

    @Test(.inTemporaryDirectory)
    func symlinked_installations_preserve_launch_aliases_but_compare_canonical_identity() async throws {
        let fixture = try await Fixture()
        let alias = fixture.directory.parentDirectory.appending(component: "bundle alias")
        try await fixture.fileSystem.createSymbolicLink(from: alias, to: fixture.executable.parentDirectory)
        let executable = alias.appending(component: fixture.executable.basename)
        #expect(try await fixture.subject.update(executable: executable, tuistVersion: "4.214.0", onlyIfInstalled: false))
        #expect(try await fixture.target().executable == executable)
        #expect(try await fixture.update("4.214.0"))
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
}

struct XcodeCacheLauncherLifecycleTests {
    @Test(
        .inTemporaryDirectory,
        .enabled(if: ProcessInfo.processInfo.environment["TUIST_CAS_PROXY_TEST_BINARY"] != nil)
    )
    func stable_alias_survives_upgrade_cleanup_without_setup_or_generation() async throws {
        let fixture = try await Fixture()
        try await fixture.prepareProxy()
        defer { unlink(fixture.socketDirectory.pathString) }
        let older = try await fixture.cli("4.213.0", in: fixture.root.appending(component: "old bundle"))
        let newer = try await fixture.cli("4.214.0", in: fixture.root.appending(component: "new bundle"))
        let alias = fixture.root.appending(component: "stable bundle")
        try await fixture.fileSystem.createSymbolicLink(from: alias, to: older.parentDirectory)
        let executable = alias.appending(component: "tuist")
        _ = try await fixture.subject.update(executable: executable, tuistVersion: "4.213.0", onlyIfInstalled: false)
        let original = try fixture.startProxy()
        defer { if original.isRunning { kill(original.processIdentifier, SIGKILL) } }
        try await fixture.waitForPlugin("4.213.0")
        #expect(try await fixture.target().executable == executable)

        // Model package-manager alias advancement and cleanup without any update().
        try await fixture.fileSystem.remove(alias)
        try await fixture.fileSystem.createSymbolicLink(from: alias, to: newer.parentDirectory)
        try await fixture.fileSystem.remove(older.parentDirectory)
        #expect(try await fixture.fileSystem.exists(fixture.target().executable))
        original.terminate()
        original.waitUntilExit()
        let replacement = try fixture.startProxy()
        defer { if replacement.isRunning { kill(replacement.processIdentifier, SIGKILL) } }
        try await fixture.waitForPlugin("4.214.0")
        #expect(try await fixture.target().executable == executable)
        #expect(try await fixture.target().tuistVersion == "4.214.0")
    }

    @Test(
        .inTemporaryDirectory,
        .enabled(if: ProcessInfo.processInfo.environment["TUIST_CAS_PROXY_TEST_BINARY"] != nil)
    )
    func real_launcher_drains_relaunches_refreshes_and_recovers_mutable_and_removed_targets() async throws {
        let fixture = try await Fixture()
        try await fixture.prepareProxy()
        defer { unlink(fixture.socketDirectory.pathString) }
        let older = try await fixture.cli("4.213.0", in: fixture.root.appending(component: "old bundle"))
        let newer = try await fixture.cli("4.214.0", in: fixture.root.appending(component: "new bundle"))
        let start = { try fixture.startProxy() }
        let waitForPlugin = { try await fixture.waitForPlugin($0) }
        _ = try await fixture.subject.update(executable: older, tuistVersion: "4.213.0", onlyIfInstalled: false)
        let original = try start()
        defer { if original.isRunning { kill(original.processIdentifier, SIGKILL) } }
        try await waitForPlugin("4.213.0")
        _ = try await fixture.subject.update(executable: newer, tuistVersion: "4.214.0", onlyIfInstalled: true)
        try await fixture.fileSystem.remove(older.parentDirectory)

        // A real protocol request reaches the old process after selection. The
        // target/plugin must not be adopted while its publication remains owed.
        try await fixture.expectPublicationOwed()
        try await Task.sleep(for: .seconds(35))
        #expect(original.isRunning)
        #expect(try await fixture.fileSystem.readTextFile(at: fixture.installedPlugin) == "4.213.0")
        try await fixture.fileSystem.remove(fixture.spool)
        let deadline = ContinuousClock.now + .seconds(25)
        while original.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(!original.isRunning)
        #expect(original.terminationStatus == 75)

        // Relaunch the same entry point, as launchd does. Only the new owner
        // publishes its plugin. Reconcile both an in-place upgrade and rollback.
        let replacement = try start()
        defer { if replacement.isRunning { kill(replacement.processIdentifier, SIGKILL) } }
        try await waitForPlugin("4.214.0")
        replacement.terminate()
        replacement.waitUntilExit()
        try await fixture.verifyMutableVersions(at: newer)

        try await fixture.fileSystem.remove(newer.parentDirectory)
        _ = try await fixture.cli("4.213.0", in: older.parentDirectory)
        #expect(try await fixture.subject.update(executable: older, tuistVersion: "4.213.0", onlyIfInstalled: false))
        let repaired = try start()
        defer { if repaired.isRunning { kill(repaired.processIdentifier, SIGKILL) } }
        try await waitForPlugin("4.213.0")
    }
}

private struct Fixture: Sendable {
    let fileSystem = FileSystem()
    let directory: AbsolutePath
    let executable: AbsolutePath
    let subject: XcodeCacheInstallationStore
    var launcher: AbsolutePath { directory.appending(component: "cas-launcher.sh") }
    var targetPath: AbsolutePath { directory.appending(component: "cas-launch-target.json") }
    var root: AbsolutePath { directory.parentDirectory }
    var socketDirectory: AbsolutePath { AbsolutePath("/tmp/tuist-cas-\(root.basename.prefix(8))") }
    var socket: AbsolutePath { socketDirectory.appending(component: "proxy.sock") }
    var registry: AbsolutePath { root.appending(component: "registry") }
    var store: AbsolutePath { root.appending(component: "store") }
    var spool: AbsolutePath { store.appending(component: "tuist-spool") }
    var installedPlugin: AbsolutePath { directory.appending(component: "libtuist_cas_plugin.dylib") }
    var binary: String { ProcessInfo.processInfo.environment["TUIST_CAS_PROXY_TEST_BINARY", default: ""] }

    init() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        directory = root.appending(component: "state")
        executable = root.appending(component: "tuist with spaces")
        try await fileSystem.writeText("binary", at: executable)
        #expect(chmod(executable.pathString, 0o755) == 0)
        subject = XcodeCacheInstallationStore(fileSystem: fileSystem, directory: directory)
    }

    func update(_ version: String, onlyIfInstalled: Bool = false) async throws -> Bool {
        try await subject.update(executable: executable, tuistVersion: version, onlyIfInstalled: onlyIfInstalled)
    }

    func target() async throws -> XcodeCacheInstallationStore.Target {
        try await fileSystem.readJSONFile(at: targetPath)
    }

    func expectPublicationOwed() async throws {
        do {
            try await CommandRunner().run(
                arguments: [binary, "--drain", store.pathString, "--socket", socket.pathString, "--timeout-ms", "1"]
            ).awaitCompletion()
            Issue.record("The proxy must report the owed publication")
        } catch let CommandError.terminated(code, _, _) {
            #expect(code == 3)
        }
    }

    func prepareProxy() async throws {
        // sockaddr_un cannot hold the test trait's long temporary path.
        try await fileSystem.createSymbolicLink(from: socketDirectory, to: root)
        try await fileSystem.makeDirectory(at: spool)
        // Removing this owed test spool models completed publication, not an upload test.
        try await fileSystem.writeText("owed publication", at: spool.appending(component: "record"))
        try await fileSystem.writeText("\(store.pathString)\taccount/project\n", at: registry)
    }

    func cli(_ version: String, in directory: AbsolutePath) async throws -> AbsolutePath {
        try await fileSystem.makeDirectory(at: directory)
        let executable = directory.appending(component: "tuist")
        try await fileSystem.writeText("""
        #!/bin/sh
        [ "$1" = cache-proxy ] || exit 1
        export TUIST_CAS_TUIST_BIN="$0"
        export TUIST_CAS_TUIST_VERSION="\(version)"
        export TUIST_CAS_BUNDLED_PLUGIN="$(dirname "$0")/libtuist_cas_plugin.dylib"
        exec "$TUIST_TEST_PROXY_BINARY"
        """, at: executable)
        #expect(chmod(executable.pathString, 0o755) == 0)
        try await fileSystem.writeText(version, at: directory.appending(component: "libtuist_cas_plugin.dylib"))
        return executable
    }

    func startProxy() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [launcher.pathString, targetPath.pathString, "cache-proxy"]
        process.environment = [
            "HOME": root.pathString, "PATH": "/usr/bin:/bin", "TUIST_TEST_PROXY_BINARY": binary,
            "TUIST_CAS_PROXY_SOCKET": socket.pathString, "TUIST_CAS_PROXY_REGISTRY": registry.pathString,
            "TUIST_CAS_PREFETCH": "0", "TUIST_CAS_UPSTREAM_PLUGIN": "/missing/test-upstream.dylib",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    func waitForPlugin(_ version: String) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (try? await fileSystem.readTextFile(at: installedPlugin)) != version, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try await fileSystem.readTextFile(at: installedPlugin) == version)
    }

    func verifyMutableVersions(at executable: AbsolutePath) async throws {
        _ = try await cli("4.216.0", in: executable.parentDirectory)
        let inPlace = try startProxy()
        defer { if inPlace.isRunning { kill(inPlace.processIdentifier, SIGKILL) } }
        try await waitForPlugin("4.216.0")
        #expect(try await target().tuistVersion == "4.216.0")
        #expect(try await !subject.update(executable: self.executable, tuistVersion: "4.215.0", onlyIfInstalled: true))
        inPlace.terminate()
        inPlace.waitUntilExit()
        _ = try await cli("4.214.0", in: executable.parentDirectory)
        let rollback = try startProxy()
        defer { if rollback.isRunning { kill(rollback.processIdentifier, SIGKILL) } }
        try await waitForPlugin("4.214.0")
        #expect(try await target().tuistVersion == "4.214.0")
        #expect(try await target().highestTuistVersion == "4.216.0")
        rollback.terminate()
        rollback.waitUntilExit()
    }
}
