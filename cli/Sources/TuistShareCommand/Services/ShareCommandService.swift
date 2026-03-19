import FileSystem
import Foundation
import Noora
import Path
import TuistAlert
import TuistAndroid
import TuistConfigLoader
import TuistConstants
import TuistEncodable
import TuistEnvironment
import TuistGit
import TuistLogging
import TuistServer
import TuistSupport

#if os(macOS)
    import TuistAutomation
    import TuistCore
    import TuistKit
    import TuistSimulator
    import TuistXcodeBuildProducts
    import XcodeGraph
#endif

enum ShareCommandServiceError: Equatable, LocalizedError {
    case fullHandleNotFound
    case multipleAppsSpecified([String])
    #if os(macOS)
        case appNotSpecified
    #endif
    case appleBuildsSharingNotSupportedOnLinux

    var errorDescription: String? {
        switch self {
        case .fullHandleNotFound:
            return "You are missing fullHandle in your \(Constants.tuistManifestFileName). Run 'tuist init' to get started with remote Tuist features."
        case let .multipleAppsSpecified(apps):
            return "You specified multiple apps to share: \(apps.joined(separator: " ")). You cannot specify multiple apps when using `tuist share`."
        #if os(macOS)
            case .appNotSpecified:
                return "If you're not using Tuist projects, you must specify the app name when sharing an app, such as `tuist share App --platforms ios`."
        #endif
        case .appleBuildsSharingNotSupportedOnLinux:
            return "Sharing Apple app bundles and IPAs is only supported on macOS. On Linux, only APK files can be shared."
        }
    }
}

// swiftlint:disable:next type_body_length
struct ShareCommandService {
    private let fileSystem: FileSysteming
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let previewsUploadService: PreviewsUploadServicing
    private let apkMetadataService: APKMetadataServicing
    private let fileArchiverFactory: FileArchivingFactorying
    private let gitController: GitControlling

    #if os(macOS)
        private let builtAppBundleLocator: BuiltAppBundleLocating
        private let buildGraphInspector: BuildGraphInspecting
        private let appBundlePathResolver: AppBundlePathResolving
        private let appBundleLoader: AppBundleLoading
    #endif

    init() {
        #if os(macOS)
            self.init(
                fileSystem: FileSystem(),
                configLoader: ConfigLoader(),
                serverEnvironmentService: ServerEnvironmentService(),
                previewsUploadService: PreviewsUploadService(),
                apkMetadataService: APKMetadataService(),
                fileArchiverFactory: FileArchivingFactory(),
                gitController: GitController(),
                builtAppBundleLocator: BuiltAppBundleLocator(),
                buildGraphInspector: BuildGraphInspector(),
                appBundlePathResolver: AppBundlePathResolver(),
                appBundleLoader: AppBundleLoader()
            )
        #else
            self.init(
                fileSystem: FileSystem(),
                configLoader: ConfigLoader(),
                serverEnvironmentService: ServerEnvironmentService(),
                previewsUploadService: PreviewsUploadService(),
                apkMetadataService: APKMetadataService(),
                fileArchiverFactory: FileArchivingFactory(),
                gitController: GitController()
            )
        #endif
    }

    #if os(macOS)
        init(
            fileSystem: FileSysteming,
            configLoader: ConfigLoading,
            serverEnvironmentService: ServerEnvironmentServicing,
            previewsUploadService: PreviewsUploadServicing,
            apkMetadataService: APKMetadataServicing,
            fileArchiverFactory: FileArchivingFactorying,
            gitController: GitControlling,
            builtAppBundleLocator: BuiltAppBundleLocating,
            buildGraphInspector: BuildGraphInspecting,
            appBundlePathResolver: AppBundlePathResolving,
            appBundleLoader: AppBundleLoading
        ) {
            self.fileSystem = fileSystem
            self.configLoader = configLoader
            self.serverEnvironmentService = serverEnvironmentService
            self.previewsUploadService = previewsUploadService
            self.apkMetadataService = apkMetadataService
            self.fileArchiverFactory = fileArchiverFactory
            self.gitController = gitController
            self.builtAppBundleLocator = builtAppBundleLocator
            self.buildGraphInspector = buildGraphInspector
            self.appBundlePathResolver = appBundlePathResolver
            self.appBundleLoader = appBundleLoader
        }
    #else
        init(
            fileSystem: FileSysteming,
            configLoader: ConfigLoading,
            serverEnvironmentService: ServerEnvironmentServicing,
            previewsUploadService: PreviewsUploadServicing,
            apkMetadataService: APKMetadataServicing,
            fileArchiverFactory: FileArchivingFactorying,
            gitController: GitControlling
        ) {
            self.fileSystem = fileSystem
            self.configLoader = configLoader
            self.serverEnvironmentService = serverEnvironmentService
            self.previewsUploadService = previewsUploadService
            self.apkMetadataService = apkMetadataService
            self.fileArchiverFactory = fileArchiverFactory
            self.gitController = gitController
        }
    #endif

