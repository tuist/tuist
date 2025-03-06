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
    case noBuildLogFound(buildLogsPath: AbsolutePath, projectPath: AbsolutePath)
    case missingFullHandle
    case executablePathMissing

    var errorDescription: String? {
        switch self {
        case let .projectNotFound(path):
            return "No Xcode project found at \(path.pathString). Make sure it exists."
        case let .noBuildLogFound(buildLogsPath: buildLogsPath, projectPath: projectPath):
            return "No build logs for project \(projectPath.basename) found at \(buildLogsPath.pathString)."
        case .missingFullHandle:
            return "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        case .executablePathMissing:
            return "We couldn't find tuist's executable path to run inspect build in a background."
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
    private let xcactivityParser: XCActivityParsing
    private let backgroundProcessRunner: BackgroundProcessRunning
    private let dateService: DateServicing

    init(
        environment: Environmenting = Environment.shared,
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        ciChecker: CIChecking = CIChecker(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        createBuildService: CreateBuildServicing = CreateBuildService(),
        configLoader: ConfigLoading = ConfigLoader(),
        xcactivityParser: XCActivityParsing = XCActivityParser(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
        dateService: DateServicing = DateService()
    ) {
        self.environment = environment
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.ciChecker = ciChecker
        self.machineEnvironment = machineEnvironment
        self.xcodeBuildController = xcodeBuildController
        self.createBuildService = createBuildService
        self.configLoader = configLoader
        self.xcactivityParser = xcactivityParser
        self.backgroundProcessRunner = backgroundProcessRunner
        self.dateService = dateService
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
        let buildLogsPath = try derivedDataLocator.locate(for: projectPath)
            .appending(components: "Logs", "Build")
        let logManifestPlistPath = buildLogsPath.appending(component: "LogStoreManifest.plist")

        guard try await fileSystem.exists(logManifestPlistPath)
        else {
            throw InspectBuildCommandServiceError.noBuildLogFound(buildLogsPath: buildLogsPath, projectPath: projectPath)
        }
        let xcactivityLog = try await latestXCActivityLog(
            logManifestPlistPath: logManifestPlistPath,
            buildLogsPath: buildLogsPath,
            projectPath: projectPath,
            referenceDate: referenceDate
        )
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
        guard let fullHandle = config.fullHandle else { throw InspectBuildCommandServiceError.missingFullHandle }
        try await createBuildService.createBuild(
            fullHandle: fullHandle,
            serverURL: config.url,
            id: xcactivityLog.mainSection.uniqueIdentifier,
            duration: Int(xcactivityLog.mainSection.timeStoppedRecording * 1000) -
                Int(xcactivityLog.mainSection.timeStartedRecording * 1000),
            isCI: ciChecker.isCI(),
            modelIdentifier: machineEnvironment.modelIdentifier(),
            macOSVersion: machineEnvironment.macOSVersion,
            scheme: environment.schemeName,
            xcodeVersion: try await xcodeBuildController.version()?.description
        )
        ServiceContext.current?.ui?.success(
            .alert(
                "Uploaded a build to the server."
            )
        )
    }

    private func latestXCActivityLog(
        logManifestPlistPath: AbsolutePath,
        buildLogsPath: AbsolutePath,
        projectPath: AbsolutePath,
        referenceDate: Date
    ) async throws -> XCActivityLog {
        let plist: LogStoreManifest = try await fileSystem
            .readPlistFile(at: logManifestPlistPath)

        guard let latestLog = plist.logs.values.sorted(by: { $0.timeStoppedRecording > $1.timeStoppedRecording }).first,
              environment
              .workspacePath == nil ||
              (referenceDate.timeIntervalSinceReferenceDate - 10 ..< referenceDate.timeIntervalSinceReferenceDate + 10) ~=
              latestLog.timeStoppedRecording
        else {
            throw InspectBuildCommandServiceError.noBuildLogFound(buildLogsPath: buildLogsPath, projectPath: projectPath)
        }
        let logPath = buildLogsPath.appending(component: latestLog.fileName)
        return try xcactivityParser.parse(logPath)
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
            if let xcodeProjPath = try await fileSystem.glob(
                directory: basePath,
                include: ["*.xcodeproj"]
            )
            .collect()
            .first {
                return xcodeProjPath
            } else if let workspacePath = try await fileSystem.glob(
                directory: basePath,
                include: ["*.xcodeproj"]
            )
            .collect()
            .first {
                return workspacePath
            } else {
                throw InspectBuildCommandServiceError.projectNotFound(basePath)
            }
        }
    }
}
