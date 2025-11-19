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

    init(
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        xcResultService: XCResultServicing = XCResultService(),
        xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating = XcodeProjectOrWorkspacePathLocator(),
        inspectResultBundleService: InspectResultBundleServicing = InspectResultBundleService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.xcResultService = xcResultService
        self.xcodeProjectOrWorkspacePathLocator = xcodeProjectOrWorkspacePathLocator
        self.inspectResultBundleService = inspectResultBundleService
        self.configLoader = configLoader
    }

    func run(
        path: String?,
        derivedDataPath: String? = nil,
        resultBundlePath: String? = nil
    ) async throws {
        let basePath = try await self.path(path)

        let resolvedResultBundlePath = try await resolveResultBundlePath(
            resultBundlePath: resultBundlePath,
            basePath: basePath,
            derivedDataPath: derivedDataPath
        )

        let config = try await configLoader.loadConfig(path: basePath)
        let test = try await inspectResultBundleService.inspectResultBundle(
            resultBundlePath: resolvedResultBundlePath,
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
    ) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()

        if let resultBundlePath {
            return try AbsolutePath(
                validating: resultBundlePath,
                relativeTo: currentWorkingDirectory
            )
        }

        let projectPath = try await xcodeProjectOrWorkspacePathLocator.locate(from: basePath)
        var projectDerivedDataDirectory: AbsolutePath! = try derivedDataPath.map { try AbsolutePath(
            validating: $0,
            relativeTo: currentWorkingDirectory
        ) }
        if projectDerivedDataDirectory == nil {
            projectDerivedDataDirectory = try await derivedDataLocator.locate(for: projectPath)
        }

        let mostRecentXCResultFile = try await xcResultService
            .mostRecentXCResultFile(projectDerivedDataDirectory: projectDerivedDataDirectory)
        guard let xcResultFile = mostRecentXCResultFile else {
            throw InspectTestCommandServiceError.mostRecentResultBundleNotFound(projectDerivedDataDirectory)
        }
        return AbsolutePath(xcResultFile.url.path)
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
