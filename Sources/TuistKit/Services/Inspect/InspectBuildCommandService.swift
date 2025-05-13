import FileSystem
import Foundation
import Path
import ServiceContextModule
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

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
            return "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        case .executablePathMissing:
            return "We couldn't find tuist's executable path to run inspect build in a background."
        case let .mostRecentActivityLogNotFound(projectPath):
            return "We couldn't find the most recent activity log from the project at \(projectPath.pathString)"
        }
    }
}

struct InspectBuildCommandService {
    private let environment: Environmenting
    private let derivedDataLocator: DerivedDataLocating
    private let fileSystem: FileSysteming
    private let ciChecker: CIChecking
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let xcodeBuildController: XcodeBuildControlling
    private let createBuildService: CreateBuildServicing
    private let configLoader: ConfigLoading
    private let xcActivityLogController: XCActivityLogControlling
    private let backgroundProcessRunner: BackgroundProcessRunning
    private let dateService: DateServicing
    private let serverURLService: ServerURLServicing

    init(
        environment: Environmenting = Environment.shared,
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        ciChecker: CIChecking = CIChecker(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        createBuildService: CreateBuildServicing = CreateBuildService(),
        configLoader: ConfigLoading = ConfigLoader(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
        dateService: DateServicing = DateService(),
        serverURLService: ServerURLServicing = ServerURLService()
    ) {
        self.environment = environment
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.ciChecker = ciChecker
        self.machineEnvironment = machineEnvironment
        self.xcodeBuildController = xcodeBuildController
        self.createBuildService = createBuildService
        self.configLoader = configLoader
        self.xcActivityLogController = xcActivityLogController
        self.backgroundProcessRunner = backgroundProcessRunner
        self.dateService = dateService
        self.serverURLService = serverURLService
    }

    func run(
        path: String?
    ) async throws {
        let referenceDate = dateService.now()
        guard let executablePath = Bundle.main.executablePath else { throw InspectBuildCommandServiceError.executablePathMissing }

        if environment.tuistVariables["TUIST_INSPECT_BUILD_WAIT"] != "YES",
           environment.workspacePath != nil
        {
            var environment = ProcessInfo.processInfo.environment
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
        let projectDerivedDataDirectory = try derivedDataLocator.locate(for: projectPath)
        guard let mostRecentActivityLogPath = try await xcActivityLogController.mostRecentActivityLogPath(
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            after: referenceDate
        ) else {
            throw InspectBuildCommandServiceError.mostRecentActivityLogNotFound(projectPath)
        }
        let xcactivityLog = try xcActivityLogController.parse(mostRecentActivityLogPath)
        try await createBuild(
            for: xcactivityLog,
            projectPath: projectPath
        )
    }

    private func createBuild(
        for xcactivityLog: XCActivityLog,
        projectPath: AbsolutePath
    ) async throws {
        let config = try await configLoader
            .loadConfig(path: projectPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)
        guard let fullHandle = config.fullHandle else { throw InspectBuildCommandServiceError.missingFullHandle }
        try await createBuildService.createBuild(
            fullHandle: fullHandle,
            serverURL: serverURL,
            id: xcactivityLog.mainSection.uniqueIdentifier,
            duration: Int(xcactivityLog.mainSection.timeStoppedRecording * 1000) -
                Int(xcactivityLog.mainSection.timeStartedRecording * 1000),
            isCI: ciChecker.isCI(),
            modelIdentifier: machineEnvironment.modelIdentifier(),
            macOSVersion: machineEnvironment.macOSVersion,
            scheme: environment.schemeName,
            xcodeVersion: try await xcodeBuildController.version()?.description,
            status: xcactivityLog.buildStep.errorCount == 0 ? .success : .failure
        )
        ServiceContext.current?.ui?.success(
            .alert(
                "Uploaded a build to the server."
            )
        )
    }

    private func projectPath(_ path: String?) async throws -> AbsolutePath {
        if let workspacePath = environment.workspacePath {
            if workspacePath.parentDirectory.extension == "xcodeproj" {
                return workspacePath.parentDirectory
            } else {
                return workspacePath
            }
        } else {
            let currentWorkingDirectory = try await fileSystem.currentWorkingDirectory()
            let basePath = if let path {
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
