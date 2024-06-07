import Foundation
import ProjectDescription
import Path
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.CompatibleXcodeVersions {
    /// Maps a ProjectDescription.CompatibleXcodeVersions instance into a XcodeGraph.CompatibleXcodeVersions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of compatible Xcode versions.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> XcodeGraph.CompatibleXcodeVersions {
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
