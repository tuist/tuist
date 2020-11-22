import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Requirement {
    static func from(manifest: ProjectDescription.Dependency.Requirement) -> Self {
        switch manifest {
        case let .exact(version):
            return .exact(version.description)
        }
    }
}
