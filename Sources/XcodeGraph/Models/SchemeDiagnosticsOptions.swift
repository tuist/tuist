import Foundation

public struct SchemeDiagnosticsOptions: Equatable, Codable {
    public let addressSanitizerEnabled: Bool
    public let detectStackUseAfterReturnEnabled: Bool
    public let threadSanitizerEnabled: Bool
    public let mainThreadCheckerEnabled: Bool
    public let performanceAntipatternCheckerEnabled: Bool

    public init(
        addressSanitizerEnabled: Bool = false,
        detectStackUseAfterReturnEnabled: Bool = false,
        threadSanitizerEnabled: Bool = false,
        mainThreadCheckerEnabled: Bool = false,
        performanceAntipatternCheckerEnabled: Bool = false
    ) {
        self.addressSanitizerEnabled = addressSanitizerEnabled
        self.detectStackUseAfterReturnEnabled = detectStackUseAfterReturnEnabled
        self.threadSanitizerEnabled = threadSanitizerEnabled
        self.mainThreadCheckerEnabled = mainThreadCheckerEnabled
        self.performanceAntipatternCheckerEnabled = performanceAntipatternCheckerEnabled
    }
}
