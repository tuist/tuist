import Foundation
@_exported import Logging
import Path
import TuistEnvironment

#if os(macOS)
    import TuistConstants
#endif

#if canImport(LoggingOSLog)
    import LoggingOSLog
#endif

extension Logger {
    @TaskLocal public static var current: Logger = .init(label: "dev.tuist.logger")
}

// MARK: - LoggingConfig

public struct LoggingConfig {
    public init(loggerType: LoggerType, verbose: Bool) {
        self.loggerType = loggerType
        self.verbose = verbose
    }

    public enum LoggerType {
        case console
        case detailed
        case json
        case quiet
    }

    public var loggerType: LoggerType
    public var verbose: Bool
}

extension LoggingConfig {
    public static func `default`() -> LoggingConfig {
        #if os(macOS)
            let env = Environment.current.variables

            let quiet = env[Constants.EnvironmentVariables.quiet] != nil
            let detailed = env[Constants.EnvironmentVariables.detailedLog] != nil
            let verbose = quiet ? false : Environment.current.isVerbose

            if quiet {
                return .init(loggerType: .quiet, verbose: verbose)
            }
            if detailed {
                return .init(loggerType: .detailed, verbose: verbose)
            }
            return .init(loggerType: .console, verbose: verbose)
        #else
            return .init(loggerType: .console, verbose: false)
        #endif
    }
}

// MARK: - SimpleFileLogHandler

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
        fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
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
        file _: String,
        function _: String,
        line _: UInt
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

// MARK: - VerboseLogHandler

/// A `VerboseLogHandler` allows for a LogHandler to be initialised with the `debug` logLevel.
public protocol VerboseLogHandler: LogHandler {
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

extension JSONLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        StandardLogHandler(label: label, logLevel: .debug)
    }
}

@Sendable private func quietLogHandler(label: String) -> LogHandler {
    return StandardLogHandler(label: label, logLevel: .notice)
}

// MARK: - OSLog support

#if canImport(LoggingOSLog)
    public struct OSLogHandler: LogHandler, VerboseLogHandler {
        private var osLogHandler: LoggingOSLog
        public var metadata: Logger.Metadata = [:]
        public var logLevel: Logger.Level

        public init(label: String) {
            osLogHandler = LoggingOSLog(label: label)
            logLevel = .info
        }

        public init(label: String, logLevel: Logger.Level) {
            osLogHandler = LoggingOSLog(label: label)
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
#endif

// MARK: - Logger extensions

extension Logger {
    public static func loggerHandlerForNoora(logFilePath: AbsolutePath) throws -> @Sendable (String) -> any LogHandler {
        let fileURL = URL(fileURLWithPath: logFilePath.pathString)
        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: fileURL)
        return { label in
            var handler = fileLogHandler
            handler.logLevel = .debug
            var loggers: [any LogHandler] = [handler]
            #if canImport(LoggingOSLog)
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
        case .detailed:
            handler = DetailedLogHandler.self
        case .console:
            handler = StandardLogHandler.self
        case .json:
            handler = JSONLogHandler.self
        case .quiet:
            return quietLogHandler
        }

        let fileURL = URL(fileURLWithPath: logFilePath.pathString)
        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: fileURL)

        let baseLoggers = { (label: String) -> [any LogHandler] in
            var handler = fileLogHandler
            handler.logLevel = .debug
            var loggers: [any LogHandler] = [handler]
            #if canImport(LoggingOSLog) && RELEASE
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
