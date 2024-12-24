import class Foundation.ProcessInfo
@_exported import Logging

let logger = Logger(label: "io.tuist.support")

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

public extension Logger {
    static func defaultLoggerHandler(config: LoggingConfig = .default) -> (String) -> any LogHandler {
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

        if config.verbose {
            return handler.verbose
        } else {
            return handler.init
        }
    }
}

extension LoggingConfig {
    public static var `default`: LoggingConfig {
        let env = ProcessInfo.processInfo.environment

        let quiet = env[Constants.EnvironmentVariables.quiet] != nil
        let osLog = env[Constants.EnvironmentVariables.osLog] != nil
        let detailed = env[Constants.EnvironmentVariables.detailedLog] != nil
        let verbose = quiet ? false : env[Constants.EnvironmentVariables.verbose] != nil

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
        case .json:
            handler = JSONLogHandler.self
        case .quiet:
            LoggingSystem.bootstrap(quietLogHandler)
            return
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

extension JSONLogHandler: VerboseLogHandler {
    public static func verbose(label: String) -> LogHandler {
        StandardLogHandler(label: label, logLevel: .debug)
    }
}

private func quietLogHandler(label: String) -> LogHandler {
    return StandardLogHandler(label: label, logLevel: .notice)
}
