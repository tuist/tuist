@_exported import Logging
let logger = Logger(label: "io.tuist.support")

import class Foundation.ProcessInfo

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

public enum LogOutput {
    
    public static func bootstrap() {
        
        let verbose  = ProcessInfo.processInfo.environment["TUIST_VERBOSE"] != nil
        let detailed = ProcessInfo.processInfo.environment["TUIST_DETAILED_LOG"] != nil
        
        let handler: VerboseLogHandler.Type
        
        if detailed {
            handler = DetailedLogHandler.self
        } else {
            handler = StandardLogHandler.self
        }
        
        if verbose {
            LoggingSystem.bootstrap(handler.verbose)
        } else {
            LoggingSystem.bootstrap(handler.init)
        }
        
    }
    
}
