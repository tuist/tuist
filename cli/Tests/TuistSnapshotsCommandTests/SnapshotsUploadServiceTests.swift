import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGit
import TuistServer
@testable import TuistSnapshotsCommand

struct SnapshotsUploadServiceTests {
    private static let serverURL = URL(string: "https://snapshots-tests.tuist.dev")!
    private static let sha = "0123456789abcdef0123456789abcdef01234567"
    /// The SHA-256 of `png(width: 390, height: 844, payload: "button")`, from `hashlib.sha256`.
    private static let buttonHash = "129e23f8ae85089bc153db6805c9b707700bd37c638ff84029ca1ea3973727f0"

    private let snapshotBuildService = MockSnapshotBuildServicing()
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let gitController = MockGitControlling()

    /// A PNG header with the given size: the uploader reads only the signature and IHDR chunk.
    private static func png(width: UInt32, height: UInt32, payload: String) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
        data.append(contentsOf: Array("IHDR".utf8))
        for value in [width, height] {
            data.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
        }
        data.append(contentsOf: Array(payload.utf8))
        return data
    }

    private static func directory(_ files: [String: Data]) throws -> AbsolutePath {
        let directory = try AbsolutePath(validating: FileManager.default.temporaryDirectory.path)
            .appending(component: "snapshots-tests-\(UUID().uuidString)")
        for (name, data) in files {
            let path = directory.appending(try RelativePath(validating: name))
            try FileManager.default.createDirectory(at: path.parentDirectory.url, withIntermediateDirectories: true)
            try data.write(to: path.url)
        }
        return directory
    }

    private func subject() -> SnapshotsUploadService {
        given(configLoader).loadConfig(path: .any).willReturn(.test(fullHandle: "tuist/ios"))
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Self.serverURL)
        given(gitController).gitInfo(workingDirectory: .any).willReturn(
            .test(ref: "refs/pull/42/merge", branch: "feature/buttons", sha: Self.sha, pullRequestNumber: 42)
        )
        return SnapshotsUploadService(
            snapshotBuildService: snapshotBuildService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader,
            gitController: gitController,
            pollInterval: .zero
        )
    }

    private static func build(status: String, changed: Int = 0, unchanged: Int = 0) -> ServerSnapshotBuild {
        ServerSnapshotBuild(
            id: "build-1",
            url: "https://tuist.dev/tuist/ios/snapshots/build-1",
            state: status == "processing" ? "processing" : "processed",
            status: status,
            changedCount: changed,
            unchangedCount: unchanged
        )
    }

    @Test
    func collectsImagesWithTheirSidecarMetadataAndSkipsDerivedFiles() async throws {
        let directory = try Self.directory([
            "Buttons/Primary.png": Self.png(width: 390, height: 844, payload: "button"),
            "Buttons/Primary.json": Data("""
            {"display_name": "Primary button", "group": "Buttons", "tags": {"theme": "dark", "scale": 2}, "diff_threshold": 0}
            """.utf8),
            "Buttons/Primary_diff.png": Self.png(width: 1, height: 1, payload: "diff"),
            "Card.png": Self.png(width: 1, height: 2, payload: "card"),
            "Card.json": Data(#"{"tags": ["landscape"]}"#.utf8),
        ])
        defer { try? FileManager.default.removeItem(at: directory.url) }

        let images = try await SnapshotImages.collect(directory: directory).map(\.manifest)

        #expect(images == [
            SnapshotImageManifest(
                name: "Buttons/Primary.png",
                contentHash: Self.buttonHash,
                width: 390,
                height: 844,
                displayName: "Primary button",
                group: "Buttons",
                tags: ["theme": "dark", "scale": "2"],
                diffThreshold: 0
            ),
            SnapshotImageManifest(
                name: "Card.png",
                contentHash: images.last?.contentHash ?? "",
                width: 1,
                height: 2,
                tags: ["landscape": "true"]
            ),
        ])
        #expect(images.last?.contentHash != Self.buttonHash)
    }

    @Test(.withMockedEnvironment())
    func uploadsOnlyTheImagesTheServerLacksAndFailsOnUnreviewedChanges() async throws {
        let directory = try Self.directory([
            "Primary.png": Self.png(width: 390, height: 844, payload: "button"),
            "Secondary.png": Self.png(width: 390, height: 844, payload: "secondary"),
            "Secondary.json": Data(#"{"diff_threshold": 0.2}"#.utf8),
            "tuist-all-image-names.txt": Data("Primary.png\nSecondary.png\nRemoved.png\nPrimary.png\n".utf8),
        ])
        defer { try? FileManager.default.removeItem(at: directory.url) }
        let uploadURL = URL(string: "https://storage.tuist.dev/blobs/primary?signature=1")!
        let manifests = Recorder<SnapshotBuildManifest>()
        given(snapshotBuildService).createSnapshotBuild(
            fullHandle: .value("tuist/ios"),
            serverURL: .value(Self.serverURL),
            manifest: .any
        )
        .willProduce { _, _, manifest in
            manifests.append(manifest)
            return CreatedSnapshotBuild(
                build: Self.build(status: "processing"),
                uploads: [.init(contentHash: Self.buttonHash, url: uploadURL)]
            )
        }
        given(snapshotBuildService).uploadSnapshotImage(.any, to: .any).willReturn()
        given(snapshotBuildService).completeSnapshotBuild(fullHandle: .any, serverURL: .any, buildID: .value("build-1"))
            .willReturn(Self.build(status: "processing"))
        let polls = Recorder<Int>()
        given(snapshotBuildService).getSnapshotBuild(fullHandle: .any, serverURL: .any, buildID: .value("build-1"))
            .willProduce { _, _, _ in
                polls.append(1)
                return polls.count < 3 ? Self.build(status: "processing") : Self.build(
                    status: "needs_review",
                    changed: 1,
                    unchanged: 1
                )
            }

        await #expect(throws: SnapshotsUploadServiceError.changesNeedReview(
            summary: "1 changed, 0 added, 0 removed, 0 renamed, 1 unchanged, 0 skipped",
            url: "https://tuist.dev/tuist/ios/snapshots/build-1"
        )) {
            try await subject().upload(
                directory: directory,
                options: SnapshotsUploadOptions(set: "ios-iphone", path: directory, diffThreshold: 0.05, buildSystem: .xcode)
            )
        }

        let manifest = try #require(manifests.values.first)
        #expect(manifest.set == "ios-iphone")
        #expect(manifest.gitCommitSHA == Self.sha)
        #expect(manifest.pullRequestNumber == 42)
        #expect(manifest.buildSystem == .xcode)
        #expect(manifest.allImageNames == ["Primary.png", "Secondary.png", "Removed.png"])
        // The command's threshold fills in only for images whose metadata doesn't set one.
        #expect(manifest.images.map(\.name) == ["Primary.png", "Secondary.png"])
        #expect(manifest.images.map(\.diffThreshold) == [0.05, 0.2])
        verify(snapshotBuildService).uploadSnapshotImage(.any, to: .any).called(1)
        verify(snapshotBuildService).uploadSnapshotImage(
            .value(directory.appending(component: "Primary.png")),
            to: .value(uploadURL)
        )
        .called(1)
        #expect(polls.count == 3)
    }

    @Test(.withMockedEnvironment())
    func reportsUnreviewedChangesWithoutFailingWhenAsked() async throws {
        let directory = try Self.directory(["Primary.png": Self.png(width: 1, height: 1, payload: "button")])
        defer { try? FileManager.default.removeItem(at: directory.url) }
        given(snapshotBuildService).createSnapshotBuild(fullHandle: .any, serverURL: .any, manifest: .any)
            .willReturn(CreatedSnapshotBuild(build: Self.build(status: "processing"), uploads: []))
        given(snapshotBuildService).completeSnapshotBuild(fullHandle: .any, serverURL: .any, buildID: .any)
            .willReturn(Self.build(status: "processing"))
        given(snapshotBuildService).getSnapshotBuild(fullHandle: .any, serverURL: .any, buildID: .any)
            .willReturn(Self.build(status: "rejected", changed: 1))

        let build = try await subject().upload(
            directory: directory,
            options: SnapshotsUploadOptions(set: "ios-iphone", path: directory, failOnChanges: false)
        )

        #expect(build?.status == "rejected")
        verify(snapshotBuildService).uploadSnapshotImage(.any, to: .any).called(0)
    }

    @Test
    func uploadsTheExportedImagesWhenTestsFailAndRethrowsTheTestFailure() async throws {
        struct TestsFailed: Error, Equatable {}
        let uploadService = MockSnapshotsUploadServicing()
        let uploads = Recorder<(names: [String], options: SnapshotsUploadOptions)>()
        given(uploadService).upload(directory: .any, options: .any).willProduce { directory, options in
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.pathString).sorted()
            uploads.append((names, options))
            return Self.build(status: "needs_review", changed: 1)
        }
        let path = try AbsolutePath(validating: "/project")
        let exportDirectories = Recorder<String>()

        await #expect(throws: TestsFailed()) {
            try await SnapshotsTestRunner(uploadService: uploadService).run(
                enabled: true,
                set: "App",
                path: path,
                skippedTests: { true },
                tests: { environment in
                    let directory = try #require(environment["TEST_RUNNER_SNAPSHOTS_EXPORT_DIR"])
                    exportDirectories.append(directory)
                    try Self.png(width: 1, height: 1, payload: "card")
                        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("Card.png"))
                    throw TestsFailed()
                }
            )
        }

        let upload = try #require(uploads.values.first)
        #expect(upload.names == ["Card.png"])
        #expect(upload.options == SnapshotsUploadOptions(
            set: "App",
            path: path,
            selective: true,
            failOnChanges: false,
            buildSystem: .xcode
        ))
        // The export directory is temporary.
        let directory = try #require(exportDirectories.values.first)
        #expect(!FileManager.default.fileExists(atPath: directory))
    }

    struct AutomaticCase: CustomTestStringConvertible, Sendable {
        var name: String
        var enabled: Bool?
        var variables: [String: String]
        var fullHandle: String?
        var rendersImages: Bool
        var exports: Bool
        var uploads: Bool

        var testDescription: String { name }
    }

    @Test(.withMockedEnvironment(), arguments: [
        AutomaticCase(
            name: "CI, connected", enabled: nil, variables: ["CI": "true"], fullHandle: "tuist/ios",
            rendersImages: true, exports: true, uploads: true
        ),
        AutomaticCase(
            name: "CI, no previews rendered", enabled: nil, variables: ["CI": "true"], fullHandle: "tuist/ios",
            rendersImages: false, exports: true, uploads: false
        ),
        AutomaticCase(
            name: "local run", enabled: nil, variables: [:], fullHandle: "tuist/ios",
            rendersImages: true, exports: false, uploads: false
        ),
        AutomaticCase(
            name: "CI, not connected", enabled: nil, variables: ["CI": "true"], fullHandle: nil,
            rendersImages: true, exports: false, uploads: false
        ),
        AutomaticCase(
            name: "CI, caller exports itself", enabled: nil,
            variables: ["CI": "true", "TEST_RUNNER_SNAPSHOTS_EXPORT_DIR": "/tmp/sentry"], fullHandle: "tuist/ios",
            rendersImages: true, exports: false, uploads: false
        ),
        AutomaticCase(
            name: "--no-snapshots in CI", enabled: false, variables: ["CI": "true"], fullHandle: "tuist/ios",
            rendersImages: true, exports: false, uploads: false
        ),
        AutomaticCase(
            name: "--snapshots locally", enabled: true, variables: [:], fullHandle: "tuist/ios",
            rendersImages: true, exports: true, uploads: true
        ),
    ])
    func decidesWhetherToExportAndUploadSnapshots(_ testCase: AutomaticCase) async throws {
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables = testCase.variables
        let uploadService = MockSnapshotsUploadServicing()
        given(uploadService).upload(directory: .any, options: .any).willReturn(Self.build(status: "approved"))
        given(configLoader).loadConfig(path: .any).willReturn(.test(fullHandle: testCase.fullHandle))
        let environments = Recorder<[String: String]>()

        try await SnapshotsTestRunner(uploadService: uploadService, configLoader: configLoader).run(
            enabled: testCase.enabled,
            set: "App",
            path: try AbsolutePath(validating: "/project"),
            skippedTests: { false },
            tests: { environment in
                environments.append(environment)
                if testCase.rendersImages, let directory = environment["TEST_RUNNER_SNAPSHOTS_EXPORT_DIR"] {
                    try Self.png(width: 1, height: 1, payload: "card")
                        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("Card.png"))
                }
            }
        )

        #expect(environments.values.map { $0["TEST_RUNNER_SNAPSHOTS_EXPORT_DIR"] != nil } == [testCase.exports])
        verify(uploadService).upload(directory: .any, options: .any).called(testCase.uploads ? 1 : 0)
    }

    @Test
    func readsThePullRequestTitleFromGitLabFirstThenTheGitHubEvent() throws {
        let event = try Self.directory(["event.json": Data(#"{"pull_request": {"title": "Refresh the buttons"}}"#.utf8)])
            .appending(component: "event.json")
        defer { try? FileManager.default.removeItem(at: event.parentDirectory.url) }

        #expect(SnapshotsUploadService
            .pullRequestTitle(environment: ["GITHUB_EVENT_PATH": event.pathString]) == "Refresh the buttons")
        #expect(SnapshotsUploadService.pullRequestTitle(environment: [
            "CI_MERGE_REQUEST_TITLE": "Draft: new cards",
            "GITHUB_EVENT_PATH": event.pathString,
        ]) == "Draft: new cards")
        #expect(SnapshotsUploadService.pullRequestTitle(environment: ["CI_MERGE_REQUEST_TITLE": "  "]) == nil)
    }
}

private final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] { lock.withLock { storage } }
    var count: Int { lock.withLock { storage.count } }

    func append(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}
