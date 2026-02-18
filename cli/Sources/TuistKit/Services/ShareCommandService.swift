import Command
import FileSystem
import Foundation
import TuistEnvironment
import Noora
import Path
import TuistAlert
import TuistAutomation
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEncodable
import TuistLoader
import TuistLogging
import TuistServer
import TuistSimulator
import TuistSupport
import TuistUserInputReader
import XcodeGraph

enum ShareCommandServiceError: Equatable, LocalizedError {
    case projectOrWorkspaceNotFound(path: String)
    case noAppsFound(app: String, configuration: String)
    case appNotSpecified
    case multipleAppsSpecified([String])
    case platformsNotSpecified
    case fullHandleNotFound
    case aapt2NotFound
    case aapt2ParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .projectOrWorkspaceNotFound(path):
            return "Workspace or project not found at \(path)"
        case let .noAppsFound(app: app, configuration: configuration):
            return "\(app) for the \(configuration) configuration was not found. You can build it by running `tuist build \(app)`"
        case .appNotSpecified:
            return "If you're not using Tuist projects, you must specify the app name when sharing an app, such as `tuist share App --platforms ios`."
        case .platformsNotSpecified:
            return "If you're not using Tuist projects, you must specify the platforms when sharing an app, such as `tuist share App --platforms ios`."
        case let .multipleAppsSpecified(apps):
            return "You specified multiple apps to share: \(apps.joined(separator: " ")). You cannot specify multiple apps when using `tuist share`."
        case .fullHandleNotFound:
            return "You are missing fullHandle in your \(Constants.tuistManifestFileName). Run 'tuist init' to get started with remote Tuist features."
        case .aapt2NotFound:
            return "aapt2 is required to share APK files. Install it via the Android SDK (build-tools) and ensure ANDROID_HOME or ANDROID_SDK_ROOT is set, or that aapt2 is in your PATH."
        case let .aapt2ParsingFailed(path):
            return "Failed to parse APK metadata from \(path). Ensure the file is a valid APK."
        }
    }
}

// swiftlint:disable:next type_body_length
struct ShareCommandService {
    private let fileHandler: FileHandling
    private let fileSystem: FileSysteming
    private let xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating
    private let buildGraphInspector: BuildGraphInspecting
    private let previewsUploadService: PreviewsUploadServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let manifestLoader: ManifestLoading
    private let manifestGraphLoader: ManifestGraphLoading
    private let userInputReader: UserInputReading
    private let defaultConfigurationFetcher: DefaultConfigurationFetching
    private let appBundleLoader: AppBundleLoading
    private let fileArchiverFactory: FileArchivingFactorying

    init() {
        let manifestLoader = ManifestLoader.current
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )

