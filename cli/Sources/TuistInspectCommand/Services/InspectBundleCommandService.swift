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
import TuistLogging
import TuistServer
import TuistSupport

#if os(macOS)
    import TuistKit
    import TuistXcodeBuildProducts
    import XcodeGraph
#endif

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

    #if os(macOS)
        private let buildProductService: BuildProductServicing
        private let appBundleTargetResolver: AppBundleTargetResolving
    #endif

    public init(
        rosalind: Rosalindable = Rosalind(),
        createBundleService: CreateBundleServicing = CreateBundleService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        gitController: GitControlling = GitController()
    ) {
        #if os(macOS)
            self.init(
                rosalind: rosalind,
                createBundleService: createBundleService,
                configLoader: configLoader,
                serverEnvironmentService: serverEnvironmentService,
                gitController: gitController,
                fileSystem: FileSystem(),
                buildProductService: BuildProductService(),
                appBundleTargetResolver: AppBundleTargetResolver()
            )
        #else
            self.init(
                rosalind: rosalind,
                createBundleService: createBundleService,
                configLoader: configLoader,
                serverEnvironmentService: serverEnvironmentService,
                gitController: gitController,
                fileSystem: FileSystem()
            )
        #endif
    }

    #if os(macOS)
        init(
            rosalind: Rosalindable,
            createBundleService: CreateBundleServicing,
            configLoader: ConfigLoading,
            serverEnvironmentService: ServerEnvironmentServicing,
            gitController: GitControlling,
            fileSystem: FileSysteming,
            buildProductService: BuildProductServicing,
            appBundleTargetResolver: AppBundleTargetResolving
        ) {
            self.rosalind = rosalind
            self.createBundleService = createBundleService
            self.configLoader = configLoader
            self.serverEnvironmentService = serverEnvironmentService
            self.gitController = gitController
            self.fileSystem = fileSystem
            self.buildProductService = buildProductService
            self.appBundleTargetResolver = appBundleTargetResolver
        }
    #else
        init(
            rosalind: Rosalindable,
            createBundleService: CreateBundleServicing,
            configLoader: ConfigLoading,
            serverEnvironmentService: ServerEnvironmentServicing,
            gitController: GitControlling,
            fileSystem: FileSysteming
        ) {
            self.rosalind = rosalind
            self.createBundleService = createBundleService
            self.configLoader = configLoader
            self.serverEnvironmentService = serverEnvironmentService
            self.gitController = gitController
            self.fileSystem = fileSystem
        }
    #endif

    #if os(macOS)
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
    #endif

    public func run(
        path: String?,
        bundle: String,
        json: Bool
    ) async throws {
        let path = try await self.path(path)
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let bundlePath = try AbsolutePath(validating: bundle, relativeTo: currentWorkingDirectory)

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

        let gitInfo = try await gitController.gitInfo(workingDirectory: path)
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

    #if os(macOS)
        private func resolveBundlePath(
            _ bundle: String,
            path: AbsolutePath,
            configuration: String?,
            platforms: [Platform],
            derivedDataPath: String?
        ) async throws -> AbsolutePath {
            let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
            let explicitPath = try AbsolutePath(validating: bundle, relativeTo: currentWorkingDirectory)

            if looksLikeBundlePath(explicitPath) {
                return explicitPath
            }

            let resolvedDerivedDataPath = try derivedDataPath.map {
                try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory)
            }

            let appBundleTarget = try await appBundleTargetResolver.resolve(
                app: bundle,
                path: path,
                configuration: configuration,
                platforms: platforms,
                derivedDataPath: resolvedDerivedDataPath
            )

            return try await buildProductService.appBundlePath(
                app: appBundleTarget.app,
                projectPath: appBundleTarget.workspacePath,
                derivedDataPath: appBundleTarget.derivedDataPath,
                configuration: appBundleTarget.configuration,
                platforms: appBundleTarget.platforms
            )
        }

        private func looksLikeBundlePath(_ path: AbsolutePath) -> Bool {
            let bundleExtensions = ["app", "xcarchive", "ipa", "aab", "apk"]
            guard let fileExtension = path.extension else { return false }
            return bundleExtensions.contains(fileExtension)
        }
    #endif

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
