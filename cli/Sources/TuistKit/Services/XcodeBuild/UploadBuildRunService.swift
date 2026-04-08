import FileSystem
import Foundation
import Mockable
import Path
import TuistAutomation
import TuistCASAnalytics
import TuistCI
import TuistConfig
import TuistCore
import TuistEnvironment
import TuistGit
import TuistLogging
import TuistMachineMetrics
import TuistServer
import TuistSupport
import TuistXCActivityLog

enum UploadBuildRunServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        }
    }
}

@Mockable
public protocol UploadBuildRunServicing {
    @discardableResult
    func uploadBuildRun(
        activityLogPath: AbsolutePath,
        projectPath: AbsolutePath,
        config: Tuist,
        scheme: String?,
        configuration: String?
    ) async throws -> URL
}

public struct UploadBuildRunService: UploadBuildRunServicing {
    private let fileSystem: FileSysteming
    private let machineEnvironment: MachineEnvironmentRetrieving
    private let xcodeBuildController: XcodeBuildControlling
    private let createBuildService: CreateBuildServicing
    private let uploadBuildService: UploadBuildServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let ciController: CIControlling

    public init(
        fileSystem: FileSysteming = FileSystem(),
        machineEnvironment: MachineEnvironmentRetrieving = MachineEnvironment.shared,
        xcodeBuildController: XcodeBuildControlling = XcodeBuildController(),
        createBuildService: CreateBuildServicing = CreateBuildService(),
        uploadBuildService: UploadBuildServicing = UploadBuildService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController(),
        ciController: CIControlling = CIController()
    ) {
        self.fileSystem = fileSystem
        self.machineEnvironment = machineEnvironment
        self.xcodeBuildController = xcodeBuildController
        self.createBuildService = createBuildService
        self.uploadBuildService = uploadBuildService
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.ciController = ciController
    }

    @discardableResult
    public func uploadBuildRun(
        activityLogPath: AbsolutePath,
        projectPath: AbsolutePath,
        config: Tuist,
        scheme: String? = nil,
        configuration: String? = nil
    ) async throws -> URL {
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        guard let fullHandle = config.fullHandle else {
            throw UploadBuildRunServiceError.missingFullHandle
        }

        let buildId = activityLogPath.basenameWithoutExt

        let build: ServerBuild = try await fileSystem.runInTemporaryDirectory(prefix: "build") { tempDirectory in
            let archivePath = try await bundleBuild(
                activityLogPath: activityLogPath,
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
                configuration: configuration ?? Environment.current.variables["CONFIGURATION"],
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
                scheme: scheme ?? Environment.current.schemeName,
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
        await RunMetadataStorage.current.update(buildRunURL: build.url)
        return build.url
    }

    private func bundleBuild(
        activityLogPath: AbsolutePath,
        into tempDirectory: AbsolutePath
    ) async throws -> AbsolutePath {
        let buildDirectory = tempDirectory.appending(component: "build")
        try await fileSystem.makeDirectory(at: buildDirectory)

        let xcactivitylogDir = buildDirectory.appending(component: "xcactivitylog")
        try await fileSystem.makeDirectory(at: xcactivitylogDir)
        try await fileSystem.copy(
            activityLogPath,
            to: xcactivitylogDir.appending(component: activityLogPath.basename)
        )

        let casAnalyticsDatabasePath = Environment.current.stateDirectory
            .appending(component: CASAnalyticsDatabase.databaseName)
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
