@_exported import Logging
let logger = Logger(label: "io.tuist.support")

import class Foundation.ProcessInfo

public enum LogOutput {
    
    static var environment = ProcessInfo.processInfo.environment
    
    public static func bootstrap() {
                
        let os_log   = environment["TUIST_OS_LOG"]       != nil
        let detailed = environment["TUIST_DETAILED_LOG"] != nil
        
        let handler: VerboseLogHandler.Type
        
        if os_log {
            handler = OSLogHandler.self
        } else if detailed {
            handler = DetailedLogHandler.self
        } else {
            handler = StandardLogHandler.self
        }
        
        let verbose = environment["TUIST_VERBOSE"] != nil
        
        if verbose {
            LoggingSystem.bootstrap(handler.verbose)
        } else {
            LoggingSystem.bootstrap(handler.init)
        }
        
    }
    
}

// A `VerboseLogHandler` allows for a LogHandler to be initialised with the
// `debug` logLevel.
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
