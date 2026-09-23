import Command
import FileSystem
import Foundation
import Path
import Rosalind
import SnapshotTesting
import Testing
import TuistTestSupport

struct RosalindAcceptanceTests {
    private let fileSystem = FileSystem()
    private let subject = Rosalind()

    // We run `assetutils` as part of these acceptance tests, so these won't run on Linux
    #if os(macOS)
        @Test func macos_app() async throws {
            try await withFixtureInTemporaryDirectory("macos_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.app")
                    )

                // Then
                assertRepositorySnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }

        @Test func ios_app() async throws {
            try await withFixtureInTemporaryDirectory("ios_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.app")
                    )

                // Then
                assertRepositorySnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }

        @Test func ios_app_xcarchive() async throws {
            try await withFixtureInTemporaryDirectory("ios_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.xcarchive")
                    )

                // Then
                assertRepositorySnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }

        @Test func ios_app_ipa() async throws {
            try await withFixtureInTemporaryDirectory("ios_app") { _, fixtureDirectory in
                // When
                let got = try await subject
                    .analyzeAppBundle(
                        at: fixtureDirectory.appending(component: "App.ipa")
                    )

                // Then
                assertRepositorySnapshot(
                    of: got,
                    as: .rosalind()
                )
            }
        }
    #endif

    @Test func android_aab() async throws {
        try await withFixtureInTemporaryDirectory("android_app") { _, fixtureDirectory in
            // When
            let got = try await subject
                .analyzeAppBundle(
                    at: fixtureDirectory.appending(component: "app.aab")
                )

            // Then
            // bundletool signs the splits it builds, and the signature it produces depends on the keystore of
            // the machine running it. bundletool also rewrites `AndroidManifest.xml` and `resources.arsc` at
            // split time, and their byte-level output moves between bundletool versions. Neither is portable
            // across environments, so this snapshot asserts the shape of the report only. Numeric coverage
            // lives inline (`installSize > 0`, `downloadSize > 0`), and `RosalindTests.aabBundle` covers that
            // the reported size is the one bundletool measured rather than the size of the `.aab` on disk.
            #expect(try #require(got.downloadSize) > 0)
            #expect(got.installSize > 0)

            assertRepositorySnapshot(
                of: AppBundleReport(
                    bundleId: got.bundleId,
                    name: got.name,
                    type: got.type,
                    installSize: 0,
                    downloadSize: nil,
                    platforms: got.platforms,
                    version: got.version,
                    artifacts: got.artifacts.map(withNormalizedBytes)
                ),
                as: .rosalind()
            )
        }
    }

    /// bundletool rewrites `AndroidManifest.xml` and `resources.arsc` at split time and re-signs the split
    /// APKs, so per-file sizes and shasums differ across bundletool versions and keystores. The acceptance
    /// snapshot zeroes them to keep the tree shape assertable across environments.
    private func withNormalizedBytes(_ artifact: AppBundleArtifact) -> AppBundleArtifact {
        AppBundleArtifact(
            artifactType: artifact.artifactType,
            path: artifact.path,
            size: 0,
            shasum: "",
            children: artifact.children?.map(withNormalizedBytes)
        )
    }

    private func withFixtureInTemporaryDirectory(
        _ fixturePath: String,
        callback: (AbsolutePath, AbsolutePath) async throws -> Void
    ) async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            let sourceFixtureDirectory = try TestPaths.fixturesDirectory.appending(component: "Rosalind")
                .appending(try RelativePath(validating: fixturePath))
            let targetFixtureDirectory = temporaryDirectory.appending(component: sourceFixtureDirectory.basename)
            try await fileSystem.copy(sourceFixtureDirectory, to: targetFixtureDirectory)
            try await callback(temporaryDirectory, targetFixtureDirectory)
        }
    }
}
