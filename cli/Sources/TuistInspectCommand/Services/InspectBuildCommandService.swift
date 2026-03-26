#if os(macOS)
    import FileSystem
    import Foundation
    import Path
    import TuistAlert
    import TuistAutomation
    import TuistCI
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistGit
    import TuistLoader
    import TuistLogging
    import TuistMachineMetrics
    import TuistProcess
    import TuistServer
    import TuistSupport
    import TuistXCActivityLog
    import TuistXcodeProjectOrWorkspacePathLocator

    enum InspectBuildCommandServiceError: Equatable, LocalizedError {
        case missingFullHandle
        case executablePathMissing
        case mostRecentActivityLogNotFound(AbsolutePath)
        var errorDescription: String? {
            switch self {
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
        private let uploadBuildService: UploadBuildServicing
        private let configLoader: ConfigLoading
        private let xcActivityLogController: XCActivityLogControlling
        private let backgroundProcessRunner: BackgroundProcessRunning
        private let dateService: DateServicing
        private let serverEnvironmentService: ServerEnvironmentServicing
        private let gitController: GitControlling
        private let ciController: CIControlling
        private let xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating
        private let casAnalyticsDatabasePath: AbsolutePath

        init(
            derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
            fileSystem: FileSysteming = FileSystem(),
            machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
            xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
            createBuildService: CreateBuildServicing = CreateBuildService(),
            uploadBuildService: UploadBuildServicing = UploadBuildService(),
            configLoader: ConfigLoading = ConfigLoader(),
            xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
            backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
            dateService: DateServicing = DateService(),
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            gitController: GitControlling = GitController(),
            ciController: CIControlling = CIController(),
            xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating = XcodeProjectOrWorkspacePathLocator(),
            casAnalyticsDatabasePath: AbsolutePath = Environment.current.stateDirectory.appending(component: "cas_analytics.db")
        ) {
            self.derivedDataLocator = derivedDataLocator
            self.fileSystem = fileSystem
            self.machineEnvironment = machineEnvironment
            self.xcodeBuildController = xcodeBuildController
            self.createBuildService = createBuildService
            self.uploadBuildService = uploadBuildService
            self.configLoader = configLoader
            self.xcActivityLogController = xcActivityLogController
            self.backgroundProcessRunner = backgroundProcessRunner
            self.dateService = dateService
            self.serverEnvironmentService = serverEnvironmentService
            self.gitController = gitController
            self.ciController = ciController
            self.xcodeProjectOrWorkspacePathLocator = xcodeProjectOrWorkspacePathLocator
            self.casAnalyticsDatabasePath = casAnalyticsDatabasePath
        }

        func run(
            path: String?,
            derivedDataPath: String? = nil
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
                try backgroundProcessRunner.runInBackground(
                    [executablePath, "inspect", "build"],
                    environment: environment
                )
                return
            }
            let basePath = try await self.path(path)
            Logger.current.debug("Inspect build: base path resolved to \(basePath.pathString)")
            let projectPath = try await xcodeProjectOrWorkspacePathLocator.locate(from: basePath)
            Logger.current.debug("Inspect build: project path resolved to \(projectPath.pathString)")
            let projectDerivedDataDirectory: AbsolutePath
            if let derivedDataPath {
                let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
                projectDerivedDataDirectory = try AbsolutePath(
                    validating: derivedDataPath,
                    relativeTo: currentWorkingDirectory
                )
            } else {
                projectDerivedDataDirectory = try await derivedDataLocator.locate(for: projectPath)
            }
            Logger.current.debug("Inspect build: derived data directory resolved to \(projectDerivedDataDirectory.pathString)")
            Logger.current
                .debug(
                    "Inspect build: workspace path from environment is \(Environment.current.workspacePath?.pathString ?? "nil")"
                )
            Logger.current
                .debug(
                    "Inspect build: reference date is \(referenceDate) (timeIntervalSinceReferenceDate: \(referenceDate.timeIntervalSinceReferenceDate))"
                )

            let mostRecentActivityLogPath = try await mostRecentActivityLogPath(
                projectPath: projectPath,
                projectDerivedDataDirectory: projectDerivedDataDirectory,
                referenceDate: referenceDate
            )

            try await createRemoteBuild(
                mostRecentActivityLogPath: mostRecentActivityLogPath,
                projectPath: projectPath
            )
        }

        private func mostRecentActivityLogPath(
            projectPath: AbsolutePath,
            projectDerivedDataDirectory: AbsolutePath,
            referenceDate: Date
        ) async throws -> AbsolutePath {
            var mostRecentActivityLogPath: AbsolutePath!
            let timeoutSeconds = Int(Environment.current.variables["TUIST_INSPECT_BUILD_TIMEOUT"] ?? "") ?? 10
            try await withTimeout(
                .seconds(timeoutSeconds),
                onTimeout: {
                    throw InspectBuildCommandServiceError.mostRecentActivityLogNotFound(projectPath)
                }
            ) {
                while true {
                    if let mostRecentActivityLogFile = try await xcActivityLogController.mostRecentActivityLogFile(
                        projectDerivedDataDirectory: projectDerivedDataDirectory,
                        filter: { !$0.signature.hasPrefix("Clean") }
                    ),
                        Environment.current.workspacePath == nil || (
                            referenceDate.timeIntervalSinceReferenceDate - 10 ..< referenceDate.timeIntervalSinceReferenceDate
                                + 10
                        ) ~= mostRecentActivityLogFile.timeStoppedRecording.timeIntervalSinceReferenceDate
                    {
                        mostRecentActivityLogPath = mostRecentActivityLogFile.path
                    }
                    if mostRecentActivityLogPath != nil {
                        Logger.current.debug("Inspect build: using activity log at \(mostRecentActivityLogPath.pathString)")
                        return
                    }

                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            return mostRecentActivityLogPath
        }

        private func createRemoteBuild(
            mostRecentActivityLogPath: AbsolutePath,
            projectPath: AbsolutePath
        ) async throws {
            let config =
                try await configLoader
                    .loadConfig(path: projectPath)
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
            guard let fullHandle = config.fullHandle else {
                throw InspectBuildCommandServiceError.missingFullHandle
            }

            let buildId = mostRecentActivityLogPath.basenameWithoutExt

            let build: ServerBuild = try await fileSystem.runInTemporaryDirectory(prefix: "build") { tempDirectory in
                let archivePath = try await bundleBuild(
                    mostRecentActivityLogPath: mostRecentActivityLogPath,
                    into: tempDirectory
                )
                try await uploadBuildService.uploadBuild(
                    buildId: buildId,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    filePath: archivePath
                )

                let gitInfo = try gitController.gitInfo(workingDirectory: projectPath)
                let ciInfo = ciController.ciInfo()
                let customMetadata = readCustomMetadata()
                return try await createBuildService.createBuild(
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    id: buildId,
                    category: .incremental,
                    configuration: Environment.current.variables["CONFIGURATION"],
                    customMetadata: customMetadata,
                    duration: 0,
                    files: [],
                    gitBranch: gitInfo.branch,
                    gitCommitSHA: gitInfo.sha,
                    gitRef: gitInfo.ref,
                    gitRemoteURLOrigin: gitInfo.remoteURLOrigin,
                    isCI: Environment.current.isCI,
                    issues: [],
                    modelIdentifier: machineEnvironment.modelIdentifier(),
                    macOSVersion: machineEnvironment.macOSVersion,
                    scheme: Environment.current.schemeName,
                    targets: [],
                    xcodeCacheUploadEnabled: config.cache.upload,
                    xcodeVersion: try await xcodeBuildController.version()?.description,
                    status: .processing,
                    ciRunId: ciInfo?.runId,
                    ciProjectHandle: ciInfo?.projectHandle,
                    ciHost: ciInfo?.host,
                    ciProvider: ciInfo?.provider,
                    cacheableTasks: [],
                    casOutputs: [],
                    machineMetrics: []
                )
            }
            AlertController.current.success(
                .alert("Build uploaded for processing. View status at \(build.url.absoluteString)")
            )
        }

        private func bundleBuild(
            mostRecentActivityLogPath: AbsolutePath,
            into tempDirectory: AbsolutePath
        ) async throws -> AbsolutePath {
            let buildDirectory = tempDirectory.appending(component: "build")
            try await fileSystem.makeDirectory(at: buildDirectory)

            let xcactivitylogDir = buildDirectory.appending(component: "xcactivitylog")
            try await fileSystem.makeDirectory(at: xcactivitylogDir)
            try await fileSystem.copy(
                mostRecentActivityLogPath,
                to: xcactivitylogDir.appending(component: mostRecentActivityLogPath.basename)
            )

            if try await fileSystem.exists(casAnalyticsDatabasePath) {
                try await fileSystem.copy(
                    casAnalyticsDatabasePath,
                    to: buildDirectory.appending(component: "cas_analytics.db")
                )
            }

            let metricsSource = MachineMetricsReader.metricsFilePath
            if try await fileSystem.exists(metricsSource) {
                try await fileSystem.copy(
                    metricsSource,
                    to: buildDirectory.appending(component: "machine_metrics.jsonl")
                )
            }

            let zipPath = tempDirectory.appending(component: "build.zip")
            try await fileSystem.zipFileOrDirectoryContent(at: buildDirectory, to: zipPath)
            return zipPath
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

        private func readCustomMetadata() -> BuildCustomMetadata {
            let env = Environment.current.variables
            var tags: [String] = []
            var values: [String: String] = [:]

            if let tagsString = env["TUIST_BUILD_TAGS"] {
                tags.append(
                    contentsOf: tagsString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                )
            }

            for (key, value) in env where key.hasPrefix("TUIST_BUILD_VALUE_") {
                let valueKey = String(key.dropFirst("TUIST_BUILD_VALUE_".count)).lowercased()
                values[valueKey] = value
            }

            return BuildCustomMetadata(
                tags: tags,
                values: BuildCustomMetadata.valuesPayload(additionalProperties: values)
            )
        }
    }
#endif
