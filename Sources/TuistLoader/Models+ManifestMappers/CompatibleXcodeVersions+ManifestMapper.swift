import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.CompatibleXcodeVersions {
    /// Maps a ProjectDescription.CompatibleXcodeVersions instance into a TuistCore.CompatibleXcodeVersions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of compatible Xcode versions.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> TuistGraph.CompatibleXcodeVersions {
        switch manifest {
        case .all:
            return .all
        case let .list(versions):
            return .list(versions)
        }
    }
}
