/// Options to configure scheme diagnostics for run and test actions.
public struct SchemeDiagnosticsOptions: Equatable, Codable, Sendable {
    /// Enable the address sanitizer
    public var addressSanitizerEnabled: Bool

    /// Enable the detect use of stack after return of address sanitizer
    public var detectStackUseAfterReturnEnabled: Bool

    /// Enable the thread sanitizer
    public var threadSanitizerEnabled: Bool

    /// Enable the main thread cheker
    public var mainThreadCheckerEnabled: Bool

    /// Enable thread performance checker
    public var performanceAntipatternCheckerEnabled: Bool

    public static func options(
        addressSanitizerEnabled: Bool = false,
        detectStackUseAfterReturnEnabled: Bool = false,
        threadSanitizerEnabled: Bool = false,
        mainThreadCheckerEnabled: Bool = true,
        performanceAntipatternCheckerEnabled: Bool = true
    ) -> SchemeDiagnosticsOptions {
        return SchemeDiagnosticsOptions(
            addressSanitizerEnabled: addressSanitizerEnabled,
            detectStackUseAfterReturnEnabled: detectStackUseAfterReturnEnabled,
            threadSanitizerEnabled: threadSanitizerEnabled,
            mainThreadCheckerEnabled: mainThreadCheckerEnabled,
            performanceAntipatternCheckerEnabled: performanceAntipatternCheckerEnabled
        )
    }
}
