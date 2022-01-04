import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.CompatibleXcodeVersions {
    /// Maps a ProjectDescription.CompatibleXcodeVersions instance into a TuistGraph.CompatibleXcodeVersions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of compatible Xcode versions.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> TuistGraph.CompatibleXcodeVersions {
        switch manifest {
        case .all:
            return .all
        case let .exact(version):
            return .exact(version)
        case let .upToNextMajor(version):
            return .upToNextMajor(version)
        case let .upToNextMinor(version):
            return .upToNextMinor(version)
        case let .list(versions):
            return .list(versions.map { from(manifest: $0) })
        }
    }
}
