import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.CompatibleXcodeVersions {
    /// Maps a ProjectDescription.CompatibleXcodeVersions instance into a XcodeGraph.CompatibleXcodeVersions model.
    /// - Parameters:
    ///   - manifest: Manifest representation of compatible Xcode versions.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> TuistCore.CompatibleXcodeVersions {
        switch manifest {
        case .all:
            return .all
        case let .exact(version):
            return .exact(.init(stringLiteral: version.description))
        case let .upToNextMajor(version):
            return .upToNextMajor(.init(stringLiteral: version.description))
        case let .upToNextMinor(version):
            return .upToNextMinor(.init(stringLiteral: version.description))
        case let .list(versions):
            return .list(versions.map { from(manifest: $0) })
        }
    }
}