        self.init(
            fileHandler: FileHandler.shared,
            fileSystem: FileSystem(),
            xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocator(),
            buildGraphInspector: BuildGraphInspector(),
            previewsUploadService: PreviewsUploadService(),
            configLoader: ConfigLoader(),
            serverEnvironmentService: ServerEnvironmentService(),
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader,
            userInputReader: UserInputReader(),
            defaultConfigurationFetcher: DefaultConfigurationFetcher(),
            appBundleLoader: AppBundleLoader(),
            fileArchiverFactory: FileArchivingFactory()
        )
    }

    init(
        fileHandler: FileHandling,
        fileSystem: FileSysteming,
        xcodeProjectBuildDirectoryLocator: XcodeProjectBuildDirectoryLocating,
        buildGraphInspector: BuildGraphInspecting,
        previewsUploadService: PreviewsUploadServicing,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing,
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading,
        userInputReader: UserInputReading,
        defaultConfigurationFetcher: DefaultConfigurationFetching,
        appBundleLoader: AppBundleLoading,
        fileArchiverFactory: FileArchivingFactorying
    ) {
        self.fileHandler = fileHandler
        self.fileSystem = fileSystem
        self.xcodeProjectBuildDirectoryLocator = xcodeProjectBuildDirectoryLocator
        self.buildGraphInspector = buildGraphInspector
        self.previewsUploadService = previewsUploadService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.manifestLoader = manifestLoader
        self.manifestGraphLoader = manifestGraphLoader
        self.userInputReader = userInputReader
        self.defaultConfigurationFetcher = defaultConfigurationFetcher
        self.appBundleLoader = appBundleLoader
        self.fileArchiverFactory = fileArchiverFactory
    }

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
        let path = try self.path(path)

        let config = try await configLoader.loadConfig(path: path)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let fullHandle = config.fullHandle else {
            throw ShareCommandServiceError.fullHandleNotFound
        }

        let derivedDataPath = try derivedDataPath.map {
            try AbsolutePath(
                validating: $0,
                relativeTo: fileHandler.currentPath
            )
        }

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
        } else if try await manifestLoader.hasRootManifest(at: path) {
            guard apps.count < 2 else { throw ShareCommandServiceError.multipleAppsSpecified(apps) }

            let (graph, _, _, _) = try await manifestGraphLoader.load(
                path: path,
                disableSandbox: config.project.disableSandbox
            )
            let graphTraverser = GraphTraverser(graph: graph)
            let shareableTargets =
                graphTraverser
                    .targets(product: .app)
                    .union(graphTraverser.targets(product: .appClip))
                    .union(graphTraverser.targets(product: .watch2App))
                    .map { $0 }
                    .filter {
                        if let app = apps.first {
                            return $0.target.name == app
                        } else {
                            return true
                        }
                    }
            let appTarget: GraphTarget = try userInputReader.readValue(
                asking: "Select the app that you want to share:",
                values: shareableTargets.sorted(by: { $0.target.name < $1.target.name }),
                valueDescription: \.target.name
            )

            let configuration = try defaultConfigurationFetcher.fetch(
                configuration: configuration,
                defaultConfiguration: config.project.generatedProject?.generationOptions
                    .defaultConfiguration,
                graph: graph
            )

            let platforms =
                platforms.isEmpty ? appTarget.target.supportedPlatforms.map { $0 } : platforms

            try await uploadPreview(
                for: platforms,
                workspacePath: graph.workspace.xcWorkspacePath,
                configuration: configuration,
                app: appTarget.target.productName,
                derivedDataPath: derivedDataPath,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json,
                track: track
            )
        } else {
            guard !apps.isEmpty else { throw ShareCommandServiceError.appNotSpecified }
            guard apps.count == 1, let app = apps.first else {
                throw ShareCommandServiceError.multipleAppsSpecified(apps)
            }
            guard !platforms.isEmpty else { throw ShareCommandServiceError.platformsNotSpecified }

            let configuration = configuration ?? BuildConfiguration.debug.name

            let workspace = try await fileSystem.glob(directory: path, include: ["*.xcworkspace"])
                .collect().first
            let project = try await fileSystem.glob(directory: path, include: ["*.xcodeproj"])
                .collect().first
            guard let workspaceOrProjectPath = workspace ?? project
            else {
                throw ShareCommandServiceError.projectOrWorkspaceNotFound(path: path.pathString)
            }

            try await uploadPreview(
                for: platforms,
                workspacePath: workspaceOrProjectPath,
                configuration: configuration,
                app: app,
                derivedDataPath: derivedDataPath,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json,
                track: track
            )
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

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

        try await uploadPreview(
            .ipa(appBundle),
            displayName: displayName,
            path: path,
            fullHandle: fullHandle,
            serverURL: serverURL,
            json: json,
            track: track
        )
    }

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

        let metadata = try await parseAPKMetadata(at: apkPath)

        try await uploadPreview(
            .apk(path: apkPath, metadata: metadata),
            displayName: metadata.displayName,
            path: path,
            fullHandle: fullHandle,
            serverURL: serverURL,
            json: json,
            track: track
        )
    }

    private func resolveAapt2Path() async throws -> String {
        var candidateRoots: [String] = []

        let variables = Environment.current.variables
        for envVar in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let value = variables[envVar], !value.isEmpty {
                candidateRoots.append(value)
            }
        }

        let home = FileHandler.shared.homeDirectory.pathString
        candidateRoots.append(contentsOf: [
            "\(home)/.local/share/mise/installs/android-sdk/1.0",
            "\(home)/Library/Android/sdk",
            "/opt/homebrew/share/android-commandlinetools",
            "/usr/local/share/android-commandlinetools",
        ])

        for root in candidateRoots {
            let buildToolsDir: AbsolutePath
            do {
                buildToolsDir = try AbsolutePath(validating: root).appending(component: "build-tools")
            } catch { continue }
            guard await (try? fileSystem.exists(buildToolsDir)) == true else { continue }
            let aapt2Paths = try await fileSystem.glob(directory: buildToolsDir, include: ["*/aapt2"]).collect()
            if let aapt2 = aapt2Paths.sorted(by: { $0.pathString > $1.pathString }).first {
                return aapt2.pathString
            }
        }
        return "aapt2"
    }

    private func parseAPKMetadata(at apkPath: AbsolutePath) async throws -> APKMetadata {
        let commandRunner = CommandRunner()
        let aapt2 = try await resolveAapt2Path()

        let output: String
        do {
            output = try await commandRunner
                .run(arguments: [aapt2, "dump", "badging", apkPath.pathString])
                .concatenatedString()
        } catch {
            throw ShareCommandServiceError.aapt2NotFound
        }

        var packageName: String?
        var versionName: String?
        var versionCode: String?
        var applicationLabel: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("package:") {
                packageName = extractValue(from: line, key: "name")
                versionCode = extractValue(from: line, key: "versionCode")
                versionName = extractValue(from: line, key: "versionName")
            } else if line.hasPrefix("application-label:") {
                applicationLabel = line
                    .replacingOccurrences(of: "application-label:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            }
        }

        guard let packageName, let versionName, let versionCode else {
            throw ShareCommandServiceError.aapt2ParsingFailed(apkPath.pathString)
        }

        return APKMetadata(
            packageName: packageName,
            versionName: versionName,
            versionCode: versionCode,
            displayName: applicationLabel ?? apkPath.basenameWithoutExt
        )
    }

    private func extractValue(from line: String, key: String) -> String? {
        guard let range = line.range(of: "\(key)='") else { return nil }
        let start = range.upperBound
        guard let end = line[start...].firstIndex(of: "'") else { return nil }
        return String(line[start ..< end])
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

        try await uploadPreview(
            .appBundles(appBundles),
            displayName: appName,
            path: path,
            fullHandle: fullHandle,
            serverURL: serverURL,
            json: json,
            track: track
        )
    }

    private func copyAppBundle(
        for destinationType: DestinationType,
        app: String,
        projectPath: AbsolutePath,
        derivedDataPath: AbsolutePath?,
        configuration: String,
        temporaryPath: AbsolutePath
    ) async throws -> AbsolutePath? {
        let appPath = try await xcodeProjectBuildDirectoryLocator.locate(
            destinationType: destinationType,
            projectPath: projectPath,
            derivedDataPath: derivedDataPath,
            configuration: configuration
        )
        .appending(component: "\(app).app")

        let newAppPath = temporaryPath.appending(
            component:
            "\(destinationType.buildProductDestinationPathComponent(for: configuration))-\(app).app"
        )

        if try await !fileSystem.exists(appPath) {
            return nil
        }

        try await fileSystem.copy(appPath, to: newAppPath)

        return newAppPath
    }

    private func uploadPreview(
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
        try await fileHandler.inTemporaryDirectory { temporaryPath in
            let appPaths =
                try await platforms
                    .concurrentFlatMap { platform -> [DestinationType] in
                        switch platform {
                        case .iOS, .tvOS, .visionOS, .watchOS:
                            return [
                                .simulator(platform),
                                .device(platform),
                            ]
                        case .macOS:
                            return [.device(platform)]
                        }
                    }
                    .concurrentCompactMap { destinationType in
                        try await copyAppBundle(
                            for: destinationType,
                            app: app,
                            projectPath: workspacePath,
                            derivedDataPath: derivedDataPath,
                            configuration: configuration,
                            temporaryPath: temporaryPath
                        )
                    }
                    .uniqued()

            let appBundles = try await appPaths.concurrentMap {
                try await appBundleLoader.load($0)
            }

            if appPaths.isEmpty {
                throw ShareCommandServiceError.noAppsFound(app: app, configuration: configuration)
            }

            try await uploadPreview(
                .appBundles(appBundles),
                displayName: app,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                json: json,
                track: track
            )
        }
    }

    private func uploadPreview(
        _ previewUploadType: PreviewUploadType,
        displayName: String,
        path: AbsolutePath,
        fullHandle: String,
        serverURL: URL,
        json: Bool,
        track: String?
    ) async throws {
        let preview = try await Noora.current.progressBarStep(
            message: "Uploading \(displayName)",
            successMessage: "\(displayName) uploaded",
            errorMessage: "Failed to upload \(displayName)"
        ) { updateProgress in
            try await previewsUploadService.uploadPreview(
                previewUploadType,
                path: path,
                fullHandle: fullHandle,
                serverURL: serverURL,
                track: track,
                updateProgress: updateProgress
            )
        }

        AlertController.current
            .success(
                .alert(
                    "Share \(displayName) with others using the following link: \(preview.url.absoluteString)"
                )
            )

        await RunMetadataStorage.current.update(previewId: preview.id)

        if json {
            let previewJSON = try preview.toJSON()
            Logger.current.info(
                .init(
                    stringLiteral: previewJSON.toString(prettyPrint: true)
                ),
                metadata: .json
            )
        }
    }
}
