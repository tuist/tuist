import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.SchemeDiagnosticsOptions {
    static func from(manifest: ProjectDescription.SchemeDiagnosticsOptions) -> TuistGraph.SchemeDiagnosticsOptions {
        return TuistGraph.SchemeDiagnosticsOptions(
            addressSanitizerEnabled: manifest.addressSanitizerEnabled,
            detectStackUseAfterReturnEnabled: manifest.detectStackUseAfterReturnEnabled,
            threadSanitizerEnabled: manifest.threadSanitizerEnabled,
            mainThreadCheckerEnabled: manifest.mainThreadCheckerEnabled,
            performanceAntipatternCheckerEnabled: manifest
                .performanceAntipatternCheckerEnabled
        )
    }
}
