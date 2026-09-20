import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
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
    case bundleMissingInfoPlist(AbsolutePath)

    public var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        case let .bundleMissingInfoPlist(path):
            return
                "The xcresult bundle at \(path.pathString) is missing 'Info.plist' — xcodebuild did not finish populating it (the test action was likely interrupted or failed before producing results). Skipping upload."
        }
    }
}

@Mockable
public protocol UploadResultBundleServicing {
    func uploadTestSummary(
        testSummary: TestSummary,
        resultBundlePath: AbsolutePath?,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        shardPlanId: String?,
        shardIndex: Int?,
        onlyTestIdentifiers: [String],
        skipTestIdentifiers: [String],
        stressNewTests: Components.Schemas.StressNewTestsResult?
    ) async throws -> Components.Schemas.RunsTest

    func uploadResultBundle(
        resultBundlePath: AbsolutePath,
        config: Tuist,
        quarantinedTests: [TestIdentifier],
        buildRunId: String?,
        shardPlanId: String?,
        shardIndex: Int?,
        onlyTestIdentifiers: [String],
        skipTestIdentifiers: [String],
        stressNewTests: Components.Schemas.StressNewTestsResult?,
        stressResultBundlePaths: [AbsolutePath]
    ) async throws -> Components.Schemas.RunsTest
}

public struct UploadResultBundleService: UploadResultBundleServicing {
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let createTestService: CreateTestServicing
    private let gitHistoryService: GitHistoryServicing
    private let coverageUploadService: CoverageUploadServicing
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
    private let xcresultToolController: XCResultToolControlling
    private let xcResultService: XCResultServicing

    public init(
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        createTestService: CreateTestServicing = CreateTestService(),
        gitHistoryService: GitHistoryServicing = GitHistoryService(),
        coverageUploadService: CoverageUploadServicing = CoverageUploadService(),
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
        fileSystem: FileSysteming = FileSystem(),
        xcresultToolController: XCResultToolControlling = XCResultToolController(),
        xcResultService: XCResultServicing = XCResultService()
    ) {
        self.machineEnvironment = machineEnvironment
        self.createTestService = createTestService
        self.gitHistoryService = gitHistoryService
        self.coverageUploadService = coverageUploadService
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
        self.xcresultToolController = xcresultToolController
        self.xcResultService = xcResultService
    }

