import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironmentTesting
import TuistGit
import TuistServer
@testable import TuistSnapshotsCommand

struct SnapshotsDownloadServiceTests {
    private static let serverURL = URL(string: "https://snapshots-tests.tuist.dev")!
    private static let sha = "0123456789abcdef0123456789abcdef01234567"

    private let snapshotBuildService = MockSnapshotBuildServicing()
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let gitController = MockGitControlling()

    private static func hash(_ data: Data) -> String {
        SnapshotImages.contentHash(data)
    }

    private static func image(_ name: String, _ content: String) -> ServerSnapshotBaseline.Image {
        .init(
            name: name,
            contentHash: hash(Data(content.utf8)),
            url: URL(string: "https://storage.test/\(hash(Data(content.utf8))).png")!
        )
    }

    private func subject(baseline: ServerSnapshotBaseline) -> SnapshotsDownloadService {
        given(configLoader).loadConfig(path: .any).willReturn(.test(fullHandle: "tuist/ios"))
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Self.serverURL)
        given(gitController).gitInfo(workingDirectory: .any).willReturn(.test(branch: "feature/buttons", sha: Self.sha))
        given(snapshotBuildService).getSnapshotBaseline(
            fullHandle: .value("tuist/ios"),
            serverURL: .value(Self.serverURL),
            set: .value("ios"),
            gitCommitSHA: .value(Self.sha),
            mergeBaseSHA: .any,
            gitRemoteURLOrigin: .any
        ).willReturn(baseline)
        given(snapshotBuildService).downloadSnapshotImage(from: .any, to: .any).willProduce { _, file in
            try FileManager.default.createDirectory(at: file.parentDirectory.url, withIntermediateDirectories: true)
            try Data("downloaded".utf8).write(to: file.url)
        }
        return SnapshotsDownloadService(
            snapshotBuildService: snapshotBuildService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader,
            gitController: gitController
        )
    }

    private static func temporaryDirectory() throws -> AbsolutePath {
        try AbsolutePath(validating: FileManager.default.temporaryDirectory.path)
            .appending(component: "snapshots-download-tests-\(UUID().uuidString)")
    }

    @Test(.withMockedEnvironment())
    func downloadsOnlyTheImagesTheDirectoryDoesNotAlreadyHold() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.url) }
        try FileManager.default.createDirectory(
            at: directory.appending(component: "Buttons").url,
            withIntermediateDirectories: true
        )
        // Card.png already holds the baseline's bytes; Primary.png holds an older recording.
        try Data("card".utf8).write(to: directory.appending(component: "Card.png").url)
        try Data("old primary".utf8).write(to: directory.appending(components: "Buttons", "Primary.png").url)

        let primary = Self.image("Buttons/Primary.png", "primary")
        let dark = Self.image("Onboarding/Dark.png", "dark")
        let baseline = ServerSnapshotBaseline(
            build: ServerSnapshotBuild(id: "main-build", url: "https://tuist.dev/b", state: "processed", status: "baseline"),
            images: [Self.image("Card.png", "card"), primary, dark]
        )

        try await subject(baseline: baseline).download(directory: directory, options: .init(set: "ios", path: directory))

        verify(snapshotBuildService).downloadSnapshotImage(from: .any, to: .any).called(2)
        verify(snapshotBuildService)
            .downloadSnapshotImage(
                from: .value(primary.url),
                to: .value(directory.appending(components: "Buttons", "Primary.png"))
            )
            .called(1)
        verify(snapshotBuildService)
            .downloadSnapshotImage(from: .value(dark.url), to: .value(directory.appending(components: "Onboarding", "Dark.png")))
            .called(1)
        #expect(try String(contentsOf: directory.appending(component: "Card.png").url, encoding: .utf8) == "card")
    }

    @Test(.withMockedEnvironment())
    func refusesImageNamesOutsideTheDirectory() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.url) }

        let escaping = ServerSnapshotBaseline(
            build: ServerSnapshotBuild(id: "main-build", url: "https://tuist.dev/b", state: "processed", status: "baseline"),
            images: [Self.image("Buttons/../../escape.png", "escape")]
        )
        await #expect(throws: SnapshotsDownloadServiceError.invalidImageName("Buttons/../../escape.png")) {
            try await subject(baseline: escaping).download(directory: directory, options: .init(set: "ios", path: directory))
        }
        verify(snapshotBuildService).downloadSnapshotImage(from: .any, to: .any).called(0)
    }

    @Test(.withMockedEnvironment())
    func downloadsNothingWithoutABaseline() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.url) }

        let none = ServerSnapshotBaseline(build: nil, images: [])
        try await subject(baseline: none).download(directory: directory, options: .init(set: "ios", path: directory))

        verify(snapshotBuildService).downloadSnapshotImage(from: .any, to: .any).called(0)
    }
}
