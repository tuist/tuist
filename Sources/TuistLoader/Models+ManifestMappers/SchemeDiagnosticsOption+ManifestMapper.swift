import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.SchemeDiagnosticsOption {
    static func from(manifest: ProjectDescription.SchemeDiagnosticsOption) -> TuistGraph.SchemeDiagnosticsOption {
        switch manifest {
        case .enableAddressSanitizer: return .enableAddressSanitizer
        case .enableDetectStackUseAfterReturn: return .enableASanStackUseAfterReturn
        case .enableThreadSanitizer: return .enableThreadSanitizer
        case .mainThreadChecker: return .mainThreadChecker
        case .performanceAntipatternChecker: return .performanceAntipatternChecker
        }
    }
}
