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
        }
    }

    public func success() -> [SuccessAlert] {
        return alerts.withValue { alerts in
            alerts.compactMap(\.success)
        }
    }

    public func print() {
        for alert in alerts.value {
            switch alert {
            case let .success(successAlert):
                ServiceContext.current?.ui?.success(successAlert)
            case let .warning(warningAlert):
                ServiceContext.current?.ui?.warning(warningAlert)
            }
        }
    }
}
