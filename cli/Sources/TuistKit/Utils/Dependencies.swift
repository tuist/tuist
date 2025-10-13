import Foundation
import Noora
import Path
import TSCBasic
import TuistServer
import TuistSupport
#if canImport(TuistCacheEE)
    import TuistCacheEE
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

struct IgnoreOutputPipeline: StandardPipelining {
    func write(content _: String) {}
}

public func initDependencies(_ action: (Path.AbsolutePath) async throws -> Void) async throws {
    try await initEnv()

    let (logger, logFilePath) = try await initLogger()

    try await withAdditionalMiddlewares {
        try await ServerAuthenticationConfig.$current.withValue(ServerAuthenticationConfig(backgroundRefresh: true)) {
            try await Noora.$current.withValue(initNoora()) {
                try await Logger.$current.withValue(logger) {
                    try await ServerCredentialsStore.$current.withValue(ServerCredentialsStore(backend: .fileSystem)) {
                        try await CachedValueStore.$current.withValue(CachedValueStore(backend: .fileSystem)) {
                            try await RecentPathsStore.$current
                                .withValue(RecentPathsStore(storageDirectory: Environment.current.stateDirectory)) {
                                    try await action(logFilePath)
                                }
                        }
                    }
                }
            }
        }
    }
}

public func withAdditionalMiddlewares(_ action: () async throws -> Void) async throws {
    #if canImport(TuistCacheEE)
        try await Client.$additionalMiddlewares.withValue([SignatureVerifierMiddleware()]) {
            try await action()
        }
    #else
        try await action()
    #endif
}

private func initEnv() async throws {
    if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--verbose") {
        throw DependenciesError.exclusiveOptionError("quiet", "verbose")
    }

    if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--json") {
        throw DependenciesError.exclusiveOptionError("quiet", "json")
    }

    if CommandLine.arguments.contains("--verbose") {
        try? ProcessEnv.setVar("TUIST_CONFIG_VERBOSE", value: "true")
    }

    if CommandLine.arguments.contains("--quiet") {
        try? ProcessEnv.setVar(Constants.EnvironmentVariables.quiet, value: "true")
    }
}

func withLoggerForNoora(logFilePath: Path.AbsolutePath, _ action: () async throws -> Void) async throws {
    let loggerHandler = try Logger.loggerHandlerForNoora(logFilePath: logFilePath)
    try await Logger.$current.withValue(Logger(label: "dev.tuist.cli", factory: loggerHandler)) {
        try await action()
    }
}

private func initLogger() async throws -> (Logger, Path.AbsolutePath) {
    let (loggerHandler, logFilePath) = try await LogsController().setup(
        stateDirectory: Environment.current.stateDirectory
    )
    // This is the old initialization method and will eventually go away.
    LoggingSystem.bootstrap(loggerHandler)
    return (Logger(label: "dev.tuist.cli", factory: loggerHandler), logFilePath)
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
