import Foundation
import Mockable
import Noora
import ServiceContextModule

enum Alert {
    case success(SuccessAlert)
    case warning(WarningAlert)
}

public final class AlertController: @unchecked Sendable {
    private let alertQueue = DispatchQueue(label: "io.tuist.TuistSupport.AlertController")
    private var alerts: ThreadSafe<[Alert]> = ThreadSafe([])

    public init() {}

    public func success(_ alert: SuccessAlert) {
        alerts.mutate { alerts in
            alerts.insert(.success(alert), at: alerts.endIndex)
        }
    }

    public func warning(_ alert: WarningAlert) {
        alerts.mutate { alerts in
            alerts.insert(.warning(alert), at: alerts.endIndex)
        }
    }

    public func flush() {
        alerts.mutate { alerts in
            alerts.removeAll()
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
