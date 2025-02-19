import Foundation
import TuistCore
import TuistAutomation
import TuistSupport
import TuistServer
import TuistLoader
import FileSystem
import Path
import XCLogParser

enum InspectBuildServiceError: LocalizedError {
    case projectNotFound(AbsolutePath)
    
    var errorDescription: String?
}

struct InspectBuildService {
    private let environment: Environmenting
    private let derivedDataLocator: DerivedDataLocating
    private let fileSystem: FileSysteming
    private let ciChecker: CIChecking
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let xcodeBuildController: XcodeBuildControlling
    private let createBuildService: CreateBuildServicing
    
    init(
        environment: Environmenting = Environment.shared,
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        ciChecker: CIChecking = CIChecker(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        createBuildService: CreateBuildServicing = CreateBuildService()
    ) {
        self.environment = environment
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.ciChecker = ciChecker
        self.machineEnvironment = machineEnvironment
        self.xcodeBuildController = xcodeBuildController
        self.createBuildService = createBuildService
    }
    
    func run() async throws {
        let workspacePath = environment.workspacePath!
        let config = try await ConfigLoader(warningController: WarningController.shared)
            .loadConfig(path: workspacePath)
        let buildLogsPath = try derivedDataLocator.locate(for: workspacePath.parentDirectory)
            .appending(components: "Logs", "Build")
        let plist: LogStoreManifest = try await fileSystem.readPlistFile(at: buildLogsPath.appending(component: "LogStoreManifest.plist"))
        let latestLog = plist.logs.values.sorted(by: { $0.timeStoppedRecording > $1.timeStoppedRecording }).first!
        let logPath = buildLogsPath.appending(component: latestLog.fileName)
        let activityLog = try ActivityParser().parseActivityLogInURL(
            logPath.url,
            redacted: false,
            withoutBuildSpecificInformation: false
        )
        try await createBuildService.createBuild(
            fullHandle: config.fullHandle!,
            serverURL: config.url,
            id: activityLog.mainSection.uniqueIdentifier,
            duration: Int(activityLog.mainSection.timeStoppedRecording * 1000) - Int(activityLog.mainSection.timeStartedRecording * 1000),
            isCI: ciChecker.isCI(),
            modelIdentifier: machineEnvironment.modelIdentifier(),
            macOSVersion: machineEnvironment.macOSVersion,
            scheme: environment.schemeName,
            xcodeVersion: try await xcodeBuildController.version()?.description
        )
    }
    
    private func projectPath(_ path: String?) async throws -> AbsolutePath {
        if let workspacePath = environment.workspacePath {
            if workspacePath.extension == "xcodeproj" {
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
            return fileSystem.glob(
                directory: path,
                include: ["*.xcodeproj"]
            )
            .collect()
            
        }
    }
}

fileprivate struct ActivityLog: Codable {
    let fileName: String
    let timeStartedRecording: Double
    let timeStoppedRecording: Double
}

fileprivate struct LogStoreManifest: Codable {
    let logs: [String: ActivityLog]
}
