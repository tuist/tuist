import Foundation
import Testing
@testable import SwifterPMCore

struct CLIRunnerTests {
    @Test
    func resolvePreservesCurrentPackageResolved() async throws {
        try await withTemporaryDirectory { root in
            try await writeMinimalPackageManifest(at: root, name: "Fixture")
            let resolved = try await currentResolvedPins(packageDir: root)
            try await ResolvedFile.write(packageDir: root, resolved: resolved)

            try await CLIRunner.run(
                CLI(
                    cachePath: CLIPath(root.appendingPathComponent("cache").path),
                    disableSandbox: true,
                    quiet: true,
                    command: .resolve(.init(packageDir: CLIPath(root.path)))
                ))

            #expect(try await ResolvedFile.read(packageDir: root).pins == resolved.pins)
        }
    }

    @Test
    func updateRefreshesCurrentPackageResolved() async throws {
        try await withTemporaryDirectory { root in
            try await writeMinimalPackageManifest(at: root, name: "Fixture")
            try await ResolvedFile.write(
                packageDir: root,
                resolved: await currentResolvedPins(packageDir: root)
            )

            try await CLIRunner.run(
                CLI(
                    cachePath: CLIPath(root.appendingPathComponent("cache").path),
                    disableSandbox: true,
                    quiet: true,
                    command: .update(.init(packageDir: CLIPath(root.path)))
                ))

            #expect(
                try await !fileSystem.exists(root.appendingPathComponent("Package.resolved").absolutePath)
            )
        }
    }

    @Test
    func chdirResolvesRelativePathsWithoutChangingProcessDirectory() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            try await writeMinimalPackageManifest(at: package, name: "Fixture")

            let currentDirectory = try await fileSystem.currentWorkingDirectory().pathString

            try await CLIRunner.run(
                CLI(
                    chdir: CLIPath(root.path),
                    cachePath: CLIPath("cache"),
                    disableSandbox: true,
                    quiet: true,
                    command: .resolve(.init(packageDir: CLIPath("Package")))
                ))

            #expect(try await fileSystem.currentWorkingDirectory().pathString == currentDirectory)
            #expect(try await fileSystem.exists(root.appendingPathComponent("cache/sources").absolutePath))
        }
    }

    private func currentResolvedPins(packageDir: URL) async throws -> ResolvedPins {
        try ResolvedPins(
            originHash: await ResolvedFile.packageOriginHash(packageDir: packageDir),
            pins: [
                ResolvedPin(
                    identity: "preserved",
                    kind: "unsupported",
                    location: "",
                    state: ResolvedState(branch: nil, revision: "abcdef123456", version: nil)
                ),
            ],
            version: 3
        )
    }
}
