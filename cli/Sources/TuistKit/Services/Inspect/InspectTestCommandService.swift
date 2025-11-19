import FileSystem
import Foundation
import Path
import TuistAutomation
import TuistCore
import TuistGit
import TuistLoader
import TuistProcess
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXcodeProjectOrWorkspacePathLocator
import TuistXCResultService

enum InspectTestCommandServiceError: Equatable, LocalizedError {
    case executablePathMissing
    case mostRecentActivityLogNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case .executablePathMissing:
            return "We couldn't find tuist's executable path to run inspect test in a background."
        case let .mostRecentActivityLogNotFound(projectPath):
            return
                "We couldn't find the most recent activity log from the project at \(projectPath.pathString)"
        }
    }
}

struct InspectTestCommandService {
    private let derivedDataLocator: DerivedDataLocating
    private let fileSystem: FileSysteming
    private let xcResultService: XCResultServicing
    private let rootDirectoryLocator: RootDirectoryLocating
    private let xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating
    private let inspectResultBundleService: InspectResultBundleServicing
    private let gitController: GitControlling
    private let configLoader: ConfigLoading

    init(
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        xcResultService: XCResultServicing = XCResultService(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating = XcodeProjectOrWorkspacePathLocator(),
        inspectResultBundleService: InspectResultBundleServicing = InspectResultBundleService(),
        gitController: GitControlling = GitController(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.xcResultService = xcResultService
        self.rootDirectoryLocator = rootDirectoryLocator
        self.xcodeProjectOrWorkspacePathLocator = xcodeProjectOrWorkspacePathLocator
        self.inspectResultBundleService = inspectResultBundleService
        self.gitController = gitController
        self.configLoader = configLoader
    }

    func run(
        path: String?,
        derivedDataPath: String? = nil
    ) async throws {
        let basePath = try await self.path(path)
        let projectPath = try await xcodeProjectOrWorkspacePathLocator.locate(from: basePath)
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        var projectDerivedDataDirectory: AbsolutePath! = try derivedDataPath.map { try AbsolutePath(
            validating: $0,
            relativeTo: currentWorkingDirectory
        ) }
        if projectDerivedDataDirectory == nil {
            projectDerivedDataDirectory = try await derivedDataLocator.locate(for: projectPath)
        }

        guard let rootDirectory = try await rootDirectory() else {
            fatalError()
        }
        let mostRecentXCResultFile = try await xcResultService
            .mostRecentXCResultFile(projectDerivedDataDirectory: projectDerivedDataDirectory)
        guard let xcResultFile = mostRecentXCResultFile else {
            fatalError()
        }

        let config = try await configLoader.loadConfig(path: basePath)
        let resultBundlePath = AbsolutePath(xcResultFile.url.path)
        let test = try await inspectResultBundleService.inspectResultBundle(
            resultBundlePath: resultBundlePath,
            rootDirectory: rootDirectory,
            config: config
        )

        AlertController.current.success(
            .alert("View the analyzed test at \(test.url)")
        )
    }

    private func rootDirectory() async throws -> AbsolutePath? {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let workingDirectory = Environment.current.workspacePath ?? currentWorkingDirectory
        if gitController.isInGitRepository(workingDirectory: workingDirectory) {
            return try gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
        } else {
            return try await rootDirectoryLocator.locate(from: workingDirectory)
        }
    }

    private func path(_ path: String?) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        if let path {
            return try AbsolutePath(
                validating: path, relativeTo: currentWorkingDirectory
            )
        } else {
            return currentWorkingDirectory
        }
    }
}
