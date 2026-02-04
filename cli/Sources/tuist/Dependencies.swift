import Foundation
import Logging
import Noora
import Path
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistNooraExtension
import TuistServer

#if os(macOS)
    import TuistExtension
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

private func initLogger() async throws -> (Logger, AbsolutePath) {
    #if os(macOS)
        let machineReadableCommandNames = [DumpCommand.self].map(\._commandName)
    #else
        let machineReadableCommandNames: [String] = []
    #endif

    let (loggerHandler, logFilePath) = try await LogsController().setup(
        stateDirectory: Environment.current.stateDirectory,
        machineReadableCommandNames: machineReadableCommandNames
    )
    LoggingSystem.bootstrap(loggerHandler)
    return (Logger(label: "dev.tuist.cli", factory: loggerHandler), logFilePath)
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

func initDependencies(_ action: (AbsolutePath) async throws -> Void) async throws {
    try initEnv()

    let (logger, logFilePath) = try await initLogger()

    try await withPlatformDependencies {
        try await withSharedDependencies(logger: logger, logFilePath: logFilePath) {
            try await action(logFilePath)
        }
    }
}

private func withPlatformDependencies(_ action: () async throws -> Void) async throws {
    #if os(macOS)
        try await withAdditionalMiddlewares {
            try await withInitializedManifestLoader {
                try await RecentPathsStore.$current
                    .withValue(RecentPathsStore(storageDirectory: Environment.current.stateDirectory)) {
                        try await Extension.$hashCacheService
                            .withValue(HashCacheCommandService()) {
                                try await action()
                            }
                    }
            }
        }
    #else
        try await action()
    #endif
}

private func withSharedDependencies(
    logger: Logger,
    logFilePath _: AbsolutePath,
    _ action: () async throws -> Void
) async throws {
    try await ServerAuthenticationConfig.$current
        .withValue(ServerAuthenticationConfig(backgroundRefresh: true)) {
            try await Noora.$current.withValue(initNoora()) {
                try await Logger.$current.withValue(logger) {
                    try await ServerCredentialsStore.$current
                        .withValue(ServerCredentialsStore(
                            backend: .fileSystem,
                            configDirectory: Environment.current.configDirectory
                        )) {
                            try await CachedValueStore.$current
                                .withValue(CachedValueStore(backend: .fileSystem)) {
                                    try await action()
                                }
                        }
                }
            }
        }
}

func withLoggerForNoora(logFilePath: AbsolutePath, _ action: () async throws -> Void) async throws {
    let loggerHandler = try Logger.loggerHandlerForNoora(logFilePath: logFilePath)
    try await Logger.$current.withValue(Logger(label: "dev.tuist.cli", factory: loggerHandler)) {
        try await action()
    }
}

#if os(macOS)
    func withAdditionalMiddlewares(_ action: () async throws -> Void) async throws {
        #if canImport(TuistCacheEE)
            try await Client.$additionalMiddlewares.withValue([SignatureVerifierMiddleware()]) {
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
#endif
