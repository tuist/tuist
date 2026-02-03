// Re-export logging utilities from TuistLogging for backwards compatibility
@_exported import TuistLogging

import Foundation
import Logging
import LoggingOSLog
import Path
import TuistConstants
import TuistEnvironment

// MARK: - OSLog support for macOS

extension LoggingConfig.LoggerType {
    public static let osLog = LoggingConfig.LoggerType.console // Fallback to console in base enum
}

public struct OSLogHandler: LogHandler, VerboseLogHandler {
    private var osLogHandler: LoggingOSLog
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level

    public init(label: String) {
        self.osLogHandler = LoggingOSLog(label: label)
        self.logLevel = .info
    }

    public init(label: String, logLevel: Logger.Level) {
        self.osLogHandler = LoggingOSLog(label: label)
        self.logLevel = logLevel
    }

    public static func verbose(label: String) -> LogHandler {
        OSLogHandler(label: label, logLevel: .debug)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        osLogHandler.log(
            level: level,
            message: message,
            metadata: metadata,
            source: source,
            file: file,
            function: function,
            line: line
        )
    }
}

// MARK: - macOS-specific LoggingConfig extension

extension LoggingConfig {
    public static func defaultWithOSLog() -> LoggingConfig {
        let env = Environment.current.variables

        let quiet = env[Constants.EnvironmentVariables.quiet] != nil
        let osLog = env[Constants.EnvironmentVariables.osLog] != nil
        let detailed = env[Constants.EnvironmentVariables.detailedLog] != nil
        let verbose = quiet ? false : Environment.current.isVerbose

        if quiet {
            return .init(loggerType: .quiet, verbose: verbose)
        }
        if osLog {
            // Use console as fallback since osLog isn't in the base enum
            return .init(loggerType: .console, verbose: verbose)
        }
        if detailed {
            return .init(loggerType: .detailed, verbose: verbose)
        }
        return .init(loggerType: .console, verbose: verbose)
    }
}

// MARK: - macOS-specific Logger extensions

extension Logger {
    public static func loggerHandlerForNooraWithOSLog(logFilePath: AbsolutePath) throws -> @Sendable (String) -> any LogHandler {
        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: logFilePath.url)
        return { label in
            var handler = fileLogHandler
            handler.logLevel = .debug
            var loggers: [any LogHandler] = [handler]
            loggers.append(OSLogHandler.verbose(label: label))
            return MultiplexLogHandler(loggers)
        }
    }

    public static func defaultLoggerHandlerWithOSLog(
        config: LoggingConfig,
        logFilePath: AbsolutePath
    ) throws -> @Sendable (String) -> any LogHandler {
        let handler: VerboseLogHandler.Type

        switch config.loggerType {
        case .detailed:
            handler = DetailedLogHandler.self
        case .console:
            handler = StandardLogHandler.self
        case .json:
            handler = JSONLogHandler.self
        case .quiet:
            return { label in StandardLogHandler(label: label, logLevel: .notice) }
        }

        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: logFilePath.url)

        let baseLoggers = { (label: String) -> [any LogHandler] in
            var handler = fileLogHandler
            handler.logLevel = .debug

            var loggers: [any LogHandler] = [handler]
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
