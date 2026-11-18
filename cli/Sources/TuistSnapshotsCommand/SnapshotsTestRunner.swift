import Foundation
import Path
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistServer

/// Runs a test action with the tuist/snapshots library exporting the previews it renders, then uploads them as
/// a snapshot build. `tuist test` and `tuist xcodebuild test` share it.
public struct SnapshotsTestRunner {
    /// tuist/snapshots writes each rendered preview, as a PNG with a JSON sidecar, to
    /// `SNAPSHOTS_EXPORT_DIR`. xcodebuild passes `TEST_RUNNER_`-prefixed variables to the test
    /// process without the prefix.
    public static let exportDirectoryVariable = "TEST_RUNNER_SNAPSHOTS_EXPORT_DIR"

    private let uploadService: SnapshotsUploadServicing
    private let configLoader: ConfigLoading

    public init(
        uploadService: SnapshotsUploadServicing = SnapshotsUploadService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.uploadService = uploadService
        self.configLoader = configLoader
    }

    /// Runs `tests` with the variables to pass to xcodebuild, then uploads the exported images,
    /// also when tests failed, so the changes can be reviewed either way. A test failure wins over
    /// the snapshot verdict, which then only warns.
    /// - Parameters:
    ///   - enabled: `--snapshots` (true), `--no-snapshots` (false), or neither (nil). Without
    ///     either, snapshots are on only in CI for a project connected to Tuist, and a run that
    ///     renders no images uploads nothing, so tests without the library are unaffected. Local
    ///     runs stay off, because they would upload uncommitted changes and fail on them.
    ///   - set: The snapshot set the images belong to.
    ///   - path: The Tuist project's directory.
    ///   - skippedTests: Whether the run skipped tests, read once it finished: images it didn't
    ///     render are then skipped rather than removed.
    ///   - tests: Runs the tests with the given variables added to xcodebuild's environment.
    public func run(
        enabled: Bool?,
        set: String,
        path: AbsolutePath,
        skippedTests: () async -> Bool,
        tests: ([String: String]) async throws -> Void
    ) async throws {
        guard await isEnabled(enabled, path: path) else { return try await tests([:]) }
        let exportDirectory = try AbsolutePath(validating: FileManager.default.temporaryDirectory.path)
            .appending(component: "tuist-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: exportDirectory.url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDirectory.url) }

        var testError: Error?
        do {
            try await tests([Self.exportDirectoryVariable: exportDirectory.pathString])
        } catch {
            testError = error
        }

        // Unless asked for explicitly, a run without the library stays quiet.
        guard enabled == true || Self.containsImages(exportDirectory) else {
            if let testError { throw testError }
            return
        }
        do {
            try await uploadService.upload(
                directory: exportDirectory,
                options: SnapshotsUploadOptions(
                    set: set,
                    path: path,
                    selective: await skippedTests(),
                    failOnChanges: testError == nil,
                    buildSystem: .xcode
                )
            )
        } catch {
            guard testError != nil else { throw error }
            AlertController.current.warning(.alert("The snapshots couldn't be uploaded: \(error.localizedDescription)"))
        }
        if let testError { throw testError }
    }

    private func isEnabled(_ enabled: Bool?, path: AbsolutePath) async -> Bool {
        if let enabled { return enabled }
        let environment = Environment.current
        // A caller exporting the images itself, such as for another service, keeps them.
        guard environment.isCI, environment.variables[Self.exportDirectoryVariable] == nil else { return false }
        return (try? await configLoader.loadConfig(path: path))?.fullHandle != nil
    }

    private static func containsImages(_ directory: AbsolutePath) -> Bool {
        FileManager.default.enumerator(at: directory.url, includingPropertiesForKeys: nil)?
            .contains { ($0 as? URL)?.pathExtension.lowercased() == "png" } ?? false
    }
}
