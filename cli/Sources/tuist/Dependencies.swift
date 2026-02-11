import Foundation
import Noora
import Path
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistNooraExtension
import TuistServer

#if os(macOS)
    import FileSystem
    import TuistCore
    import TuistExtension
    import TuistHAR
    import TuistKit
    import TuistLoader
    import TuistSupport

    #if canImport(TuistCacheEE)
        import TuistCacheEE
    #endif
#endif

private enum DependenciesError: LocalizedError {
    case exclusiveOptionError(String, String)

    var errorDescription: String? {
        switch self {
        case let .exclusiveOptionError(option1, option2):
            "Cannot use --\(option1) and --\(option2) at the same time."
        }
    }
}

private func initEnv() throws {
    if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--verbose") {
        throw DependenciesError.exclusiveOptionError("quiet", "verbose")
    }

    if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--json") {
        throw DependenciesError.exclusiveOptionError("quiet", "json")
    }

    if CommandLine.arguments.contains("--verbose") {
        setenv("TUIST_CONFIG_VERBOSE", "true", 1)
    }

    if CommandLine.arguments.contains("--quiet") {
        setenv(Constants.EnvironmentVariables.quiet, "true", 1)
    }
}

struct IgnoreOutputPipeline: StandardPipelining {
    func write(content _: String) {}
}

func initNoora(jsonThroughNoora: Bool = false) -> Noora {
    if CommandLine.arguments.contains("--json") || CommandLine.arguments.contains("--quiet") {
        Noora(
            standardPipelines: jsonThroughNoora ? StandardPipelines() : StandardPipelines(
                output: IgnoreOutputPipeline()
            ),
            logger: Logger.current
        )
    } else {
        Noora(
            logger: Logger.current
        )
    }
}

