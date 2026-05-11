import FileSystem
import Foundation
import Path
import TuistAlert
import TuistCache
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistGenerator
import TuistLoader
import TuistLogging
import TuistOpener
import TuistPlugin
import TuistServer
import TuistSupport

#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

public struct GenerateService {
    private let opener: Opening
    private let clock: Clock
    private let timeTakenLoggerFormatter: TimeTakenLoggerFormatting
    private let cacheStorageFactory: CacheStorageFactorying
    private let generatorFactory: GeneratorFactorying
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let installService: InstallServicing
    private let manifestFilesLocator: ManifestFilesLocating
    private let fileSystem: FileSysteming

    public init(
        cacheStorageFactory: CacheStorageFactorying,
        generatorFactory: GeneratorFactorying,
        clock: Clock = WallClock(),
        timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
        opener: Opening = Opener(),
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.init(
            cacheStorageFactory: cacheStorageFactory,
            generatorFactory: generatorFactory,
            clock: clock,
            timeTakenLoggerFormatter: timeTakenLoggerFormatter,
            opener: opener,
            pluginService: pluginService,
            configLoader: configLoader,
            installService: InstallService(),
            manifestFilesLocator: ManifestFilesLocator(),
            fileSystem: FileSystem()
        )
    }

    init(
        cacheStorageFactory: CacheStorageFactorying,
        generatorFactory: GeneratorFactorying,
        clock: Clock = WallClock(),
        timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
        opener: Opening = Opener(),
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(),
        installService: InstallServicing,
        manifestFilesLocator: ManifestFilesLocating,
        fileSystem: FileSysteming
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.clock = clock
        self.timeTakenLoggerFormatter = timeTakenLoggerFormatter
        self.opener = opener
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.installService = installService
        self.manifestFilesLocator = manifestFilesLocator
        self.fileSystem = fileSystem
    }

    public func run(
        path: String?,
        includedTargets: Set<TargetQuery>,
        noOpen: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool,
        cacheProfile: CacheProfileType?
    ) async throws {
        let timer = clock.startTimer()
        let path = try await self.path(path)

        #if canImport(TuistCacheEE)
            Task.detached(priority: .background) {
                let cacheLocalStorage = CacheLocalStorage(cacheDirectoriesProvider: CacheDirectoriesProvider())
                try? await cacheLocalStorage.clean()
            }
        #endif

        let config = try await configLoader.loadConfig(path: path)
            .assertingIsGeneratedProjectOrSwiftPackage(
                errorMessageOverride:
                "The 'tuist generate' command is only available for generated projects and Swift packages."
            )

        if let generatedProject = config.project.generatedProject,
           generatedProject.generationOptions.autoInstallOutdatedDependencies,
           try await packageDependenciesAreOutdated(at: path)
        {
            Logger.current.notice("Outdated dependencies detected. Running `tuist install`.", metadata: .section)
            try await installService.run(
                path: path.pathString,
                update: false,
                passthroughArguments: []
            )
        }

        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)

        let resolvedCacheProfile = try config.resolveCacheProfile(
            ignoreBinaryCache: ignoreBinaryCache,
            includedTargets: includedTargets,
            cacheProfile: cacheProfile
        )

        let generator = generatorFactory.generation(
            config: config,
            includedTargets: includedTargets,
            configuration: configuration,
            cacheProfile: resolvedCacheProfile,
            cacheStorage: cacheStorage
        )
        let (workspacePath, _, _) = try await generator.generateWithGraph(
            path: path,
            options: config.project.generatedProject?.generationOptions
        )
        if !noOpen {
            try await opener.open(path: workspacePath)
        }
        AlertController.current.success(.alert("Project generated."))
        Logger.current.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
    }

    // MARK: - Helpers

    private func path(_ path: String?) async throws -> AbsolutePath {
        try await Environment.current.pathRelativeToWorkingDirectory(path)
    }

    private func packageDependenciesAreOutdated(at path: AbsolutePath) async throws -> Bool {
        guard let packageManifestPath = try await manifestFilesLocator.locatePackageManifest(at: path) else {
            return false
        }

        let packageDirectory = packageManifestPath.parentDirectory
        let currentPackageResolvedPath = packageDirectory
            .appending(component: Constants.SwiftPackageManager.packageResolvedName)
        let savedPackageResolvedPath = packageDirectory.appending(components: [
            Constants.SwiftPackageManager.packageBuildDirectoryName,
            Constants.DerivedDirectory.name,
            Constants.SwiftPackageManager.packageResolvedName,
        ])

        var currentData: Data?
        if try await fileSystem.exists(currentPackageResolvedPath) {
            currentData = try await fileSystem.readFile(at: currentPackageResolvedPath)
        }

        var savedData: Data?
        if try await fileSystem.exists(savedPackageResolvedPath) {
            savedData = try await fileSystem.readFile(at: savedPackageResolvedPath)
        }

        return currentData != savedData
    }
}
