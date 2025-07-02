import FileLogging
@_exported import Logging
import LoggingOSLog
import Path

import class Foundation.ProcessInfo

extension Logger {
    @TaskLocal public static var current: Logger = .init(label: "dev.tuist.logger")
}

public struct LoggingConfig {
    public init(loggerType: LoggerType, verbose: Bool) {
        self.loggerType = loggerType
        self.verbose = verbose
    }

    public enum LoggerType {
        case console
        case detailed
        case osLog
        case json
        case quiet
    }

    public var loggerType: LoggerType
    public var verbose: Bool
}

extension Logger {
    public static func loggerHandlerForNoora(logFilePath: AbsolutePath) throws -> @Sendable (String) -> any LogHandler {
        let fileLogger = try FileLogging(to: logFilePath.url)
        return { label in
            var fileLogHandler = FileLogHandler(label: label, fileLogger: fileLogger)
            fileLogHandler.logLevel = .debug
            var loggers: [any LogHandler] = [fileLogHandler]
            loggers.append(OSLogHandler.verbose(label: label))
            return MultiplexLogHandler(loggers)
        }
    }

    public static func defaultLoggerHandler(
        config: LoggingConfig,
        logFilePath: AbsolutePath
    ) throws -> @Sendable (String) -> any LogHandler {
        let handler: VerboseLogHandler.Type

        switch config.loggerType {
        case .osLog:
            handler = OSLogHandler.self
        case .detailed:
            handler = DetailedLogHandler.self
        case .console:
            handler = StandardLogHandler.self
        case .json:
            handler = JSONLogHandler.self
        case .quiet:
            return quietLogHandler
        }

        let fileLogger = try FileLogging(to: logFilePath.url)

        let baseLoggers = { (label: String) -> [any LogHandler] in
            var fileLogHandler = FileLogHandler(label: label, fileLogger: fileLogger)
            fileLogHandler.logLevel = .debug

            var loggers: [any LogHandler] = [fileLogHandler]
            // OSLog is not needed in development.
            // If we include it, the Xcode console will show duplicated logs, making it harder for contributors to debug the
            // execution
            // within Xcode.
            // When run directly from a terminal, logs are not duplicated.
            #if RELEASE
                loggers.append(LoggingOSLog(label: label))
            #endif
            return loggers
        }
        if config.verbose {
            return { label in
                var loggers = baseLoggers(label)
                loggers.append(handler.verbose(label: label))
                return MultiplexLogHandler(loggers)
            }
        } else {
            return { label in
                var loggers = baseLoggers(label)
                loggers.append(handler.init(label: label))
                return MultiplexLogHandler(loggers)
            }
        }
    }
}

extension LoggingConfig {
    public static func `default`() -> LoggingConfig {
        let env = Environment.current.variables

        let quiet = env[Constants.EnvironmentVariables.quiet] != nil
        let osLog = env[Constants.EnvironmentVariables.osLog] != nil
        let detailed = env[Constants.EnvironmentVariables.detailedLog] != nil
        let verbose = quiet ? false : Environment.current.isVerbose

        if quiet {
            return .init(loggerType: .quiet, verbose: verbose)
        } else if osLog {
            return .init(loggerType: .osLog, verbose: verbose)
        } else if detailed {
            return .init(loggerType: .detailed, verbose: verbose)
        } else {
            return .init(loggerType: .console, verbose: verbose)
        }
    }
}

/// A `VerboseLogHandler` allows for a LogHandler to be initialised with the `debug` logLevel.
protocol VerboseLogHandler: LogHandler {
    @Sendable static func verbose(label: String) -> LogHandler
    @Sendable init(label: String)
}

extension DetailedLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        DetailedLogHandler(label: label, logLevel: .debug)
    }
}

extension StandardLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        StandardLogHandler(label: label, logLevel: .debug)
    }
}

extension OSLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        OSLogHandler(label: label, logLevel: .debug)
    }
}

extension JSONLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        StandardLogHandler(label: label, logLevel: .debug)
    }
}

@Sendable private func quietLogHandler(label: String) -> LogHandler {
    return StandardLogHandler(label: label, logLevel: .notice)
}
