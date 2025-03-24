import Noora
import ServiceContextModule

private enum AlertServiceContextKey: ServiceContextKey {
    typealias Value = AlertController
}

extension ServiceContext {
    public var alerts: AlertController? {
        get {
            self[AlertServiceContextKey.self]
        } set {
            self[AlertServiceContextKey.self] = newValue
        }
    }
}
