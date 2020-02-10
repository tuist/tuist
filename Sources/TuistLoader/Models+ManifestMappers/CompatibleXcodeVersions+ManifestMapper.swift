import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.CompatibleXcodeVersions {
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> TuistCore.CompatibleXcodeVersions {
        switch manifest {
        case .all:
            return .all
        case let .list(versions):
            return .list(versions)
        }
    }
}
