import FileSystem
import Foundation
import Noora
import Path
import Rosalind
import TuistAlert
import TuistConfigLoader
import TuistEncodable
import TuistEnvironment
import TuistGit
import TuistKit
import TuistLogging
import TuistServer
import TuistSupport
import TuistXcodeBuildProducts
import XcodeGraph

public enum InspectBundleCommandServiceError: LocalizedError {
    case missingFullHandle

    public var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            "To analyze the app bundle, run 'tuist init' to connect to the Tuist server."
        }
    }
}

public struct InspectBundleCommandService {
    private let rosalind: Rosalindable
    private let createBundleService: CreateBundleServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let gitController: GitControlling
    private let fileSystem: FileSysteming
    private let fileHandler: FileHandling
    private let builtAppBundleLocator: BuiltAppBundleLocating
    private let appBundlePathResolver: AppBundlePathResolving

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
            fileSystem: FileSystem(),
            fileHandler: FileHandler.shared,
            builtAppBundleLocator: BuiltAppBundleLocator(),
            appBundlePathResolver: AppBundlePathResolver()
        )
    }

    init(
        rosalind: Rosalindable,
        createBundleService: CreateBundleServicing,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing,
        gitController: GitControlling,
        fileSystem: FileSysteming,
        fileHandler: FileHandling,
        builtAppBundleLocator: BuiltAppBundleLocating,
        appBundlePathResolver: AppBundlePathResolving
    ) {
        self.rosalind = rosalind
        self.createBundleService = createBundleService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.gitController = gitController
        self.fileSystem = fileSystem
        self.fileHandler = fileHandler
        self.builtAppBundleLocator = builtAppBundleLocator
        self.appBundlePathResolver = appBundlePathResolver
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
        let bundlePath = try await resolveBundlePath(
            bundle,
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

    private func resolveBundlePath(
        _ bundle: String,
        path: AbsolutePath,
        configuration: String?,
        platforms: [Platform],
        derivedDataPath: String?
    ) async throws -> AbsolutePath {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let explicitPath = try AbsolutePath(validating: bundle, relativeTo: currentWorkingDirectory)

        if try await fileSystem.exists(explicitPath) || looksLikeBundlePath(explicitPath) {
            return explicitPath
        }

        let resolvedDerivedDataPath = try derivedDataPath.map {
            try AbsolutePath(validating: $0, relativeTo: fileHandler.currentPath)
        }

        let resolved = try await appBundlePathResolver.resolve(
            app: bundle,
            path: path,
            configuration: configuration,
            platforms: platforms,
            derivedDataPath: resolvedDerivedDataPath
        )

        return try await builtAppBundleLocator.locateBuiltAppBundlePath(
            app: resolved.app,
            projectPath: resolved.workspacePath,
            derivedDataPath: resolved.derivedDataPath,
            configuration: resolved.configuration,
            platforms: resolved.platforms
        )
    }

    private func looksLikeBundlePath(_ path: AbsolutePath) -> Bool {
        let bundleExtensions = ["app", "xcarchive", "ipa", "aab", "apk"]
        guard let fileExtension = path.extension else { return false }
        return bundleExtensions.contains(fileExtension)
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
