import Foundation
import Noora
import Path
import Rosalind
import TuistAlert
import TuistConfigLoader
import TuistEncodable
import TuistEnvironment
import TuistGit
import TuistLogging
import TuistServer
import XcodeGraph

public enum InspectBundleCommandServiceError: LocalizedError {
    case missingFullHandle
    case appleAppNameResolutionNotSupported
    case projectOrWorkspaceNotFound(path: String)
    case noAppsFound(app: String, configuration: String)
    case multipleBuiltBundlesFound(app: String, paths: [String])
    case platformsNotSpecified

    public var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            "To analyze the app bundle, run 'tuist init' to connect to the Tuist server."
        case .appleAppNameResolutionNotSupported:
            "Resolving an app name for Apple platforms from Xcode build products is only supported on macOS. Pass an explicit bundle path instead."
        case let .projectOrWorkspaceNotFound(path):
            "Workspace or project not found at \(path)"
        case let .noAppsFound(app, configuration):
            "\(app) for the \(configuration) configuration was not found. You can build it by running `xcodebuild build -scheme \(app) -configuration \(configuration)`"
        case let .multipleBuiltBundlesFound(app, paths):
            "Multiple built bundles were found for \(app): \(paths.joined(separator: ", ")). Pass an explicit bundle path."
        case .platformsNotSpecified:
            "If you're not using Tuist projects, you must specify the platforms when inspecting an app by name, such as `tuist inspect bundle App --platforms ios`."
        }
    }
}

public struct InspectBundleCommandService {
    private let rosalind: Rosalindable
    private let createBundleService: CreateBundleServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let bundlePathResolver: any InspectBundlePathResolving

    public init(
        rosalind: Rosalindable = Rosalind(),
        createBundleService: CreateBundleServicing = CreateBundleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController()
    ) {
        self.init(
            rosalind: rosalind,
            createBundleService: createBundleService,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            bundlePathResolver: makeInspectBundlePathResolver()
        )
    }

    init(
        rosalind: Rosalindable,
        createBundleService: CreateBundleServicing,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing,
        gitController: GitControlling,
        bundlePathResolver: any InspectBundlePathResolving
    ) {
        self.rosalind = rosalind
        self.createBundleService = createBundleService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.bundlePathResolver = bundlePathResolver
    }

    public func run(
        path: String?,
        bundle: String,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: String?,
        json: Bool
    ) async throws {
        let path = try await self.path(path)
        let bundlePath = try await bundlePathResolver.resolve(
            bundle: bundle,
            path: path,
            configuration: configuration,
            platforms: platforms,
            derivedDataPath: derivedDataPath
        )

        try await inspect(
            path: path,
            bundlePath: bundlePath,
            json: json
        )
    }

    private func inspect(
        path: AbsolutePath,
        bundlePath: AbsolutePath,
        json: Bool
    ) async throws {
        let config = try await configLoader.loadConfig(path: path)

        if json {
            let appBundleReport = try await rosalind.analyzeAppBundle(at: bundlePath)
            let json = try appBundleReport.toJSON()
            Logger.current.info(
                .init(stringLiteral: json.toString(prettyPrint: true)),
                metadata: .json
            )
            return
        }

        guard let fullHandle = config.fullHandle else {
            throw InspectBundleCommandServiceError.missingFullHandle
        }

        let gitInfo = try gitController.gitInfo(workingDirectory: path)
        let gitRef = gitInfo.ref
        let gitBranch = gitInfo.branch
        let gitCommitSHA = gitInfo.sha

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let serverBundle = try await Noora.current.progressStep(
            message: "Analyzing bundle...",
            successMessage: "Bundle analyzed",
            errorMessage: nil,
            showSpinner: true
        ) { updateStep in
            let appBundleReport = try await rosalind.analyzeAppBundle(at: bundlePath)
            updateStep("Pushing bundle to the server...")
            return try await createBundleService.createBundle(
                fullHandle: fullHandle,
                serverURL: serverURL,
                appBundleReport: appBundleReport,
                gitCommitSHA: gitCommitSHA,
                gitBranch: gitBranch,
                gitRef: gitRef
            )
        }
        AlertController.current.success(
            .alert("View the bundle analysis at \(serverBundle.url)")
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
