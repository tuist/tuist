#if os(macOS)
    import FileSystem
    import Foundation
    import Path
    import TuistAlert
    import TuistAutomation
    import TuistCI
    import TuistConfig
    import TuistConfigLoader
    import TuistCore
    import TuistGit
    import TuistRootDirectoryLocator
    import TuistEnvironment
    import TuistKit
    import TuistLoader
    import TuistLogging
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
        private let uploadResultBundleService: UploadResultBundleServicing
        private let analyticsArtifactUploadService: AnalyticsArtifactUploadServicing
        private let createTestService: CreateTestServicing
        private let configLoader: ConfigLoading
        private let backgroundProcessRunner: BackgroundProcessRunning
        private let serverEnvironmentService: ServerEnvironmentServicing
        private let gitController: GitControlling
        private let ciController: CIControlling
        private let machineEnvironment: MachineEnvironmentRetrieving
        private let xcodeBuildController: XcodeBuildControlling
        private let rootDirectoryLocator: RootDirectoryLocating

        init(
            derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
            fileSystem: FileSysteming = FileSystem(),
            xcResultService: XCResultServicing = XCResultService(),
            xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating = XcodeProjectOrWorkspacePathLocator(),
            uploadResultBundleService: UploadResultBundleServicing = UploadResultBundleService(),
            analyticsArtifactUploadService: AnalyticsArtifactUploadServicing = AnalyticsArtifactUploadService(),
            createTestService: CreateTestServicing = CreateTestService(),
            configLoader: ConfigLoading = ConfigLoader(),
            backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            gitController: GitControlling = GitController(),
            ciController: CIControlling = CIController(),
            machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
            xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
            rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
        ) {
            self.derivedDataLocator = derivedDataLocator
            self.fileSystem = fileSystem
            self.xcResultService = xcResultService
            self.xcodeProjectOrWorkspacePathLocator = xcodeProjectOrWorkspacePathLocator
            self.uploadResultBundleService = uploadResultBundleService
            self.analyticsArtifactUploadService = analyticsArtifactUploadService
            self.createTestService = createTestService
            self.configLoader = configLoader
            self.backgroundProcessRunner = backgroundProcessRunner
            self.serverEnvironmentService = serverEnvironmentService
            self.gitController = gitController
            self.ciController = ciController
            self.machineEnvironment = machineEnvironment
            self.xcodeBuildController = xcodeBuildController
            self.rootDirectoryLocator = rootDirectoryLocator
        }

        func run(
            path: String?,
            derivedDataPath: String? = nil,
            resultBundlePath: String? = nil,
            mode: InspectTestCommand.ProcessingMode = .local
        ) async throws {
            if Environment.current.variables["TUIST_INSPECT_TEST_WAIT"] != "YES",
               Environment.current.workspacePath != nil
            {
                guard let executablePath = Environment.current.currentExecutablePath() else {
                    throw InspectTestCommandServiceError.executablePathMissing
                }
                var environment = Environment.current.variables
                environment["TUIST_INSPECT_TEST_WAIT"] = "YES"
                try backgroundProcessRunner.runInBackground(
                    [executablePath.pathString, "inspect", "test"],
                    environment: environment
                )
                return
            }

            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)

            let (resolvedResultBundlePath, projectDerivedDataDirectory) = try await resolveResultBundlePath(
                resultBundlePath: resultBundlePath,
                basePath: path,
                derivedDataPath: derivedDataPath
            )

            let projectPath = try await xcodeProjectOrWorkspacePathLocator.locate(from: path)
            let config = try await configLoader.loadConfig(path: projectPath)

            switch mode {
            case .local:
                try await runLocal(
                    resolvedResultBundlePath: resolvedResultBundlePath,
                    projectDerivedDataDirectory: projectDerivedDataDirectory,
                    path: path,
                    config: config
                )
            case .remote:
                try await runRemote(
                    resolvedResultBundlePath: resolvedResultBundlePath,
                    config: config
                )
            }
        }

        private func runLocal(
            resolvedResultBundlePath: AbsolutePath,
            projectDerivedDataDirectory: AbsolutePath?,
            path: AbsolutePath,
            config: Tuist
        ) async throws {
            guard let testSummary = try await xcResultService.parse(
                path: resolvedResultBundlePath,
                rootDirectory: path
            ) else {
                throw InspectTestCommandServiceError.mostRecentResultBundleNotFound(resolvedResultBundlePath)
            }

            let test = try await uploadResultBundleService.uploadResultBundle(
                testSummary: testSummary,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                config: config,
                shardPlanId: nil,
                shardIndex: nil
            )

            AlertController.current.success(
                .alert("View the analyzed test at \(test.url)")
            )
        }

        private func runRemote(
            resolvedResultBundlePath: AbsolutePath,
            config: Tuist
        ) async throws {
            guard let fullHandle = config.fullHandle else {
                throw UploadResultBundleServiceError.missingFullHandle
            }

            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let workingDirectory = Environment.current.workspacePath ?? currentWorkingDirectory
            let rootDirectory: AbsolutePath? = if gitController.isInGitRepository(workingDirectory: workingDirectory) {
                try gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
            } else {
                try await rootDirectoryLocator.locate(from: workingDirectory)
            }
            let gitInfoDirectory = rootDirectory ?? currentWorkingDirectory
            let gitInfo = try gitController.gitInfo(workingDirectory: gitInfoDirectory)
            let ciInfo = ciController.ciInfo()

            let testSummary = TestSummary(
                testPlanName: nil,
                status: .passed,
                duration: 0,
                testModules: []
            )

            let test = try await createTestService.createTest(
                fullHandle: fullHandle,
                serverURL: serverURL,
                testSummary: testSummary,
                buildRunId: nil,
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
                shardPlanId: nil,
                shardIndex: nil,
                status: "processing"
            )

            let components = fullHandle.components(separatedBy: "/")
            let accountHandle = components[0]
            let projectHandle = components[1]

            try await analyticsArtifactUploadService.uploadResultBundleOnly(
                resolvedResultBundlePath,
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                commandEventId: test.id,
                serverURL: serverURL
            )

            AlertController.current.success(
                .alert("Result bundle uploaded for processing. View at \(test.url)")
            )
        }

        private func resolveResultBundlePath(
            resultBundlePath: String?,
            basePath: AbsolutePath,
            derivedDataPath: String?
        ) async throws -> (resultBundlePath: AbsolutePath, derivedDataDirectory: AbsolutePath?) {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            Logger.current.debug("Inspect test: base path is \(basePath.pathString)")
            Logger.current
                .debug(
                    "Inspect test: workspace path from environment is \(Environment.current.workspacePath?.pathString ?? "nil")"
                )

            if let resultBundlePath {
                Logger.current.debug("Inspect test: using explicit result bundle path \(resultBundlePath)")
                let derivedDataDirectory: AbsolutePath? = if let derivedDataPath {
                    try AbsolutePath(
                        validating: derivedDataPath,
                        relativeTo: currentWorkingDirectory
                    )
                } else {
                    nil
                }
                return (
                    try AbsolutePath(
                        validating: resultBundlePath,
                        relativeTo: currentWorkingDirectory
                    ),
                    derivedDataDirectory
                )
            }

            let projectPath = try await xcodeProjectOrWorkspacePathLocator.locate(from: basePath)
            Logger.current.debug("Inspect test: project path resolved to \(projectPath.pathString)")
            let projectDerivedDataDirectory: AbsolutePath
            if let derivedDataPath {
                projectDerivedDataDirectory = try AbsolutePath(
                    validating: derivedDataPath,
                    relativeTo: currentWorkingDirectory
                )
            } else {
                projectDerivedDataDirectory = try await derivedDataLocator.locate(for: projectPath)
            }
            Logger.current.debug("Inspect test: derived data directory resolved to \(projectDerivedDataDirectory.pathString)")

            guard let xcResultPath = try await xcResultService
                .mostRecentXCResultFile(projectDerivedDataDirectory: projectDerivedDataDirectory)
            else {
                Logger.current.debug("Inspect test: no result bundle found in \(projectDerivedDataDirectory.pathString)")
                throw InspectTestCommandServiceError.mostRecentResultBundleNotFound(projectDerivedDataDirectory)
            }
            Logger.current.debug("Inspect test: using result bundle at \(xcResultPath.pathString)")
            return (xcResultPath, projectDerivedDataDirectory)
        }
    }
#endif
