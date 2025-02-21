import Foundation
import Mockable
import Noora
import ServiceContextModule

public enum Alert {
    case success(SuccessAlert)
    case warning(WarningAlert)
}

public final class AlertController: @unchecked Sendable {
    private let alertQueue = DispatchQueue(label: "io.tuist.TuistSupport.AlertController")
    private var _alerts: [Alert] = []
    public var alerts: [Alert] {
        get {
            alertQueue.sync { _alerts }
        }
        set {
            alertQueue.sync { _alerts = newValue }
        }
    }

    public init() {}

    public func append(_ alert: Alert) {
        var alerts = alerts
        alerts.insert(alert, at: alerts.endIndex)
        self.alerts = alerts
    }

    public func print() {
        for alert in alerts {
            switch alert {
            case let .success(successAlert):
                ServiceContext.current?.ui?.success(successAlert)
            case let .warning(warningAlert):
                ServiceContext.current?.ui?.warning(warningAlert)
            }
        }
    }
}
