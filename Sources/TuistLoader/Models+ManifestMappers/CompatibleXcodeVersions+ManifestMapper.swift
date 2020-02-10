import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.CompatibleXcodeVersions {
    /// Maps a ProjectDescription.CompatibleXcodeVersions instance into a TuistCore.CompatibleXcodeVersions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of compatible Xcode versions.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> TuistCore.CompatibleXcodeVersions {
        switch manifest {
        case .all:
            return .all
        case let .list(versions):
            return .list(versions)
        }
    }
}
