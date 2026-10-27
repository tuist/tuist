import XcodeGraph
import XcodeProj

extension SchemeDiagnosticsOptions {
    /// Creates a SchemeDiagnosticsOptions from a LaunchAction.
    init(action: XCScheme.LaunchAction) {
        self = SchemeDiagnosticsOptions(
            addressSanitizerEnabled: action.enableAddressSanitizer,
            detectStackUseAfterReturnEnabled: action.enableASanStackUseAfterReturn,
            threadSanitizerEnabled: action.enableThreadSanitizer,
            mainThreadCheckerEnabled: !action.disableMainThreadChecker,
            performanceAntipatternCheckerEnabled: !action.disablePerformanceAntipatternChecker
        )
    }

    /// Creates a SchemeDiagnosticsOptions from a TestAction.
    init(action: XCScheme.TestAction) {
        self = SchemeDiagnosticsOptions(
            addressSanitizerEnabled: action.enableAddressSanitizer,
            detectStackUseAfterReturnEnabled: action.enableASanStackUseAfterReturn,
            threadSanitizerEnabled: action.enableThreadSanitizer,
            mainThreadCheckerEnabled: !action.disableMainThreadChecker
        )
    }
}
