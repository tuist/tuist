import Foundation
import Logging
import Path
import ServiceContextModule
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistServer
import TuistSupport

final class GenerateService {
    private let opener: Opening
    private let clock: Clock
    private let timeTakenLoggerFormatter: TimeTakenLoggerFormatting
    private let cacheStorageFactory: CacheStorageFactorying
    private let generatorFactory: GeneratorFactorying
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading

    init(
        cacheStorageFactory: CacheStorageFactorying,
        generatorFactory: GeneratorFactorying,
        clock: Clock = WallClock(),
        timeTakenLoggerFormatter: TimeTakenLoggerFormatting = TimeTakenLoggerFormatter(),
        opener: Opening = Opener(),
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader())
    ) {
        self.generatorFactory = generatorFactory
        self.cacheStorageFactory = cacheStorageFactory
        self.clock = clock
        self.timeTakenLoggerFormatter = timeTakenLoggerFormatter
        self.opener = opener
        self.pluginService = pluginService
        self.configLoader = configLoader
    }

    func run(
        path: String?,
        sources: Set<String>,
        noOpen: Bool,
        configuration: String?,
        ignoreBinaryCache: Bool
    ) async throws {
        let timer = clock.startTimer()
        let path = try self.path(path)
        let config = try await configLoader.loadConfig(path: path)
        let cacheStorage = try await cacheStorageFactory.cacheStorage(config: config)
        let generator = generatorFactory.generation(
            config: config,
            sources: sources,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            cacheStorage: cacheStorage
        )

        // Load the graph first to get the total number of projects
        let graph = try await generator.load(path: path)
        let totalProjects = graph.projects.count

        // Generate the project with progress bar
        let (workspacePath, _, _) = try await ServiceContext.current!.ui!.progressBarStep(
            message: "Generating projects",
            successMessage: "Projects generated",
            errorMessage: "Failed to generate projects"
        ) { updateProgress in
            var generatedProjects = 0

            // Create a progress logger that wraps the current logger's handler
            let progressLogger = ProgressLogger(
                handler: ServiceContext.current!.logger!.handler,
                onLog: { _ in
                    generatedProjects += 1
                    updateProgress(Double(generatedProjects) / Double(totalProjects))
                }
            )

            // Create a new logger with our progress logger as the handler
            let logger = Logger(label: ServiceContext.current!.logger!.label, factory: { _ in progressLogger })

            // Create a new context with our logger
            var context = ServiceContext.current!
            context.logger = logger

            // Run the generation in the new context
            return try await ServiceContext.withValue(context) {
                try await generator.generateWithGraph(path: path)
            }
        }

        if !noOpen {
            try await opener.open(path: workspacePath)
        }
        ServiceContext.current?.alerts?.success(.alert("Project generated."))
        ServiceContext.current?.logger?.notice(timeTakenLoggerFormatter.timeTakenMessage(for: timer))
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}

// MARK: - Progress Logger

private class ProgressLogger: LogHandler {
    private let onLog: (String) -> Void
    private var _logLevel: Logger.Level
    private var _metadata: Logger.Metadata

    init(handler: LogHandler, onLog: @escaping (String) -> Void) {
        self.onLog = onLog
        _logLevel = handler.logLevel
        _metadata = handler.metadata
    }

    var logLevel: Logger.Level {
        get { _logLevel }
        set { _logLevel = newValue }
    }

    var metadata: Logger.Metadata {
        get { _metadata }
        set { _metadata = newValue }
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { _metadata[key] }
        set { _metadata[key] = newValue }
    }

    func log(
        level _: Logger.Level,
        message: Logger.Message,
        metadata _: Logger.Metadata?,
        source _: String,
        file _: String,
        function _: String,
        line _: UInt
    ) {
        onLog(message.description)
    }
}
