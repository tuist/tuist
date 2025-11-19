import Foundation
import Path
import TuistAutomation
import TuistCore
import TuistGit
import TuistLoader
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXCResultService

enum InspectResultBundleServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case missingInvocationRecord

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        case .missingInvocationRecord:
            return "Failed to parse the test result bundle"
        }
    }
}

protocol InspectResultBundleServicing {
    func inspectResultBundle(
        resultBundlePath: AbsolutePath,
        rootDirectory: AbsolutePath,
        config: Tuist
    ) async throws -> Components.Schemas.RunsTest
}

struct InspectResultBundleService: InspectResultBundleServicing {
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let createTestService: CreateTestServicing
    private let xcResultService: XCResultServicing
    private let dateService: DateServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let xcodeBuildController: XcodeBuildControlling

    init(
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        createTestService: CreateTestServicing = CreateTestService(),
        xcResultService: XCResultServicing = XCResultService(),
        dateService: DateServicing = DateService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController()
    ) {
        self.machineEnvironment = machineEnvironment
        self.createTestService = createTestService
        self.xcResultService = xcResultService
        self.dateService = dateService
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.xcodeBuildController = xcodeBuildController
    }

    func inspectResultBundle(
        resultBundlePath: AbsolutePath,
        rootDirectory: AbsolutePath,
        config: Tuist
    ) async throws -> Components.Schemas.RunsTest {
        guard let invocationRecord = xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory) else {
            throw InspectResultBundleServiceError.missingInvocationRecord
        }

        let testRunId = UUID().uuidString
        await RunMetadataStorage.current.update(testRunId: testRunId)

        let testSummary = xcResultService.testSummary(invocationRecord: invocationRecord)

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else {
            throw InspectResultBundleServiceError.missingFullHandle
        }

        let gitInfo = try gitController.gitInfo(workingDirectory: rootDirectory)
        let test = try! await createTestService.createTest(
            fullHandle: fullHandle,
            serverURL: serverURL,
            id: testRunId,
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

        return test
    }
}
