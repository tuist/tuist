@_exported import Logging
let logger = Logger(label: "io.tuist.support")

import class Foundation.ProcessInfo

public enum LogOutput {
    public static func bootstrap() {
        let verbose = ProcessInfo.processInfo.environment["TUIST_VERBOSE"] != nil
        if verbose {
            LoggingSystem.bootstrap(ConsoleLogHandler.verbose)
        } else {
            LoggingSystem.bootstrap(ConsoleLogHandler.init)
        }
    }
}
