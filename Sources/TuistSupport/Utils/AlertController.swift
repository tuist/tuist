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
    private var _alerts: [Alert] = []
    private var alerts: [Alert] {
        get {
            alertQueue.sync { _alerts }
        }
        set {
            alertQueue.sync { _alerts = newValue }
        }
    }

    public init() {}

    public func success(_ alert: SuccessAlert) {
        var alerts = alerts
        alerts.insert(.success(alert), at: alerts.endIndex)
        self.alerts = alerts
    }

    public func warning(_ alert: WarningAlert) {
        var alerts = alerts
        alerts.insert(.warning(alert), at: alerts.endIndex)
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
