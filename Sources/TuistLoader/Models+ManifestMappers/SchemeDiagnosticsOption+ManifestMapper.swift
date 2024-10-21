import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.SchemeDiagnosticsOptions {
    static func from(manifest: ProjectDescription.SchemeDiagnosticsOptions) -> XcodeGraph.SchemeDiagnosticsOptions {
        return XcodeGraph.SchemeDiagnosticsOptions(
            addressSanitizerEnabled: manifest.addressSanitizerEnabled,
            detectStackUseAfterReturnEnabled: manifest.detectStackUseAfterReturnEnabled,
            threadSanitizerEnabled: manifest.threadSanitizerEnabled,
            mainThreadCheckerEnabled: manifest.mainThreadCheckerEnabled,
            performanceAntipatternCheckerEnabled: manifest
                .performanceAntipatternCheckerEnabled
        )
    }
}
