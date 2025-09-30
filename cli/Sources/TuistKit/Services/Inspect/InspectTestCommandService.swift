import FileSystem
import Foundation
import Path
import TuistAutomation
import TuistCore
import TuistGit
import TuistLoader
import TuistProcess
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXcodeProjectOrWorkspacePathLocator
import TuistXCResultService

enum InspectTestCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case executablePathMissing
    case mostRecentActivityLogNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
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
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let createTestService: CreateTestServicing
    private let configLoader: ConfigLoading
    private let xcResultService: XCResultServicing
    private let backgroundProcessRunner: BackgroundProcessRunning
    private let dateService: DateServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating
    private let xcodeBuildController: XcodeBuildControlling
    

    init(
        derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
        fileSystem: FileSysteming = FileSystem(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        createTestService: CreateTestServicing = CreateTestService(),
        configLoader: ConfigLoading = ConfigLoader(),
        xcResultService: XCResultServicing = XCResultService(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
        dateService: DateServicing = DateService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController(),
        xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating = XcodeProjectOrWorkspacePathLocator(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController()
    ) {
        self.derivedDataLocator = derivedDataLocator
        self.fileSystem = fileSystem
        self.machineEnvironment = machineEnvironment
        self.createTestService = createTestService
        self.configLoader = configLoader
        self.xcResultService = xcResultService
        self.backgroundProcessRunner = backgroundProcessRunner
        self.dateService = dateService
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.xcodeProjectOrWorkspacePathLocator = xcodeProjectOrWorkspacePathLocator
        self.xcodeBuildController = xcodeBuildController
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

        let mostRecentXCResultFile = try await xcResultService.mostRecentXCResultFile(projectDerivedDataDirectory: projectDerivedDataDirectory)
        guard let xcResultFile = mostRecentXCResultFile,
              let invocationRecord = xcResultService.parse(path: AbsolutePath(xcResultFile.url.path)) else { 
            fatalError() 
        }
        
        // Set the test run ID using the xcresult basename (same pattern as buildRunId)
        let testRunId = AbsolutePath(xcResultFile.url.path).basenameWithoutExt
        await RunMetadataStorage.current.update(testRunId: testRunId)
        
        let testSummary = xcResultService.testSummary(invocationRecord: invocationRecord)
        
        print("Test Summary:")
        print("Status: \(testSummary.status)")
        print("Duration: \(testSummary.duration ?? 0)ms")
        print("Test Cases: \(testSummary.testCases.count)")
        
        for testCase in testSummary.testCases {
            print("- \(testCase.name) (\(testCase.module ?? "unknown")) - \(testCase.status) - \(testCase.duration ?? 0)ms")
        }
        
        try await createTest(
            testSummary: testSummary,
            projectPath: projectPath,
            testRunId: testRunId
        )
    }

    private func createTest(
        testSummary: TestSummary,
        projectPath: AbsolutePath,
        testRunId: String
    ) async throws {
        let config =
            try await configLoader
                .loadConfig(path: projectPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        guard let fullHandle = config.fullHandle else {
            throw InspectTestCommandServiceError.missingFullHandle
        }

        let gitInfo = try gitController.gitInfo(workingDirectory: projectPath)
        let test = try await createTestService.createTest(
            fullHandle: fullHandle,
            serverURL: serverURL,
            id: UUID().uuidString,
            testSummary: testSummary,
            gitBranch: gitInfo.branch,
            gitCommitSHA: gitInfo.sha,
            gitRef: gitInfo.ref,
            gitRemoteURLOrigin: gitInfo.remoteURLOrigin,
            isCI: Environment.current.isCI,
            modelIdentifier: machineEnvironment.modelIdentifier(),
            macOSVersion: machineEnvironment.macOSVersion,
            xcodeVersion: try await xcodeBuildController.version()?.description
        )
        AlertController.current.success(
            .alert("View the analyzed test at \(test.url)")
        )
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
