import class Foundation.ProcessInfo
@_exported import Logging

let logger = Logger(label: "io.tuist.support")

public struct LoggingConfig {
    public enum LoggerType {
        case console
        case detailed
        case osLog
    }

    public var loggerType: LoggerType
    public var verbose: Bool
}

extension LoggingConfig {
    public static var `default`: LoggingConfig {
        let env = ProcessInfo.processInfo.environment

        let osLog = env[Constants.EnvironmentVariables.osLog] != nil
        let detailed = env[Constants.EnvironmentVariables.detailedLog] != nil
        let verbose = env[Constants.EnvironmentVariables.verbose] != nil

        if osLog {
            return .init(loggerType: .osLog, verbose: verbose)
        } else if detailed {
            return .init(loggerType: .detailed, verbose: verbose)
        } else {
            return .init(loggerType: .console, verbose: verbose)
        }
    }
}

public enum LogOutput {
    static var environment = ProcessInfo.processInfo.environment

    public static func bootstrap(config: LoggingConfig = .default) {
        let handler: VerboseLogHandler.Type

        switch config.loggerType {
        case .osLog:
            handler = OSLogHandler.self
        case .detailed:
            handler = DetailedLogHandler.self
        case .console:
            handler = StandardLogHandler.self
        }

        if config.verbose {
            LoggingSystem.bootstrap(handler.verbose)
        } else {
            LoggingSystem.bootstrap(handler.init)
        }
    }
}

// A `VerboseLogHandler` allows for a LogHandler to be initialised with the `debug` logLevel.
protocol VerboseLogHandler: LogHandler {
    static func verbose(label: String) -> LogHandler
    init(label: String)
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
