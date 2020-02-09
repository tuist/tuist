@_exported import Logging
let logger = Logger(label: "io.tuist.support")

public enum LogOutput {
    public static func bootstrap() {
        if CommandLine.arguments.contains("--output=os_log") {
            LoggingSystem.bootstrap(OSLogHandler.init)
        } else {
            let verbose = CommandLine.arguments.contains("--verbose") || CommandLine.arguments.contains("-v")
            if verbose {
                LoggingSystem.bootstrap(ConsoleLogHandler.verbose)
            } else {
                LoggingSystem.bootstrap(ConsoleLogHandler.init)
            }
        }
    }
}
