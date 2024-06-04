import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.SchemeDiagnosticsOptions {
    static func from(manifest: ProjectDescription.SchemeDiagnosticsOptions) -> XcodeProjectGenerator.SchemeDiagnosticsOptions {
        return XcodeProjectGenerator.SchemeDiagnosticsOptions(
            addressSanitizerEnabled: manifest.addressSanitizerEnabled,
            detectStackUseAfterReturnEnabled: manifest.detectStackUseAfterReturnEnabled,
            threadSanitizerEnabled: manifest.threadSanitizerEnabled,
            mainThreadCheckerEnabled: manifest.mainThreadCheckerEnabled,
            performanceAntipatternCheckerEnabled: manifest
                .performanceAntipatternCheckerEnabled
        )
    }
}
