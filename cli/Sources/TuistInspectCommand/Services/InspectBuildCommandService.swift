#if os(macOS)
    import FileSystem
    import Foundation
    import Path
    import TuistAlert
    import TuistConfigLoader
    import TuistCore
    import TuistEnvironment
    import TuistKit
    import TuistLogging
    import TuistProcess
    import TuistSupport
    import TuistXCActivityLog
    import TuistXcodeBuildProducts
    import TuistXcodeProjectOrWorkspacePathLocator

    enum InspectBuildCommandServiceError: Equatable, LocalizedError {
        case executablePathMissing
        case mostRecentActivityLogNotFound(AbsolutePath)
        var errorDescription: String? {
            switch self {
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
        private let configLoader: ConfigLoading
        private let xcActivityLogController: XCActivityLogControlling
        private let backgroundProcessRunner: BackgroundProcessRunning
        private let dateService: DateServicing
        private let uploadBuildRunService: UploadBuildRunServicing
        private let xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating
        init(
            derivedDataLocator: DerivedDataLocating = DerivedDataLocator(),
            fileSystem: FileSysteming = FileSystem(),
            configLoader: ConfigLoading = ConfigLoader(),
            xcActivityLogController: XCActivityLogControlling = XCActivityLogController(),
            backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
            dateService: DateServicing = DateService(),
            uploadBuildRunService: UploadBuildRunServicing = UploadBuildRunService(),
            xcodeProjectOrWorkspacePathLocator: XcodeProjectOrWorkspacePathLocating = XcodeProjectOrWorkspacePathLocator()
        ) {
            self.derivedDataLocator = derivedDataLocator
            self.fileSystem = fileSystem
            self.configLoader = configLoader
            self.xcActivityLogController = xcActivityLogController
            self.backgroundProcessRunner = backgroundProcessRunner
            self.dateService = dateService
            self.uploadBuildRunService = uploadBuildRunService
            self.xcodeProjectOrWorkspacePathLocator = xcodeProjectOrWorkspacePathLocator
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

            let config = try await configLoader.loadConfig(path: projectPath)
            let buildURL = try await uploadBuildRunService.uploadBuildRun(
                activityLogPath: mostRecentActivityLogPath,
                projectPath: projectPath,
                config: config,
                scheme: nil,
                configuration: nil
            )
            AlertController.current.success(
                .alert("Build uploaded for processing. View status at \(buildURL.absoluteString)")
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
#endif
