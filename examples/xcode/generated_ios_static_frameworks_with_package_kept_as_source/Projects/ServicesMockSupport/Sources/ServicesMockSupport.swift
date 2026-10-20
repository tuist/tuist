import Analytics
import Services

public struct ServicesMock {
    public init() {}

    public var services: Services {
        Services()
    }

    public var isCrashReportingEnabled: Bool {
        Analytics.isCrashReportingEnabled
    }
}
