import Foundation

public struct HTTPSettings: Equatable, Sendable {
    public var useEnvironmentProxy: Bool
    public var caCertificatePath: String?

    private static let lock = NSLock()
    private static var storedCurrent = HTTPSettings()

    public init(useEnvironmentProxy: Bool = true, caCertificatePath: String? = nil) {
        self.useEnvironmentProxy = useEnvironmentProxy
        self.caCertificatePath = caCertificatePath
    }

    public static var current: HTTPSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedCurrent
        }
        set {
            lock.lock()
            let didChange = storedCurrent != newValue
            storedCurrent = newValue
            lock.unlock()
            if didChange {
                invalidateSharedTuistURLSession()
            }
        }
    }
}
