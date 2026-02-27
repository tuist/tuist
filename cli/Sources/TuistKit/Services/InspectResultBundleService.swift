import FileSystem
import Foundation
import Mockable
import Path
import TuistAutomation
import TuistCI
import TuistConfig
import TuistCore
import TuistEnvironment
import TuistGit
import TuistLoader
import TuistLogging
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXcodeProjectOrWorkspacePathLocator
import TuistXCResultService

public enum InspectResultBundleServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case missingInvocationRecord

    public var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        case .missingInvocationRecord:
            return "Failed to parse the test result bundle"
        }
    }
}

@Mockable
public protocol InspectResultBundleServicing {
    func inspectResultBundle(
        resultBundlePath: AbsolutePath,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist
    ) async throws -> Components.Schemas.RunsTest
}

public struct InspectResultBundleService: InspectResultBundleServicing {
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let createTestService: CreateTestServicing
    private let createCrashReportService: CreateCrashReportServicing
    private let createTestCaseRunAttachmentService: CreateTestCaseRunAttachmentServicing
    private let xcResultService: XCResultServicing
    private let dateService: DateServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let ciController: CIControlling
    private let xcodeBuildController: XcodeBuildControlling
    private let rootDirectoryLocator: RootDirectoryLocating
    private let xcActivityLogController: XCActivityLogControlling
    private let fileSystem: FileSysteming

    public init(
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        createTestService: CreateTestServicing = CreateTestService(),
        createCrashReportService: CreateCrashReportServicing = CreateCrashReportService(),
        createTestCaseRunAttachmentService: CreateTestCaseRunAttachmentServicing = CreateTestCaseRunAttachmentService(),
        xcResultService: XCResultServicing = XCResultService(),
        dateService: DateServicing = DateService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController(),
        ciController: CIControlling = CIController(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.machineEnvironment = machineEnvironment
        self.createTestService = createTestService
        self.createCrashReportService = createCrashReportService
        self.createTestCaseRunAttachmentService = createTestCaseRunAttachmentService
        self.xcResultService = xcResultService
        self.dateService = dateService
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.ciController = ciController
        self.xcodeBuildController = xcodeBuildController
        self.rootDirectoryLocator = rootDirectoryLocator
        self.xcActivityLogController = xcActivityLogController
        self.fileSystem = fileSystem
    }

    public func inspectResultBundle(
        resultBundlePath: AbsolutePath,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist
    ) async throws -> Components.Schemas.RunsTest {
        let rootDirectory = try await rootDirectory()
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let gitInfoDirectory = rootDirectory ?? currentWorkingDirectory

        guard let testSummary = try await xcResultService.parse(path: resultBundlePath, rootDirectory: rootDirectory) else {
            throw InspectResultBundleServiceError.missingInvocationRecord
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else {
            throw InspectResultBundleServiceError.missingFullHandle
        }

        var buildRunId: String?
        if let projectDerivedDataDirectory,
           let mostRecentActivityLogFile = try await xcActivityLogController.mostRecentActivityLogFile(
               projectDerivedDataDirectory: projectDerivedDataDirectory
           )
        {
            buildRunId = mostRecentActivityLogFile.path.basenameWithoutExt
        }

        let gitInfo = try gitController.gitInfo(workingDirectory: gitInfoDirectory)
        let ciInfo = ciController.ciInfo()
        let test = try await createTestService.createTest(
            fullHandle: fullHandle,
            serverURL: serverURL,
            testSummary: testSummary,
            buildRunId: buildRunId,
            gitBranch: gitInfo.branch,
            gitCommitSHA: gitInfo.sha,
            gitRef: gitInfo.ref,
            gitRemoteURLOrigin: gitInfo.remoteURLOrigin,
            isCI: Environment.current.isCI,
            modelIdentifier: machineEnvironment.modelIdentifier(),
            macOSVersion: machineEnvironment.macOSVersion,
            xcodeVersion: try await xcodeBuildController.version()?.description,
            ciRunId: ciInfo?.runId,
            ciProjectHandle: ciInfo?.projectHandle,
            ciHost: ciInfo?.host,
            ciProvider: ciInfo?.provider
        )

        let testCaseRunIdsByIdentity = testCaseRunIdsByIdentity(testCaseRuns: test.test_case_runs)

        await testSummary.testCases.forEach(context: .concurrent) { testCase in
            await uploadCrashReport(
                for: testCase,
                testRunId: test.id,
                fullHandle: fullHandle,
                serverURL: serverURL,
                testCaseRunIdsByIdentity: testCaseRunIdsByIdentity
            )
        }

        await RunMetadataStorage.current.update(testRunId: test.id)

        return test
    }

    private func uploadCrashReport(
        for testCase: TestCase,
        testRunId _: String,
        fullHandle: String,
        serverURL: URL,
        testCaseRunIdsByIdentity: [String: String]
    ) async {
        guard let crashReport = testCase.crashReport else { return }

        let identityKey = testCaseRunIdentityKey(
            moduleName: testCase.module ?? "",
            suiteName: testCase.testSuite ?? "",
            name: testCase.name
        )
        guard let testCaseRunId = testCaseRunIdsByIdentity[identityKey] else { return }

        let fileName = crashReport.filePath.basename

        do {
            let testCaseRunAttachmentId = try await createTestCaseRunAttachmentService.createAttachment(
                fullHandle: fullHandle,
                serverURL: serverURL,
                testCaseRunId: testCaseRunId,
                fileName: fileName,
                filePath: crashReport.filePath
            )
            try await createCrashReportService.createCrashReport(
                fullHandle: fullHandle,
                serverURL: serverURL,
                crashReport: crashReport,
                testCaseRunId: testCaseRunId,
                testCaseRunAttachmentId: testCaseRunAttachmentId
            )
            try await fileSystem.remove(crashReport.filePath)
        } catch {
            Logger.current
                .warning("Failed to upload crash report for \(fileName): \(error.localizedDescription)")
        }
    }

    private func testCaseRunIdsByIdentity(
        testCaseRuns: [Components.Schemas.RunsTest.test_case_runsPayloadPayload]
    ) -> [String: String] {
        testCaseRuns.reduce(into: [:]) { result, run in
            let key = testCaseRunIdentityKey(moduleName: run.module_name, suiteName: run.suite_name, name: run.name)
            result[key] = run.id
        }
    }

    private func testCaseRunIdentityKey(moduleName: String, suiteName: String, name: String) -> String {
        if suiteName.isEmpty {
            return "\(moduleName)/\(name)"
        } else {
            return "\(moduleName)/\(suiteName)/\(name)"
        }
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
}
