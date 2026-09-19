import FileSystem
import Foundation
import Path
import TuistAlert
import TuistConfig
import TuistCore
import TuistEnvironment
import TuistGit
import TuistRootDirectoryLocator

/// Records the build's checkout into a `.xctestproducts` bundle, so a test run that uses the
/// products elsewhere (a shard, another CI job, another checkout) can resolve the coverage paths
/// the compiler embedded and attribute them to the blobs that were compiled.
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

    /// Best effort: coverage only enriches a run, so a failure costs the test run its coverage
    /// attribution and never the build.
    func write(to testProductsPath: AbsolutePath, config: Tuist) async {
        let sourcesPath = testProductsPath.appending(component: CoverageBuildSources.fileName)
        do {
            guard UploadResultBundleService.uploadsCoverage(config: config) else {
                // A bundle built earlier with coverage on must not describe this build.
                if try await fileSystem.exists(sourcesPath) { try await fileSystem.remove(sourcesPath) }
                return
            }
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let workingDirectory = Environment.current.workspacePath ?? currentWorkingDirectory
            let sources: CoverageBuildSources
            if await gitController.isInGitRepository(workingDirectory: workingDirectory) {
                let root = try await gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
                sources = CoverageBuildSources(
                    rootDirectories: UploadResultBundleService.rootSpellings(of: root, coveredFilePaths: []),
                    files: try await gitController.sourceFileBlobIds(
                        workingDirectory: root,
                        pathExtensions: UploadResultBundleService.coverageSourceExtensions
                    )
                )
            } else if let root = try await rootDirectoryLocator.locate(from: workingDirectory) {
                sources = CoverageBuildSources(
                    rootDirectories: UploadResultBundleService.rootSpellings(of: root, coveredFilePaths: []),
                    files: [:]
                )
            } else {
                return
            }
            try await fileSystem.writeAsJSON(sources, at: sourcesPath)
        } catch {
            AlertController.current.warning(
                .alert("Failed to record the build's sources for code coverage: \(error.localizedDescription)")
            )
        }
    }
}
