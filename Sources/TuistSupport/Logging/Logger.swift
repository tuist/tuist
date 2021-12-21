import class Foundation.ProcessInfo
@_exported import Logging

let logger = Logger(label: "io.tuist.support")

public struct LoggingConfig {
    public enum LoggerType {
        case console
        case detailed
        case osLog
    }

    public enum LoggerLevel {
        case `default`
        case verbose
        case silent
    }

    public var loggerType: LoggerType
    public var loggerLevel: LoggerLevel
}

extension LoggingConfig {
    public static var `default`: LoggingConfig {
        let env = ProcessInfo.processInfo.environment

        let osLog = env[Constants.EnvironmentVariables.osLog] != nil
        let detailed = env[Constants.EnvironmentVariables.detailedLog] != nil
        let verbose = env[Constants.EnvironmentVariables.verbose] != nil
        let silent = env[Constants.EnvironmentVariables.silent] != nil

        let loggerLevel: LoggerLevel
        if verbose {
            loggerLevel = .verbose
        } else if silent {
            loggerLevel = .silent
        } else {
            loggerLevel = .default
        }

        if osLog {
            return .init(loggerType: .osLog, loggerLevel: loggerLevel)
        } else if detailed {
            return .init(loggerType: .detailed, loggerLevel: loggerLevel)
        } else {
            return .init(loggerType: .console, loggerLevel: loggerLevel)
        }
    }
}

public enum LogOutput {
    static var environment = ProcessInfo.processInfo.environment

    public static func bootstrap(config: LoggingConfig = .default) {
        let handler: ConfigurableLevelLogHandler.Type

        switch config.loggerType {
        case .osLog:
            handler = OSLogHandler.self
        case .detailed:
            handler = DetailedLogHandler.self
        case .console:
            handler = StandardLogHandler.self
        }

        switch config.loggerLevel {
        case .verbose:
            LoggingSystem.bootstrap(handler.verbose)
        case .silent:
            LoggingSystem.bootstrap(handler.silent)
        case .default:
            LoggingSystem.bootstrap(handler.init)
        }
    }
}

// A `ConfigurableLevelLogHandler` allows for a LogHandler to be initialised with the
// `debug` or `error` logLevel.
protocol ConfigurableLevelLogHandler: LogHandler {
    static func verbose(label: String) -> LogHandler
    static func silent(label: String) -> LogHandler
    init(label: String)
}

extension DetailedLogHandler: ConfigurableLevelLogHandler {
    public static func verbose(label: String) -> LogHandler {
        DetailedLogHandler(label: label, logLevel: .debug)
    }

    public static func silent(label: String) -> LogHandler {
        DetailedLogHandler(label: label, logLevel: .error)
    }
}

extension StandardLogHandler: ConfigurableLevelLogHandler {
    public static func verbose(label: String) -> LogHandler {
        StandardLogHandler(label: label, logLevel: .debug)
    }

    public static func silent(label: String) -> LogHandler {
        StandardLogHandler(label: label, logLevel: .error)
    }
}

extension OSLogHandler: ConfigurableLevelLogHandler {
    public static func verbose(label: String) -> LogHandler {
        OSLogHandler(label: label, logLevel: .debug)
    }

    public static func silent(label: String) -> LogHandler {
        OSLogHandler(label: label, logLevel: .error)
    }
}
