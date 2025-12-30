enum LogFilePathDisplayStrategy: Decodable {
    /// Only shows the path to the log file on error
    case onError

    /// Always shows the path to the log file.
    case always

    /// The log file path is never shown.
    case never
}

/// This is a protocol that commands can conform to provide their preferences
/// regarding how the log file path should be shown.
///
/// If a command doesn't conform to this protocol, the default strategy used is "onError"
protocol LogConfigurableCommand {
    var logFilePathDisplayStrategy: LogFilePathDisplayStrategy { get }
}
