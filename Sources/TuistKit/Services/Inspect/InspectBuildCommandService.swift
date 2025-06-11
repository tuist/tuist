import FileSystem
import Foundation
import Path
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistXCActivityLog

enum InspectBuildCommandServiceError: Equatable, LocalizedError {
    case projectNotFound(AbsolutePath)
    case missingFullHandle
    case executablePathMissing
    case mostRecentActivityLogNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .projectNotFound(path):
            return "No Xcode project found at \(path.pathString). Make sure it exists."
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        case .executablePathMissing:
            return "We couldn't find tuist's executable path to run inspect build in a background."
        case let .mostRecentActivityLogNotFound(projectPath):
            return
                "We couldn't find the most recent activity log from the project at \(projectPath.pathString)"
        }
    }
}

struct InspectBuildCommandService {
    private let derivedDataLocator: DerivedDataLocating
    private let fileSystem: FileSysteming
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let xcodeBuildController: XcodeBuildControlling
    private let createBuildService: CreateBuildServicing
    private let configLoader: ConfigLoading
    private let xcActivityLogController: XCActivityLogControlling
    private let backgroundProcessRunner: BackgroundProcessRunning
    private let dateService: DateServicing
    private let serverURLService: ServerURLServicing
    private let gitController: GitControlling

    init(
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        createBuildService: CreateBuildServicing = CreateBuildService(),
        configLoader: ConfigLoading = ConfigLoader(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
        dateService: DateServicing = DateService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        gitController: GitControlling = GitController()
    ) {
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.machineEnvironment = machineEnvironment
        self.xcodeBuildController = xcodeBuildController
        self.createBuildService = createBuildService
        self.configLoader = configLoader
        self.xcActivityLogController = xcActivityLogController
        self.backgroundProcessRunner = backgroundProcessRunner
        self.dateService = dateService
        self.serverURLService = serverURLService
        self.gitController = gitController
    }

    func run(
        path: String?,
        projectDerivedDataPath: String? = nil
    ) async throws {
        let referenceDate = dateService.now()
        guard let executablePath = Bundle.main.executablePath else {
            throw InspectBuildCommandServiceError.executablePathMissing
        }

        if Environment.current.variables["TUIST_INSPECT_BUILD_WAIT"] != "YES",
           Environment.current.workspacePath != nil
        {
            var environment = Environment.current.variables
            environment["TUIST_INSPECT_BUILD_WAIT"] = "YES"
            // We don't want to prolongue the build action for analytics reasons.
            // Additionally, the `.xcactivitylog` might not be immediately available.
            // To resolve both issues, we run the `inspect build` command again when run from a post action (recognized by the
            // presense of the `workspacePath` environment variable).
            // We pass the `TUIST_INSPECT_BUILD_WAIT` environment variable to the new process, so we do actually upload the build
            // analytics to the server.
            try backgroundProcessRunner.runInBackground(
                [executablePath, "inspect", "build"],
                environment: environment
            )
            return
        }
        let projectPath = try await projectPath(path)
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        var projectDerivedDataDirectory: AbsolutePath! = try projectDerivedDataPath.map { try AbsolutePath(
            validating: $0,
            relativeTo: currentWorkingDirectory
        ) }
        if projectDerivedDataDirectory == nil {
            projectDerivedDataDirectory = try await derivedDataLocator.locate(for: projectPath)
        }

        let mostRecentActivityLogPath = try await mostRecentActivityLogPath(
            projectPath: projectPath,
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            referenceDate: referenceDate
        )
        let xcactivityLog = try await xcActivityLogController.parse(mostRecentActivityLogPath)
        try await createBuild(
            for: xcactivityLog,
            projectPath: projectPath
        )
    }

    private func mostRecentActivityLogPath(
        projectPath: AbsolutePath,
        projectDerivedDataDirectory: AbsolutePath,
        referenceDate: Date
    ) async throws -> AbsolutePath {
        var mostRecentActivityLogPath: AbsolutePath!
        try await withTimeout(
            .seconds(1),
            onTimeout: {
                throw InspectBuildCommandServiceError.mostRecentActivityLogNotFound(projectPath)
            }
        ) {
            while true {
                mostRecentActivityLogPath = try await xcActivityLogController.mostRecentActivityLogPath(
                    projectDerivedDataDirectory: projectDerivedDataDirectory,
                    after: referenceDate
                )
                if mostRecentActivityLogPath != nil {
                    return
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
        return mostRecentActivityLogPath
    }

    private func createBuild(
        for xcactivityLog: XCActivityLog,
        projectPath: AbsolutePath
    ) async throws {
        let config =
            try await configLoader
                .loadConfig(path: projectPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)
        guard let fullHandle = config.fullHandle else {
            throw InspectBuildCommandServiceError.missingFullHandle
        }

        let gitInfo = gitController.gitInfo(workingDirectory: projectPath)
        let gitCommitSHA = gitInfo.sha
        let gitBranch = gitInfo.branch
        let build = try await createBuildService.createBuild(
            fullHandle: fullHandle,
            serverURL: serverURL,
            id: xcactivityLog.mainSection.uniqueIdentifier,
            category: xcactivityLog.category,
            duration: Int(xcactivityLog.mainSection.timeStoppedRecording * 1000)
                - Int(xcactivityLog.mainSection.timeStartedRecording * 1000),
            files: xcactivityLog.files,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            isCI: Environment.current.isCI,
            issues: xcactivityLog.issues,
            modelIdentifier: machineEnvironment.modelIdentifier(),
            macOSVersion: machineEnvironment.macOSVersion,
            scheme: Environment.current.schemeName,
            targets: xcactivityLog.targets,
            xcodeVersion: try await xcodeBuildController.version()?.description,
            status: xcactivityLog.buildStep.errorCount == 0 ? .success : .failure
        )
        AlertController.current.success(
            .alert("View the analyzed build at \(build.url.absoluteString)")
        )
    }

    private func projectPath(_ path: String?) async throws -> AbsolutePath {
        if let workspacePath = Environment.current.workspacePath {
            if workspacePath.parentDirectory.extension == "xcodeproj" {
                return workspacePath.parentDirectory
            } else {
                return workspacePath
            }
        } else {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let basePath =
                if let path {
                    try AbsolutePath(
                        validating: path,
                        relativeTo: currentWorkingDirectory
                    )
                } else {
                    currentWorkingDirectory
                }
            if let workspacePath = try await fileSystem.glob(
                directory: basePath,
                include: ["*.xcworkspace"]
            )
            .collect()
            .first {
                return workspacePath
            } else if let xcodeProjPath = try await fileSystem.glob(
                directory: basePath,
                include: ["*.xcodeproj"]
            )
            .collect()
            .first {
                return xcodeProjPath
            } else {
                throw InspectBuildCommandServiceError.projectNotFound(basePath)
            }
        }
    }
}
