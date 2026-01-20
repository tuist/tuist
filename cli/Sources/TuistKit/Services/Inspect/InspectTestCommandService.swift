import FileSystem
import Foundation
import Path
import TuistAutomation
import TuistCore
import TuistLoader
import TuistProcess
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXcodeProjectOrWorkspacePathLocator
import TuistXCResultService

enum InspectTestCommandServiceError: Equatable, LocalizedError {
    case executablePathMissing
    case mostRecentActivityLogNotFound(AbsolutePath)
    case mostRecentResultBundleNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case .executablePathMissing:
            return "We couldn't find tuist's executable path to run inspect test in a background."
        case let .mostRecentActivityLogNotFound(projectPath):
            return
                "We couldn't find the most recent activity log from the project at \(projectPath.pathString)"
        case let .mostRecentResultBundleNotFound(derivedDataPath):
            return
                "We couldn't find the most recent result bundle in the derived data directory at \(derivedDataPath.pathString)"
        }
    }
}

struct InspectTestCommandService {
    private let derivedDataLocator: DerivedDataLocating
    private let fileSystem: FileSysteming
    private let xcResultService: XCResultServicing
    private let xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating
    private let inspectResultBundleService: InspectResultBundleServicing
    private let configLoader: ConfigLoading
    private let backgroundProcessRunner: BackgroundProcessRunning

    init(
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        xcResultService: XCResultServicing = XCResultService(),
        xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating = XcodeProjectOrWorkspacePathLocator(),
        inspectResultBundleService: InspectResultBundleServicing = InspectResultBundleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner()
    ) {
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.xcResultService = xcResultService
        self.xcodeProjectOrWorkspacePathLocator = xcodeProjectOrWorkspacePathLocator
        self.inspectResultBundleService = inspectResultBundleService
        self.configLoader = configLoader
        self.backgroundProcessRunner = backgroundProcessRunner
    }

    func run(
        path: String?,
        derivedDataPath: String? = nil,
        resultBundlePath: String? = nil
    ) async throws {
        if Environment.current.variables["TUIST_INSPECT_TEST_WAIT"] != "YES",
           Environment.current.workspacePath != nil
        {
            guard let executablePath = Environment.current.currentExecutablePath() else {
                throw InspectTestCommandServiceError.executablePathMissing
            }
            var environment = Environment.current.variables
            environment["TUIST_INSPECT_TEST_WAIT"] = "YES"
            try backgroundProcessRunner.runInBackground(
                [executablePath.pathString, "inspect", "test"],
                environment: environment
            )
            return
        }

        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let (resolvedResultBundlePath, projectDerivedDataDirectory) = try await resolveResultBundlePath(
            resultBundlePath: resultBundlePath,
            basePath: path,
            derivedDataPath: derivedDataPath
        )

        let projectPath = try await xcodeProjectOrWorkspacePathLocator.locate(from: path)
        let config = try await configLoader.loadConfig(path: projectPath)
        let test = try await inspectResultBundleService.inspectResultBundle(
            resultBundlePath: resolvedResultBundlePath,
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            config: config
        )

        AlertController.current.success(
            .alert("View the analyzed test at \(test.url)")
        )
    }

    private func resolveResultBundlePath(
        resultBundlePath: String?,
        basePath: AbsolutePath,
        derivedDataPath: String?
    ) async throws -> (resultBundlePath: AbsolutePath, derivedDataDirectory: AbsolutePath?) {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()

        if let resultBundlePath {
            let derivedDataDirectory: AbsolutePath? = if let derivedDataPath {
                try AbsolutePath(
                    validating: derivedDataPath,
                    relativeTo: currentWorkingDirectory
                )
            } else {
                nil
            }
            return (
                try AbsolutePath(
                    validating: resultBundlePath,
                    relativeTo: currentWorkingDirectory
                ),
                derivedDataDirectory
            )
        }

        let projectPath = try await xcodeProjectOrWorkspacePathLocator.locate(from: basePath)
        let projectDerivedDataDirectory = if let derivedDataPath {
            try AbsolutePath(
                validating: derivedDataPath,
                relativeTo: currentWorkingDirectory
            )
        } else {
            try await derivedDataLocator.locate(for: projectPath)
        }

        guard let xcResultPath = try await xcResultService
            .mostRecentXCResultFile(projectDerivedDataDirectory: projectDerivedDataDirectory)
        else {
            throw InspectTestCommandServiceError.mostRecentResultBundleNotFound(projectDerivedDataDirectory)
        }
        return (xcResultPath, projectDerivedDataDirectory)
    }
}
