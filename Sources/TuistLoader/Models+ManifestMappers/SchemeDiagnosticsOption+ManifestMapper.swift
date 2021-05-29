import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.SchemeDiagnosticsOption {
    static func from(manifest: ProjectDescription.SchemeDiagnosticsOption) -> TuistGraph.SchemeDiagnosticsOption {
        switch manifest {
        case .mainThreadChecker: return .mainThreadChecker
        }
    }
}
