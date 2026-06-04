import Foundation
import Path
import TuistAlert
import TuistCache
import TuistConfig
import TuistConfigLoader
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
    private let outdatedDependenciesChecker: OutdatedDependenciesChecking
    private let generationMetadataStore: GenerationMetadataStoring

    public init(
        cacheStorageFactory: CacheStorageFactorying,
        generatorFactory: GeneratorFactorying,
        clock: Clock = WallClock(),
        timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
        opener: Opening = Opener(),
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(),
        generationMetadataStore: GenerationMetadataStoring = GenerationMetadataStore()
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
            outdatedDependenciesChecker: OutdatedDependenciesChecker(),
            generationMetadataStore: generationMetadataStore
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
        outdatedDependenciesChecker: OutdatedDependenciesChecking,
        generationMetadataStore: GenerationMetadataStoring = GenerationMetadataStore()
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.clock = clock
        self.timeTakenLoggerFormatter = timeTakenLoggerFormatter
        self.opener = opener
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.installService = installService
        self.outdatedDependenciesChecker = outdatedDependenciesChecker
        self.generationMetadataStore = generationMetadataStore
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
           try await outdatedDependenciesChecker.packageDependenciesAreOutdated(at: path)
        {
            switch generatedProject.generationOptions.onOutdatedDependencies {
            case .warn:
                AlertController.current.warning(.alert(
                    "We detected outdated dependencies.",
                    takeaway: "Run \(.command("tuist install")) to update them."
                ))
            case .install:
                Logger.current.notice("Outdated dependencies detected. Running `tuist install`.", metadata: .section)
                try await installService.run(
                    path: path.pathString,
                    update: false,
                    passthroughArguments: []
                )
            case .fail:
                throw GenerateServiceError.outdatedDependencies
            }
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
        await persistGenerationMetadata(workspacePath: workspacePath)
        if !noOpen {
            try await opener.open(path: workspacePath)
        }
        AlertController.current.success(.alert("Project generated."))
        Logger.current.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
    }

    // MARK: - Helpers

    /// Mints a generation identifier, records it on the run so the generate command event carries it
    /// alongside the uploaded graph, and persists it keyed by the generated workspace so a later
    /// `tuist inspect build` can link a local Xcode build back to this generation's module breakdown.
    private func persistGenerationMetadata(workspacePath: AbsolutePath) async {
        let generationId = UUID().uuidString.lowercased()
        await RunMetadataStorage.current.update(generationId: generationId)
        do {
            // Keyed by the generated workspace. The build side resolves the same workspace before
            // reading (see UploadBuildRunService), so this single key matches every build entry point.
            try await generationMetadataStore.store(generationId: generationId, for: workspacePath)
            try await generationMetadataStore.prune()
        } catch {
            Logger.current.debug("Failed to persist generation metadata: \(error.localizedDescription)")
        }
    }

    private func path(_ path: String?) async throws -> AbsolutePath {
        try await Environment.current.pathRelativeToWorkingDirectory(path)
    }
}

enum GenerateServiceError: FatalError, Equatable {
    case outdatedDependencies

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case .outdatedDependencies:
            return "Outdated dependencies detected. Run `tuist install` to update them."
        }
    }
}
