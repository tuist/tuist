import Foundation
import Mockable
import Noora
import ServiceContextModule

enum Alert: Equatable, Hashable {
    case success(SuccessAlert)
    case warning(WarningAlert)

    var warning: WarningAlert? {
        switch self {
        case .success:
            return nil
        case let .warning(alert):
            return alert
        }
    }

    var success: SuccessAlert? {
        switch self {
        case let .success(alert):
            return alert
        case .warning:
            return nil
        }
    }
}

public final class AlertController: @unchecked Sendable {
    private let alertQueue = DispatchQueue(label: "io.tuist.TuistSupport.AlertController")
    private var alerts: ThreadSafe<Set<Alert>> = ThreadSafe([])

    public init() {}

    public func success(_ alert: SuccessAlert) {
        alerts.mutate { alerts in
            alerts.insert(.success(alert))
        }
    }

    public func warning(_ alert: WarningAlert) {
        alerts.mutate { alerts in
            alerts.insert(.warning(alert))
        }
    }

    public func flush() {
        alerts.mutate { alerts in
            alerts.removeAll()
        }
    }

    public func warnings() -> [WarningAlert] {
        return alerts.withValue { alerts in
            alerts.compactMap(\.warning)
        }.sorted(by: { $0.message.plain() < $1.message.plain() })
    }

    public func success() -> [SuccessAlert] {
        return alerts.withValue { alerts in
            alerts.compactMap(\.success)
        }.sorted(by: { $0.message.plain() < $1.message.plain() })
    }

    public func print() {
        for warning in warnings() {
            ServiceContext.current?.ui?.warning(warning)
        }
        for success in success() {
            ServiceContext.current?.ui?.success(success)
        }
    }
}
