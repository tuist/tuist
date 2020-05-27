import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.SchemeDiagnosticsOption {
    static func from(manifest: ProjectDescription.SchemeDiagnosticsOption) -> TuistCore.SchemeDiagnosticsOption {
        switch manifest {
        case .mainThreadChecker: return .mainThreadChecker
        }
    }
}
