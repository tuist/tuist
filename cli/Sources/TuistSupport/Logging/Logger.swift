import Foundation
import Logging
#if os(macOS)
    import LoggingOSLog
#endif
import Path
import TuistConstants
import TuistEnvironment
import TuistLogging

public struct LoggingConfig {
    public init(loggerType: LoggerType, verbose: Bool) {
        self.loggerType = loggerType
        self.verbose = verbose
    }

    public enum LoggerType {
        case console
        case detailed
        #if os(macOS)
            case osLog
        #endif
        case json
        case quiet
    }

    public var loggerType: LoggerType
    public var verbose: Bool
}

extension Logger {
    public static func loggerHandlerForNoora(logFilePath: AbsolutePath) throws -> @Sendable (String) -> any LogHandler {
        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: logFilePath.url)
        return { label in
            var handler = fileLogHandler
            handler.logLevel = .debug
            var loggers: [any LogHandler] = [handler]
            #if os(macOS)
                loggers.append(OSLogHandler.verbose(label: label))
            #endif
            return MultiplexLogHandler(loggers)
        }
    }

    public static func defaultLoggerHandler(
        config: LoggingConfig,
        logFilePath: AbsolutePath
    ) throws -> @Sendable (String) -> any LogHandler {
        let handler: VerboseLogHandler.Type

        switch config.loggerType {
        #if os(macOS)
            case .osLog:
                handler = OSLogHandler.self
        #endif
        case .detailed:
            handler = DetailedLogHandler.self
        case .console:
            handler = StandardLogHandler.self
        case .json:
            handler = JSONLogHandler.self
        case .quiet:
            return quietLogHandler
        }

        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: logFilePath.url)

        let baseLoggers = { (label: String) -> [any LogHandler] in
            var handler = fileLogHandler
            handler.logLevel = .debug

            var loggers: [any LogHandler] = [handler]
            // OSLog is not needed in development.
            // If we include it, the Xcode console will show duplicated logs, making it harder for contributors to debug the
            // execution
            // within Xcode.
            // When run directly from a terminal, logs are not duplicated.
            #if RELEASE && os(macOS)
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

/// A simple cross-platform file log handler that writes to a file.
public struct SimpleFileLogHandler: LogHandler, @unchecked Sendable {
    private let fileHandle: FileHandle
    private let label: String
    private let lock = NSLock()
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .info

    public init(label: String, fileURL: URL) throws {
        self.label = label
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        self.fileHandle.seekToEndOfFile()
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
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let mergedMetadata = self.metadata.merging(metadata ?? [:]) { _, new in new }
        let metadataString = mergedMetadata.isEmpty ? "" : " \(mergedMetadata)"
        let logMessage = "[\(timestamp)] [\(level)] [\(source)] \(message)\(metadataString)\n"
        if let data = logMessage.data(using: .utf8) {
            lock.lock()
            defer { lock.unlock() }
            fileHandle.write(data)
        }
    }
}

extension LoggingConfig {
    public static func `default`() -> LoggingConfig {
        let env = Environment.current.variables

        let quiet = env[Constants.EnvironmentVariables.quiet] != nil
        #if os(macOS)
            let osLog = env[Constants.EnvironmentVariables.osLog] != nil
        #endif
        let detailed = env[Constants.EnvironmentVariables.detailedLog] != nil
        let verbose = quiet ? false : Environment.current.isVerbose

        if quiet {
            return .init(loggerType: .quiet, verbose: verbose)
        }
        #if os(macOS)
            if osLog {
                return .init(loggerType: .osLog, verbose: verbose)
            }
        #endif
        if detailed {
            return .init(loggerType: .detailed, verbose: verbose)
        }
        return .init(loggerType: .console, verbose: verbose)
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

#if os(macOS)
    extension OSLogHandler: VerboseLogHandler {
        public static func verbose(label: String) -> LogHandler {
            OSLogHandler(label: label, logLevel: .debug)
        }
    }
#endif

extension JSONLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        StandardLogHandler(label: label, logLevel: .debug)
    }
}

@Sendable private func quietLogHandler(label: String) -> LogHandler {
    return StandardLogHandler(label: label, logLevel: .notice)
}
