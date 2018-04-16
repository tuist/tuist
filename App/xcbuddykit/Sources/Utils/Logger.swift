import Foundation

/// Logging protocol.
public protocol Logging: AnyObject {
    /// Logs a message.
    ///
    /// - Parameter message: message to log.
    func log(_ message: String)
}

public class Logger: Logging {
    public func log(_ message: String) {
        print(message)
    }
}
