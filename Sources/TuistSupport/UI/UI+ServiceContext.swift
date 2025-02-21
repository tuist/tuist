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

#if DEBUG
    extension ServiceContext {
        public func recordedUI() -> String! {
            alerts?.print()
            return (ui as? NooraMock)?.description as? String
        }
    }
#endif
