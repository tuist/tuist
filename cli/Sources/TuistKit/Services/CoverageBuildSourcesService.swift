import FileSystem
import Foundation
import Path
import TuistAlert
import TuistConfig
import TuistCore
import TuistEnvironment
import TuistGit
import TuistRootDirectoryLocator
import XCResultParser

/// Records the build's checkout and the targets it builds, for this process's test run and,
/// through a `.xctestproducts` bundle, for a run that uses the products elsewhere (a shard,
/// another CI job, another checkout): the coverage paths the compiler embedded resolve against
/// that checkout, to the blobs that were compiled and the targets that compiled them.
struct CoverageBuildSourcesService {
    private let fileSystem: FileSysteming
    private let gitController: GitControlling
    private let rootDirectoryLocator: RootDirectoryLocating

    init(
        fileSystem: FileSysteming = FileSystem(),
        gitController: GitControlling = GitController(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.fileSystem = fileSystem
        self.gitController = gitController
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    /// Records the build's checkout and the tested schemes' targets for this process's run.
    /// Best effort: coverage only enriches a run, so a failure costs the test run its coverage
    /// attribution and never the build.
    func record(config: Tuist, targets: [CoverageBuildTarget]) async {
        guard UploadResultBundleService.uploadsCoverage(config: config) else { return }
        do {
            await RunMetadataStorage.current.update(coverageBuildSources: try await sources(targets: targets))
        } catch {
            AlertController.current.warning(
                .alert("Failed to record the build's sources for code coverage: \(error.localizedDescription)")
            )
        }
    }

    /// Writes what `record` recorded, or the checkout alone when nothing was, into the test
    /// products for a run elsewhere. Best effort, as `record` is.
    func write(to testProductsPath: AbsolutePath, config: Tuist) async {
        let sourcesPath = testProductsPath.appending(component: CoverageBuildSources.fileName)
        do {
            guard UploadResultBundleService.uploadsCoverage(config: config) else {
                // A bundle built earlier with coverage on must not describe this build.
                if try await fileSystem.exists(sourcesPath) { try await fileSystem.remove(sourcesPath) }
                return
            }
            var sources = await RunMetadataStorage.current.coverageBuildSources
            if sources == nil { sources = try await self.sources(targets: []) }
            guard let sources else { return }
            try await fileSystem.writeAsJSON(sources, at: sourcesPath)
        } catch {
            AlertController.current.warning(
                .alert("Failed to record the build's sources for code coverage: \(error.localizedDescription)")
            )
        }
    }

    /// Nil outside any project. The targets' files, absolute from the graph, end up relative to
    /// the root, as the blob ids are keyed.
    private func sources(targets: [CoverageBuildTarget]) async throws -> CoverageBuildSources? {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let workingDirectory = Environment.current.workspacePath ?? currentWorkingDirectory
        let root: AbsolutePath
        let files: [String: String]
        if await gitController.isInGitRepository(workingDirectory: workingDirectory) {
            root = try await gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
            files = try await gitController.sourceFileBlobIds(
                workingDirectory: root,
                pathExtensions: UploadResultBundleService.coverageSourceExtensions
            )
        } else if let located = try await rootDirectoryLocator.locate(from: workingDirectory) {
            root = located
            files = [:]
        } else {
            return nil
        }
        let rootDirectories = UploadResultBundleService.rootSpellings(of: root, coveredFilePaths: [])
        return CoverageBuildSources(
            rootDirectories: rootDirectories,
            files: files,
            targets: targets.map { target in
                CoverageBuildTarget(
                    name: target.name,
                    isTest: target.isTest,
                    files: target.files
                        .map { XcodeCoverageParser.relativize($0, to: XcodeCoverageParser.roots(rootDirectories)) },
                    binaries: target.binaries
                )
            }
        )
    }
}