    // MARK: - macOS run

    #if os(macOS)
        // swiftlint:disable:next function_body_length
        func run(
            path: String?,
            apps: [String],
            configuration: String?,
            platforms: [Platform],
            derivedDataPath: String?,
            json: Bool,
            track: String?
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            guard let fullHandle = config.fullHandle else {
                throw ShareCommandServiceError.fullHandleNotFound
            }

            let derivedDataPath: AbsolutePath? = try await {
                if let derivedDataPath {
                    return try await Environment.current.pathRelativeToWorkingDirectory(derivedDataPath)
                }
                return nil
            }()

            let appPaths = try await apps.concurrentMap {
                try AbsolutePath(
                    validating: $0,
                    relativeTo: path
                )
            }
            if appPaths.contains(where: { $0.extension == "apk" }) {
                try await shareAPK(
                    appPaths,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            } else if appPaths.contains(where: { $0.extension == "ipa" }) {
                try await shareIPA(
                    appPaths,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            } else if appPaths.contains(where: { $0.extension == "app" }) {
                try await shareAppBundles(
                    appPaths,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            } else {
                guard apps.count < 2 else { throw ShareCommandServiceError.multipleAppsSpecified(apps) }

                let resolved = try await appBundlePathResolver.resolve(
                    app: apps.first,
                    path: path,
                    configuration: configuration,
                    platforms: platforms,
                    derivedDataPath: derivedDataPath
                )

                try await uploadApplePreview(
                    for: resolved.platforms,
                    workspacePath: resolved.workspacePath,
                    configuration: resolved.configuration,
                    app: resolved.app,
                    derivedDataPath: resolved.derivedDataPath,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    json: json,
                    track: track
                )
            }
        }
    #endif

    // MARK: - Linux run

    #if !os(macOS)
        func run(
            path: String?,
            apps: [String],
            json: Bool,
            track: String?
        ) async throws {
            let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
            let config = try await configLoader.loadConfig(path: path)
            let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

            guard let fullHandle = config.fullHandle else {
                throw ShareCommandServiceError.fullHandleNotFound
            }

            let appPaths = try await apps.concurrentMap {
                try AbsolutePath(
                    validating: $0,
                    relativeTo: path
                )
            }

            guard appPaths.allSatisfy({ $0.extension == "apk" }) else {
                throw ShareCommandServiceError.appleBuildsSharingNotSupportedOnLinux
            }

            try await shareAPK(
                appPaths,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json,
                track: track
            )
        }
    #endif

    // MARK: - Cross-platform APK sharing

    private func shareAPK(
        _ appPaths: [AbsolutePath],
        path: AbsolutePath,
        fullHandle: String,
        serverURL: URL,
        json: Bool,
        track: String?
    ) async throws {
        guard appPaths.count == 1,
              let apkPath = appPaths.first
        else { throw ShareCommandServiceError.multipleAppsSpecified(appPaths.map(\.pathString)) }

        let metadata = try await apkMetadataService.parseMetadata(at: apkPath)

        let gitInfo = resolveGitInfo(at: path)

        let preview = try await Noora.current.progressBarStep(
            message: "Uploading \(metadata.displayName)",
            successMessage: "\(metadata.displayName) uploaded",
            errorMessage: "Failed to upload \(metadata.displayName)"
        ) { updateProgress in
            try await previewsUploadService.uploadPreview(
                .apk(path: apkPath, metadata: metadata),
                fullHandle: fullHandle,
                serverURL: serverURL,
                gitBranch: gitInfo.branch,
                gitCommitSHA: gitInfo.sha,
                gitRef: gitInfo.ref,
                track: track,
                updateProgress: updateProgress
            )
        }

        outputResult(preview, displayName: metadata.displayName, json: json)
    }

    private func resolveGitInfo(at path: AbsolutePath) -> GitInfo {
        (try? gitController.gitInfo(workingDirectory: path)) ?? GitInfo(
            ref: nil,
            branch: nil,
            sha: nil,
            remoteURLOrigin: nil
        )
    }

    // MARK: - macOS-only Apple sharing

    #if os(macOS)
        private func shareIPA(
            _ appPaths: [AbsolutePath],
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            json: Bool,
            track: String?
        ) async throws {
            guard appPaths.count == 1,
                  let ipaPath = appPaths.first
            else { throw ShareCommandServiceError.multipleAppsSpecified(appPaths.map(\.pathString)) }

            let appBundle = try await appBundleLoader.load(ipa: ipaPath)
            let displayName = appBundle.infoPlist.name

            let preview = try await uploadApplePreviewType(
                .ipa(appBundle),
                displayName: displayName,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                track: track
            )

            outputResult(preview, displayName: displayName, json: json)
        }

        private func shareAppBundles(
            _ appPaths: [AbsolutePath],
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            json: Bool,
            track: String?
        ) async throws {
            let appBundles = try await appPaths.concurrentMap {
                try await appBundleLoader.load($0)
            }

            let appNames = appBundles.map(\.infoPlist.name).uniqued()
            guard appNames.count == 1,
                  let appName = appNames.first,
                  appPaths.allSatisfy({ $0.extension == "app" })
            else { throw ShareCommandServiceError.multipleAppsSpecified(appNames) }

            let preview = try await uploadApplePreviewType(
                .appBundles(appBundles),
                displayName: appName,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                track: track
            )

            outputResult(preview, displayName: appName, json: json)
        }

        private func copyAppBundle(
            _ builtAppBundle: BuiltAppBundle,
            app: String,
            configuration: String,
            temporaryPath: AbsolutePath
        ) async throws -> AbsolutePath {
            let newAppPath = temporaryPath.appending(
                component:
                "\(builtAppBundle.destinationType.buildProductDestinationPathComponent(for: configuration))-\(app).app"
            )

            try await fileSystem.copy(builtAppBundle.path, to: newAppPath)

            return newAppPath
        }

        private func uploadApplePreview(
            for platforms: [Platform],
            workspacePath: AbsolutePath,
            configuration: String,
            app: String,
            derivedDataPath: AbsolutePath?,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            json: Bool,
            track: String?
        ) async throws {
            try await fileSystem.runInTemporaryDirectory(prefix: "share") { temporaryPath in
                let builtAppBundles = try await builtAppBundleLocator.locateBuiltAppBundles(
                    app: app,
                    projectPath: workspacePath,
                    derivedDataPath: derivedDataPath,
                    configuration: configuration,
                    platforms: platforms
                )

                if builtAppBundles.isEmpty {
                    throw AppBundlePathResolverError.noAppsFound(app: app, configuration: configuration)
                }

                let appPaths = try await builtAppBundles.concurrentMap {
                    try await copyAppBundle(
                        $0,
                        app: app,
                        configuration: configuration,
                        temporaryPath: temporaryPath
                    )
                }
                .uniqued()

                let appBundles = try await appPaths.concurrentMap {
                    try await appBundleLoader.load($0)
                }

                let preview = try await uploadApplePreviewType(
                    .appBundles(appBundles),
                    displayName: app,
                    path: path,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    track: track
                )

                outputResult(preview, displayName: app, json: json)
            }
        }

        private func uploadApplePreviewType(
            _ previewUploadType: PreviewUploadType,
            displayName: String,
            path: AbsolutePath,
            fullHandle: String,
            serverURL: URL,
            track: String?
        ) async throws -> Components.Schemas.Preview {
            let gitInfo = resolveGitInfo(at: path)

            return try await Noora.current.progressBarStep(
                message: "Uploading \(displayName)",
                successMessage: "\(displayName) uploaded",
                errorMessage: "Failed to upload \(displayName)"
            ) { updateProgress in
                try await previewsUploadService.uploadPreview(
                    previewUploadType,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    gitBranch: gitInfo.branch,
                    gitCommitSHA: gitInfo.sha,
                    gitRef: gitInfo.ref,
                    track: track,
                    updateProgress: updateProgress
                )
            }
        }
    #endif

    // MARK: - Helpers

    private func outputResult(_ preview: Components.Schemas.Preview, displayName: String, json: Bool) {
        AlertController.current
            .success(
                .alert(
                    "Share \(displayName) with others using the following link: \(preview.url)"
                )
            )

        #if os(macOS)
            Task {
                await RunMetadataStorage.current.update(previewId: preview.id)
            }
        #endif

        if json {
            if let previewJSON = try? preview.toJSON() {
                Logger.current.info(
                    .init(
                        stringLiteral: previewJSON.toString(prettyPrint: true)
                    ),
                    metadata: .json
                )
            }
        }
    }
}