#if os(macOS)
    func initDependencies(_ action: (SessionPaths) async throws -> Void) async throws {
        try initEnv()
        ThreadDumpSignalHandler.installIfEnabled()

        let sessionController = SessionController()
        let (loggerHandler, sessionPaths) = try await sessionController.setup(
            stateDirectory: Environment.current.stateDirectory
        )
        LoggingSystem.bootstrap(loggerHandler)
        sessionController.scheduleMaintenance(stateDirectory: Environment.current.stateDirectory)
        AnalyticsStateController().scheduleMaintenance(stateDirectory: Environment.current.stateDirectory)

        #if canImport(TuistCacheEE)
            Task.detached(priority: .background) {
                try? await CacheLocalStorage.clean(
                    fileSystem: FileSystem(),
                    cacheDirectoriesProvider: CacheDirectoriesProvider()
                )
            }
        #endif

        let logger = Logger(label: "dev.tuist.cli", factory: loggerHandler)
        let harRecorder = HARRecorder(filePath: sessionPaths.networkFilePath)

        try await withAdditionalMiddlewares {
            try await withInitializedManifestLoader {
                try await ServerAuthenticationConfig.$current.withValue(ServerAuthenticationConfig(backgroundRefresh: true)) {
                    try await Noora.$current.withValue(initNoora()) {
                        try await Logger.$current.withValue(logger) {
                            try await HARRecorder.$current.withValue(harRecorder) {
                                try await ServerCredentialsStore.$current
                                    .withValue(ServerCredentialsStore(backend: .fileSystem)) {
                                        try await CachedValueStore.$current.withValue(CachedValueStore(backend: .fileSystem)) {
                                            try await RecentPathsStore.$current
                                                .withValue(RecentPathsStore(storageDirectory: Environment.current
                                                        .stateDirectory))
                                                {
                                                    try await Extension.$hashCacheService
                                                        .withValue(HashCacheCommandService()) {
                                                            try await withCacheService {
                                                                try await action(sessionPaths)
                                                            }
                                                        }
                                                }
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    func withAdditionalMiddlewares(_ action: () async throws -> Void) async throws {
        #if canImport(TuistCacheEE)
            try await Client.$additionalMiddlewares.withValue([SignatureVerifierMiddleware()]) {
                try await action()
            }
        #else
            try await action()
        #endif
    }

    func withCacheService(_ action: () async throws -> Void) async throws {
        #if canImport(TuistCacheEE)
            try await Extension.$cacheService
                .withValue(CacheWarmCommandService()) {
                    try await action()
                }
        #else
            try await action()
        #endif
    }

    private func withInitializedManifestLoader(_ action: () async throws -> Void) async throws {
        let useCache = if Environment.current.variables[Constants.EnvironmentVariables.cacheManifests] != nil {
            Environment.current.isVariableTruthy(Constants.EnvironmentVariables.cacheManifests)
        } else {
            true
        }
        return try await ManifestLoader.$current.withValue(useCache ? CachedManifestLoader() : ManifestLoader()) {
            return try await action()
        }
    }

    func withLoggerForNoora(logFilePath: AbsolutePath, _ action: () async throws -> Void) async throws {
        let loggerHandler = try Logger.loggerHandlerForNoora(logFilePath: logFilePath)
        try await Logger.$current.withValue(Logger(label: "dev.tuist.cli", factory: loggerHandler)) {
            try await action()
        }
    }
#else
    /// Linux-specific initialization - simpler setup without macOS-specific features
    func initDependencies(_ action: (SessionPaths) async throws -> Void) async throws {
        try initEnv()

        let stateDirectory = Environment.current.stateDirectory
        let sessionId = UUID().uuidString
        let sessionDirectory = stateDirectory.appending(components: ["sessions", sessionId])
        let logFilePath = sessionDirectory.appending(component: "logs.txt")
        let networkFilePath = sessionDirectory.appending(component: "network.har")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: sessionDirectory.pathString) {
            try fileManager.createDirectory(atPath: sessionDirectory.pathString, withIntermediateDirectories: true)
        }
        fileManager.createFile(atPath: logFilePath.pathString, contents: nil)

        let sessionPaths = SessionPaths(
            sessionId: sessionId,
            sessionDirectory: sessionDirectory,
            logFilePath: logFilePath,
            networkFilePath: networkFilePath
        )

        let loggingConfig =
            if CommandLine.arguments.contains("--json") {
                LoggingConfig(
                    loggerType: .json,
                    verbose: Environment.current.isVerbose
                )
            } else {
                LoggingConfig.default()
            }

        let loggerHandler = try Logger.defaultLoggerHandler(config: loggingConfig, logFilePath: logFilePath)
        LoggingSystem.bootstrap(loggerHandler)
        let logger = Logger(label: "dev.tuist.cli", factory: loggerHandler)

        try await ServerAuthenticationConfig.$current.withValue(ServerAuthenticationConfig(backgroundRefresh: false)) {
            try await Noora.$current.withValue(initNoora()) {
                try await Logger.$current.withValue(logger) {
                    try await ServerCredentialsStore.$current
                        .withValue(
                            ServerCredentialsStore(
                                backend: .fileSystem,
                                configDirectory: Environment.current.configDirectory
                            )
                        ) {
                            try await CachedValueStore.$current.withValue(CachedValueStore(backend: .fileSystem)) {
                                try await action(sessionPaths)
                            }
                        }
                }
            }
        }
    }

    /// Session paths for Linux - simplified version without HAR recording
    public struct SessionPaths: Sendable {
        public let sessionId: String
        public let sessionDirectory: AbsolutePath
        public let logFilePath: AbsolutePath
        public let networkFilePath: AbsolutePath

        public init(
            sessionId: String,
            sessionDirectory: AbsolutePath,
            logFilePath: AbsolutePath,
            networkFilePath: AbsolutePath
        ) {
            self.sessionId = sessionId
            self.sessionDirectory = sessionDirectory
            self.logFilePath = logFilePath
            self.networkFilePath = networkFilePath
        }
    }

    func withLoggerForNoora(logFilePath: AbsolutePath, _ action: () async throws -> Void) async throws {
        let loggerHandler = try Logger.loggerHandlerForNoora(logFilePath: logFilePath)
        try await Logger.$current.withValue(Logger(label: "dev.tuist.cli", factory: loggerHandler)) {
            try await action()
        }
    }
#endif
