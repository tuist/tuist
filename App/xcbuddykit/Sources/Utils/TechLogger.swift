// Documentation: https://docs.sentry.io/clients/cocoa
import Foundation
import Sentry

/// Tech logger severity levels.
///
/// - fatal: used when the event represents a fatal error.
/// - error: used when the event represents an error.
/// - warning: used when the event represents a warning.
/// - info: used when the event is an information message.
/// - debug: used when the event represents debug action.
public enum Severity {
    case fatal
    case error
    case warning
    case info
    case debug
}

// MARK: - Severity (Sentry)

extension Severity {
    /// Returns the Sentry severity from our custom severity level.
    /// This is done for mere abstraction purposes.
    ///
    /// - Returns: the Sentry severity level.
    func sentry() -> SentrySeverity {
        switch self {
        case .fatal: return .fatal
        case .error: return .error
        case .warning: return .warning
        case .info: return .info
        case .debug: return .debug
        }
    }
}

/// Protocol that represents an entity that can deliver tech events.
public protocol TechLogging: AnyObject {
    /// Reports an event.
    ///
    /// - Parameters:
    ///   - message: message to ge included in the event.
    ///   - extra: extra information to be attached to the event.
    ///   - severity: severity of the event.
    func event(message: String, extra: [String: Any], severity: Severity)

    /// Sends a breadcrumb event.
    ///
    /// - Parameters:
    ///   - category: category of the event.
    ///   - severity: severity of the event.
    func breadCrumb(category: String, severity: Severity)
}

/// Default tech logger conforming TechLogging
public class TechLogger: TechLogging {
    /// Sentry client.
    let client: Client?

    /// Initializes the tech logger with some default tags.
    ///
    /// - Parameter tags: default tags to be used.
    public init(tags: [String: String] = TechLogger.defaultTags()) {
        if let sentryDsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String {
            client = try! Client(dsn: sentryDsn)
            client?.tags = tags
            client?.enableAutomaticBreadcrumbTracking()
            try! client?.startCrashHandler()
        } else {
            client = nil
        }
    }

    /// Reports an event.
    ///
    /// - Parameters:
    ///   - message: message to ge included in the event.
    ///   - extra: extra information to be attached to the event.
    ///   - severity: severity of the event.
    public func event(message: String, extra: [String: Any] = [:], severity: Severity = .info) {
        let event = Event(level: severity.sentry())
        event.message = message
        event.extra = extra
        client?.appendStacktrace(to: event)
        client?.send(event: event)
    }

    /// Sends a breadcrumb event.
    ///
    /// - Parameters:
    ///   - category: category of the event.
    ///   - severity: severity of the event.
    public func breadCrumb(category: String, severity: Severity = .info) {
        client?.breadcrumbs.add(Breadcrumb(level: severity.sentry(), category: category))
    }

    // MARK: - Static

    /// Returns the default tags to be used with a new instance of the tech logger.
    ///
    /// - Returns: default tags that include information about the platform where the app is being run in.
    public static func defaultTags() -> [String: String] {
        var tags: [String: String] = [:]
        tags["osx"] = ProcessInfo.processInfo.operatingSystemVersionString
        tags["version"] = App().version
        return tags
    }
}