    public func uploadTestSummary(
        testSummary: TestSummary,
        resultBundlePath: AbsolutePath? = nil,
        projectDerivedDataDirectory: AbsolutePath?,
        config: Tuist,
        shardPlanId: String? = nil,
        shardIndex: Int? = nil,
        onlyTestIdentifiers: [String] = [],
        skipTestIdentifiers: [String] = [],
        stressNewTests: Components.Schemas.StressNewTestsResult? = nil
    ) async throws -> Components.Schemas.RunsTest {
        let rootDirectory = try await rootDirectory()
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let gitInfoDirectory = rootDirectory ?? currentWorkingDirectory

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else {
            throw UploadResultBundleServiceError.missingFullHandle
        }

        // Prefer the snapshot-restored buildRunId from RunMetadataStorage (set in the split
        // build/test topology where the test phase reads the build phase's run-metadata
        // snapshot). Fall back to the local activity log when the test phase shares
        // DerivedData with the build phase.
        var buildRunId: String? = await RunMetadataStorage.current.buildRunId
        if buildRunId == nil,
           let projectDerivedDataDirectory,
           let mostRecentActivityLogFile = try await xcActivityLogController.mostRecentActivityLogFile(
               projectDerivedDataDirectory: projectDerivedDataDirectory
           )
        {
            buildRunId = mostRecentActivityLogFile.path.basenameWithoutExt
        }

        // The server that receives a locally processed run has no Xcode to read the coverage
        // with, so the client reads it, through the same parser the server runs on a bundle.
        // The execution modes and the enumerated tests were recorded into the bundle after the
        // summary was parsed.
        var testSummary = testSummary
        if let resultBundlePath {
            let bundle = URL(fileURLWithPath: resultBundlePath.pathString)
            testSummary = testSummary
                .applying(executionModes: TestExecutionModes.read(fromResultBundle: bundle))
                .applying(enumeration: TestEnumeration.read(fromResultBundle: bundle))
        }
        var coverageUpload: XcodeCoverageUpload?
        var testRunId: String?
        if let resultBundlePath,
           let manifest = await coverageManifest(
               resultBundlePath: resultBundlePath,
               config: config,
               rootDirectory: gitInfoDirectory,
               onlyTestIdentifiers: onlyTestIdentifiers,
               skipTestIdentifiers: skipTestIdentifiers
           )
        {
            // The evidence's paths are the compiler's; the manifest is what ties them to the
            // repository, as it does for the coverage itself.
            testSummary = testSummary.applying(
                coverageEvidence: TestCoverageEvidence
                    .read(fromResultBundle: URL(fileURLWithPath: resultBundlePath.pathString))?
                    .inRepository(manifest: manifest)
            )
            if let prepared = await coverageUploadService.prepare(
                resultBundlePath: resultBundlePath,
                manifest: manifest,
                fullHandle: fullHandle,
                serverURL: serverURL
            ) {
                testSummary.coverage = prepared.inline
                coverageUpload = prepared.upload
                testRunId = prepared.testRunId
            }
        }

        let gitInfo = try await gitController.gitInfo(workingDirectory: gitInfoDirectory)
        let ciInfo = ciController.ciInfo()
        let gitHistory = await gitHistoryService.collect(
            gitInfo: gitInfo,
            workingDirectory: gitInfoDirectory,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
        let test = try await createTestService.createTest(
            fullHandle: fullHandle,
            serverURL: serverURL,
            id: testRunId,
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
            shardIndex: shardIndex,
            onlyTestIdentifiers: onlyTestIdentifiers,
            skipTestIdentifiers: skipTestIdentifiers,
            stressNewTests: stressNewTests,
            gitHistory: gitHistory?.payload,
            coverageUpload: coverageUpload
        )
        await gitHistoryService.upload(
            gitHistory,
            workingDirectory: gitInfoDirectory,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        let testCaseRunsByIdentity = testCaseRunsByIdentity(testCaseRuns: test.test_case_runs)

        await testSummary.testCases.forEach(context: .concurrent) { testCase in
            await uploadAttachments(
                for: testCase,
                fullHandle: fullHandle,
                serverURL: serverURL,
                testCaseRunsByIdentity: testCaseRunsByIdentity
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
        shardIndex: Int? = nil,
        onlyTestIdentifiers: [String] = [],
        skipTestIdentifiers: [String] = [],
        stressNewTests: Components.Schemas.StressNewTestsResult? = nil,
        stressResultBundlePaths: [AbsolutePath] = []
    ) async throws -> Components.Schemas.RunsTest {
        guard let fullHandle = config.fullHandle else {
            throw UploadResultBundleServiceError.missingFullHandle
        }

        // Older Xcode versions dropped a `<name>` → `<name>.xcresult` symlink
        // alongside the bundle when `-resultBundlePath` was given without an
        // extension, and callers might still pass such a path through
        // `--result-bundle-path`. Resolve any symlink so the archiver zips the
        // real directory, not the pointer.
        let resolvedResultBundlePath = try await fileSystem.resolveSymbolicLink(resultBundlePath)

        // A populated xcresult bundle has Info.plist at its root. If it's
        // missing, xcodebuild was interrupted before writing results — uploading
        // the empty skeleton just produces a 5-attempt failure on the server side
        // and a Sentry alert for nothing actionable.
        let infoPlistPath = resolvedResultBundlePath.appending(component: "Info.plist")
        if !(try await fileSystem.exists(infoPlistPath)) {
            throw UploadResultBundleServiceError.bundleMissingInfoPlist(resolvedResultBundlePath)
        }

        if !quarantinedTests.isEmpty {
            try await writeQuarantinedTests(quarantinedTests, to: resolvedResultBundlePath)
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let rootDirectory = try await rootDirectory()
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let gitInfoDirectory = rootDirectory ?? currentWorkingDirectory

        // The server reads the coverage from the bundle, but only this checkout can say which
        // repository files its paths are and which Git blobs they had, so that travels inside the
        // bundle, the way the quarantined tests do.
        let coverageManifestPath = resolvedResultBundlePath.appending(component: XcodeCoverageManifest.fileName)
        if let manifest = await coverageManifest(
            resultBundlePath: resolvedResultBundlePath,
            config: config,
            rootDirectory: gitInfoDirectory,
            onlyTestIdentifiers: onlyTestIdentifiers,
            skipTestIdentifiers: skipTestIdentifiers
        ) {
            try await fileSystem.writeAsJSON(manifest, at: coverageManifestPath)
        } else if try await fileSystem.exists(coverageManifestPath) {
            // An earlier upload of this bundle wrote one; the server reads coverage from whatever
            // manifest the bundle carries.
            try await fileSystem.remove(coverageManifestPath)
        }
        let gitInfo = try await gitController.gitInfo(workingDirectory: gitInfoDirectory)
        let ciInfo = ciController.ciInfo()
        let gitHistory = await gitHistoryService.collect(
            gitInfo: gitInfo,
            workingDirectory: gitInfoDirectory,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        let testRunId = UUID().uuidString.lowercased()

        try await analyticsArtifactUploadService.uploadResultBundle(
            resolvedResultBundlePath,
            fullHandle: fullHandle,
            commandEventId: testRunId,
            serverURL: serverURL
        )

        // The gate's pass wrote its own bundle. It goes up under the same run id, so the
        // server can fold its executions into the test cases they belong to when it parses
        // the run's own. A failure here costs the gate's per-execution detail and nothing
        // else: the run and the gate's verdict are reported either way.
        var stressNewTests = stressNewTests
        if !stressResultBundlePaths.isEmpty {
            do {
                try await analyticsArtifactUploadService.uploadStressResultBundle(
                    mergedStressResultBundle(stressResultBundlePaths),
                    fullHandle: fullHandle,
                    commandEventId: testRunId,
                    serverURL: serverURL
                )
                stressNewTests?.has_result_bundle = true
            } catch {
                AlertController.current.warning(
                    .alert("Failed to upload the stress gate's results: \(error.localizedDescription)")
                )
            }
        }

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
            shardIndex: shardIndex,
            onlyTestIdentifiers: onlyTestIdentifiers,
            skipTestIdentifiers: skipTestIdentifiers,
            stressNewTests: stressNewTests,
            gitHistory: gitHistory?.payload,
            coverageUpload: nil
        )
        await gitHistoryService.upload(
            gitHistory,
            workingDirectory: gitInfoDirectory,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        return test
    }

    private func uploadAttachments(
        for testCase: TestCase,
        fullHandle: String,
        serverURL: URL,
        testCaseRunsByIdentity: [String: Components.Schemas.RunsTest.test_case_runsPayloadPayload]
    ) async {
        guard !testCase.attachments.isEmpty else { return }

        let identityKey = testCaseRunIdentityKey(
            moduleName: testCase.module ?? "",
            suiteName: testCase.testSuite ?? "",
            name: testCase.name
        )
        guard let run = testCaseRunsByIdentity[identityKey] else { return }

        await testCase.attachments.forEach(context: .serial) { attachment in
            do {
                let argumentId: String? = attachment.argumentName.flatMap { argName in
                    run.arguments?.first(where: { $0.name == argName })?.id
                }
                let testCaseRunAttachmentId = try await createTestCaseRunAttachmentService.createAttachment(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    testCaseRunId: run.id,
                    fileName: attachment.fileName,
                    filePath: attachment.filePath,
                    repetitionNumber: attachment.repetitionNumber,
                    testCaseRunArgumentId: argumentId
                )
                if let crashReport = testCase.crashReport,
                   crashReport.filePath == attachment.filePath
                {
                    try await createCrashReportService.createCrashReport(
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        crashReport: crashReport,
                        testCaseRunId: run.id,
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
        if await gitController.isInGitRepository(workingDirectory: workingDirectory) {
            return try await gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
        } else {
            return try await rootDirectoryLocator.locate(from: workingDirectory)
        }
    }
}

extension UploadResultBundleService {
    private func testCaseRunsByIdentity(
        testCaseRuns: [Components.Schemas.RunsTest.test_case_runsPayloadPayload]
    ) -> [String: Components.Schemas.RunsTest.test_case_runsPayloadPayload] {
        testCaseRuns.reduce(into: [:]) { result, run in
            let key = testCaseRunIdentityKey(moduleName: run.module_name, suiteName: run.suite_name, name: run.name)
            result[key] = run
        }
    }

    private func testCaseRunIdentityKey(moduleName: String, suiteName: String, name: String) -> String {
        if suiteName.isEmpty {
            return "\(moduleName)/\(name)"
        } else {
            return "\(moduleName)/\(suiteName)/\(name)"
        }
    }
}

private struct QuarantinedTestEntry: Codable {
    let target: String
    let `class`: String?
    let method: String?
}

extension UploadResultBundleService {
    /// Source files whose Git blobs the manifest records: what the compiler instruments for
    /// coverage in Xcode projects.
    static let coverageSourceExtensions: Set<String> = [
        "swift", "m", "mm", "c", "cc", "cp", "cpp", "cxx", "c++", "h", "hh", "hpp", "hxx", "inl",
    ]

    /// Nil when the bundle has no coverage, which is every run that did not enable it. Coverage
    /// only enriches a run, so a manifest that cannot be built costs the run its coverage and
    /// nothing else.
    private func coverageManifest(
        resultBundlePath: AbsolutePath,
        config: Tuist,
        rootDirectory: AbsolutePath,
        onlyTestIdentifiers: [String],
        skipTestIdentifiers: [String]
    ) async -> XcodeCoverageManifest? {
        guard Self.uploadsCoverage(config: config) else { return nil }
        do {
            guard let coveredFilePaths = try await xcResultService.coveredFilePaths(path: resultBundlePath) else { return nil }

            // Test products built in another checkout carry that checkout: the compiler embedded its
            // paths, and only the build knows which blobs it compiled. The current checkout may be
            // at other content, so its blobs are never used for those products.
            let buildSources = await RunMetadataStorage.current.coverageBuildSources
            var rootSpellings = buildSources?.rootDirectories ?? []
            for spelling in Self.rootSpellings(of: rootDirectory, coveredFilePaths: coveredFilePaths)
                where !rootSpellings.contains(spelling)
            {
                rootSpellings.append(spelling)
            }
            let coveredPaths = Set(coveredFilePaths.map { Self.relativize($0, to: rootSpellings) })
            if !coveredPaths.isEmpty, coveredPaths.allSatisfy({ $0.hasPrefix("/") }) {
                AlertController.current.warning(
                    .alert(
                        "None of the \(coveredPaths.count) files covered in \(resultBundlePath.pathString) are under \(rootSpellings.joined(separator: " or ")), so the run has no coverage. If the test products were built in another checkout, build them with 'tuist xcodebuild build-for-testing -testProductsPath' or 'tuist test --build-only' so Tuist records that checkout."
                    )
                )
            }
            let blobIds: [String: String]
            if let buildSources {
                blobIds = buildSources.files.filter { coveredPaths.contains($0.key) }
            } else if await gitController.isInGitRepository(workingDirectory: rootDirectory) {
                blobIds = try await gitController.sourceFileBlobIds(
                    workingDirectory: rootDirectory,
                    pathExtensions: Self.coverageSourceExtensions
                ).filter { coveredPaths.contains($0.key) }
            } else {
                blobIds = [:]
            }

            // The run's coverage only describes the tests that ran. A selective-testing hit is a
            // test target skipped because nothing it depends on changed.
            let selectiveTestingSkippedTargets = await RunMetadataStorage.current.selectiveTestingCacheItems.values
                .contains { $0.values.contains { $0.source != .miss } }
            let skippedQuarantinedTests = await RunMetadataStorage.current.skippedQuarantinedTestIdentifiers
            let partial = !onlyTestIdentifiers.isEmpty
                || skipTestIdentifiers.contains { !skippedQuarantinedTests.contains($0) }
                || selectiveTestingSkippedTargets

            return XcodeCoverageManifest(
                rootDirectories: rootSpellings,
                partial: partial,
                files: blobIds.map { XcodeCoverageSourceFile(path: $0.key, gitBlobId: $0.value) }
                    .sorted { $0.path < $1.path }
            )
        } catch {
            AlertController.current.warning(
                .alert("Failed to prepare the code coverage of \(resultBundlePath.pathString): \(error.localizedDescription)")
            )
            return nil
        }
    }

    static let coverageUploadVariable = "TUIST_COVERAGE_UPLOAD"

    /// Coverage is in early access behind the `COVERAGE` client feature flag
    /// (`TUIST_FEATURE_FLAG_COVERAGE=1`), so released CLIs do no coverage work until it ships. Once
    /// on, the environment variable, when set, wins over `Tuist.swift`, so a single run or CI job can
    /// opt out of, or back into, a team-wide setting.
    static func uploadsCoverage(config: Tuist) -> Bool {
        guard ClientFeatureFlags.contains("COVERAGE") else { return false }
        guard Environment.current.variables[coverageUploadVariable] != nil else {
            return config.testInsights.coverage.upload
        }
        return Environment.current.isVariableTruthy(coverageUploadVariable)
    }

    /// Every spelling of the root the covered files use. The compiler records the path the build
    /// was invoked through, which is not always the one Git reports: `/tmp` is `/private/tmp` on
    /// macOS, and a checkout can be reached through a symlink. A file whose canonical path is under
    /// the root contributes the prefix it was recorded with.
    static func rootSpellings(of root: AbsolutePath, coveredFilePaths: [String]) -> [String] {
        let canonicalRoot = canonical(root.pathString)
        var spellings = [root.pathString]
        if canonicalRoot != root.pathString { spellings.append(canonicalRoot) }

        for path in coveredFilePaths where path.hasPrefix("/") && !spellings.contains(where: { path.hasPrefix($0 + "/") }) {
            let resolved = canonical(path)
            guard resolved.hasPrefix(canonicalRoot + "/") else { continue }
            let relative = resolved.dropFirst(canonicalRoot.count)
            guard path.hasSuffix(relative) else { continue }
            spellings.append(String(path.dropLast(relative.count)))
        }
        return spellings
    }

    /// The path relative to the longest root spelling it lives under, the way the parser
    /// relativizes it, or the path unchanged.
    private static func relativize(_ path: String, to roots: [String]) -> String {
        for root in roots.sorted(by: { $0.count > $1.count }) where path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return path
    }

    /// `realpath` of the longest existing prefix with the rest appended, so a file the bundle
    /// names but the checkout no longer has still resolves through the directories that exist.
    private static func canonical(_ path: String) -> String {
        var existing = path
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing), existing != "/" {
            rest.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        guard let resolved = realpath(existing, nil) else { return path }
        defer { free(resolved) }
        let base = String(cString: resolved)
        guard !rest.isEmpty else { return base }
        return (base == "/" ? "" : base) + "/" + rest.joined(separator: "/")
    }

    /// One bundle for the server to parse. A run whose candidates were priced at different
    /// repetition counts ran a pass per count, and those are merged the same way the
    /// per-scheme bundles of a multi-scheme run are.
    private func mergedStressResultBundle(_ paths: [AbsolutePath]) async throws -> AbsolutePath {
        guard paths.count > 1 else { return paths[0] }
        let directory = try await fileSystem.makeTemporaryDirectory(prefix: "stress-new-tests-merged")
        let merged = directory.appending(component: "stress.xcresult")
        try await xcresultToolController.merge(paths, into: merged)
        return merged
    }
}
