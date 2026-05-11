import Foundation

public struct HTTPSettings: Sendable {
    public var useEnvironmentProxy: Bool

    private static let lock = NSLock()
    private static var storedCurrent = HTTPSettings()

    public init(useEnvironmentProxy: Bool = true) {
        self.useEnvironmentProxy = useEnvironmentProxy
    }

    public static var current: HTTPSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedCurrent
        }
        set {
            lock.lock()
            storedCurrent = newValue
            lock.unlock()
            invalidateSharedTuistURLSession()
        }
    }
}
