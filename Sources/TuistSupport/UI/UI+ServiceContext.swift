import Noora
import ServiceContextModule

private enum UIServiceContextKey: ServiceContextKey {
    typealias Value = UIController
}

extension ServiceContext {
    public var ui: UIController? {
        get {
            self[UIServiceContextKey.self]
        } set {
            self[UIServiceContextKey.self] = newValue
        }
    }
}

#if DEBUG
    extension ServiceContext {
        public func flushRecordedUI() {
            alerts?.flush()
        }

        public func recordedUI() -> String! {
            alerts?.print()
            return (ui?.noora as? NooraMock)?.description as? String
        }
    }
#endif
