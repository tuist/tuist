// Documentation: https://docs.sentry.io/clients/cocoa
import Foundation
import Sentry

public enum Severity {
    case fatal
    case error
    case warning
    case info
    case debug
}

extension Severity {
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

public protocol TechLogging: AnyObject {
    func event(message: String, extra: [String: Any], severity: Severity)
    func breadCrumb(category: String, severity: Severity)
}

public class TechLogger: TechLogging {
    let client: Client?

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

    public func event(message: String, extra: [String: Any] = [:], severity: Severity = .info) {
        let event = Event(level: severity.sentry())
        event.message = message
        event.extra = extra
        client?.appendStacktrace(to: event)
        client?.send(event: event)
    }

    public func breadCrumb(category: String, severity: Severity = .info) {
        client?.breadcrumbs.add(Breadcrumb(level: severity.sentry(), category: category))
    }

    // MARK: - Static

    public static func defaultTags() -> [String: String] {
        var tags: [String: String] = [:]
        tags["osx"] = ProcessInfo.processInfo.operatingSystemVersionString
        tags["version"] = App().version
        return tags
    }
}
