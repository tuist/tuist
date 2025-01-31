import Noora
import ServiceContextModule

private enum UIServiceContextKey: ServiceContextKey {
    typealias Value = Noorable
}

extension ServiceContext {
    public var ui: Noorable? {
        get {
            self[UIServiceContextKey.self]
        } set {
            self[UIServiceContextKey.self] = newValue
        }
    }
}
