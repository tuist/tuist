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
import XCResultParser

public enum UploadResultBundleServiceError: Equatable, LocalizedError {
    case missingFullHandle

    public var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        }
    }
}

@Mockable
public protocol UploadResultBundleServicing {
    func uploadTestSummary(
        testSummary: TestSummary,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        shardPlanId: String?,
        shardIndex: Int?
    ) async throws -> Components.Schemas.RunsTest

    func uploadResultBundle(
        resultBundlePath: AbsolutePath,
        config: Tuist,
        quarantinedTests: [TestIdentifier],
        buildRunId: String?,
        shardPlanId: String?,
        shardIndex: Int?
    ) async throws -> Components.Schemas.RunsTest
}

public struct UploadResultBundleService: UploadResultBundleServicing {
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let createTestService: CreateTestServicing
    private let createCrashReportService: CreateCrashReportServicing
    private let createTestCaseRunAttachmentService: CreateTestCaseRunAttachmentServicing
    private let dateService: DateServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let ciController: CIControlling
    private let xcodeBuildController: XcodeBuildControlling
    private let rootDirectoryLocator: RootDirectoryLocating
    private let xcActivityLogController: XCActivityLogControlling
    private let analyticsArtifactUploadService: AnalyticsArtifactUploadServicing
    private let fileSystem: FileSysteming

    public init(
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        createTestService: CreateTestServicing = CreateTestService(),
        createCrashReportService: CreateCrashReportServicing = CreateCrashReportService(),
        createTestCaseRunAttachmentService: CreateTestCaseRunAttachmentServicing = CreateTestCaseRunAttachmentService(),
        dateService: DateServicing = DateService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController(),
        ciController: CIControlling = CIController(),
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
        analyticsArtifactUploadService: AnalyticsArtifactUploadServicing = AnalyticsArtifactUploadService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.machineEnvironment = machineEnvironment
        self.createTestService = createTestService
        self.createCrashReportService = createCrashReportService
        self.createTestCaseRunAttachmentService = createTestCaseRunAttachmentService
        self.dateService = dateService
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.ciController = ciController
        self.xcodeBuildController = xcodeBuildController
        self.rootDirectoryLocator = rootDirectoryLocator
        self.xcActivityLogController = xcActivityLogController
        self.analyticsArtifactUploadService = analyticsArtifactUploadService
        self.fileSystem = fileSystem
    }

    public func uploadTestSummary(
        testSummary: TestSummary,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        shardPlanId: String? = nil,
        shardIndex: Int? = nil
    ) async throws -> Components.Schemas.RunsTest {
        let rootDirectory = try await rootDirectory()
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let gitInfoDirectory = rootDirectory ?? currentWorkingDirectory

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else {
            throw UploadResultBundleServiceError.missingFullHandle
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
            id: nil,
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
            ciProvider: ciInfo?.provider,
            shardPlanId: shardPlanId,
            shardIndex: shardIndex
        )

        let testCaseRunIdsByIdentity = testCaseRunIdsByIdentity(testCaseRuns: test.test_case_runs)

        await testSummary.testCases.forEach(context: .concurrent) { testCase in
            await uploadAttachments(
                for: testCase,
                fullHandle: fullHandle,
                serverURL: serverURL,
                testCaseRunIdsByIdentity: testCaseRunIdsByIdentity
            )
        }

        await RunMetadataStorage.current.update(testRunId: test.id)

        return test
    }

    public func uploadResultBundle(
        resultBundlePath: AbsolutePath,
        config: Tuist,
        quarantinedTests: [TestIdentifier] = [],
        buildRunId: String? = nil,
        shardPlanId: String? = nil,
        shardIndex: Int? = nil
    ) async throws -> Components.Schemas.RunsTest {
        guard let fullHandle = config.fullHandle else {
            throw UploadResultBundleServiceError.missingFullHandle
        }

        // xcodebuild creates result-bundle as a symlink to result-bundle.xcresult,
        // so we resolve it to ensure the archiver zips the actual directory.
        let resolvedResultBundlePath = try await fileSystem.resolveSymbolicLink(resultBundlePath)

        if !quarantinedTests.isEmpty {
            try await writeQuarantinedTests(quarantinedTests, to: resolvedResultBundlePath)
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let rootDirectory = try await rootDirectory()
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let gitInfoDirectory = rootDirectory ?? currentWorkingDirectory
        let gitInfo = try gitController.gitInfo(workingDirectory: gitInfoDirectory)
        let ciInfo = ciController.ciInfo()

        let testRunId = UUID().uuidString.lowercased()

        try await analyticsArtifactUploadService.uploadResultBundle(
            resolvedResultBundlePath,
            fullHandle: fullHandle,
            commandEventId: testRunId,
            serverURL: serverURL
        )

        let test = try await createTestService.createTest(
            fullHandle: fullHandle,
            serverURL: serverURL,
            id: testRunId,
            testSummary: TestSummary(
                testPlanName: nil,
                status: .processing,
                duration: 0,
                testModules: []
            ),
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
            ciProvider: ciInfo?.provider,
            shardPlanId: shardPlanId,
            shardIndex: shardIndex
        )

        return test
    }

    private func uploadAttachments(
        for testCase: TestCase,
        fullHandle: String,
        serverURL: URL,
        testCaseRunIdsByIdentity: [String: String]
    ) async {
        guard !testCase.attachments.isEmpty else { return }

        let identityKey = testCaseRunIdentityKey(
            moduleName: testCase.module ?? "",
            suiteName: testCase.testSuite ?? "",
            name: testCase.name
        )
        guard let testCaseRunId = testCaseRunIdsByIdentity[identityKey] else { return }

        await testCase.attachments.forEach(context: .concurrent) { attachment in
            do {
                let testCaseRunAttachmentId = try await createTestCaseRunAttachmentService.createAttachment(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    testCaseRunId: testCaseRunId,
                    fileName: attachment.fileName,
                    filePath: attachment.filePath,
                    repetitionNumber: attachment.repetitionNumber
                )
                if let crashReport = testCase.crashReport,
                   crashReport.filePath == attachment.filePath
                {
                    try await createCrashReportService.createCrashReport(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        crashReport: crashReport,
                        testCaseRunId: testCaseRunId,
                        testCaseRunAttachmentId: testCaseRunAttachmentId
                    )
                }
                try await fileSystem.remove(attachment.filePath)
            } catch {
                Logger.current
                    .warning("Failed to upload attachment \(attachment.fileName): \(error.localizedDescription)")
            }
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

    private func writeQuarantinedTests(
        _ quarantinedTests: [TestIdentifier],
        to resultBundlePath: AbsolutePath
    ) async throws {
        let entries = quarantinedTests.map { test in
            QuarantinedTestEntry(
                target: test.target,
                class: test.class,
                method: test.method
            )
        }
        let filePath = resultBundlePath.appending(component: "quarantined_tests.json")
        try await fileSystem.writeAsJSON(entries, at: filePath)
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

private struct QuarantinedTestEntry: Codable {
    let target: String
    let `class`: String?
    let method: String?
}
