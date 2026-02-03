import Foundation
@_exported import Logging
import Path
import TuistConstants
import TuistEnvironment

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

// MARK: - VerboseLogHandler

/// A `VerboseLogHandler` allows for a LogHandler to be initialised with the `debug` logLevel.
public protocol VerboseLogHandler: LogHandler {
    @Sendable static func verbose(label: String) -> LogHandler
    @Sendable init(label: String)
}

extension CrossPlatformDetailedLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        CrossPlatformDetailedLogHandler(label: label, logLevel: .debug)
    }
}

extension CrossPlatformStandardLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        CrossPlatformStandardLogHandler(label: label, logLevel: .debug)
    }
}

extension CrossPlatformJSONLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        CrossPlatformStandardLogHandler(label: label, logLevel: .debug)
    }
}

@Sendable private func quietLogHandler(label: String) -> LogHandler {
    return CrossPlatformStandardLogHandler(label: label, logLevel: .notice)
}

// MARK: - Logger extensions

extension Logger {
    public static func loggerHandlerForNoora(logFilePath: AbsolutePath) throws -> @Sendable (String) -> any LogHandler {
        let fileURL = URL(fileURLWithPath: logFilePath.pathString)
        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: fileURL)
        return { _ in
            var handler = fileLogHandler
            handler.logLevel = .debug
            return MultiplexLogHandler([handler])
        }
    }

    public static func defaultLoggerHandler(
        config: LoggingConfig,
        logFilePath: AbsolutePath
    ) throws -> @Sendable (String) -> any LogHandler {
        let handler: VerboseLogHandler.Type

        switch config.loggerType {
        case .detailed:
            handler = CrossPlatformDetailedLogHandler.self
        case .console:
            handler = CrossPlatformStandardLogHandler.self
        case .json:
            handler = CrossPlatformJSONLogHandler.self
        case .quiet:
            return quietLogHandler
        }

        let fileURL = URL(fileURLWithPath: logFilePath.pathString)
        let fileLogHandler = try SimpleFileLogHandler(label: "dev.tuist.cli", fileURL: fileURL)

        let baseLoggers = { (_: String) -> [any LogHandler] in
            var handler = fileLogHandler
            handler.logLevel = .debug
            return [handler]
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
