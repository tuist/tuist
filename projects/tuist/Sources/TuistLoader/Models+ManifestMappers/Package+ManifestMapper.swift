import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Package {
    /// Maps a ProjectDescription.Package instance into a TuistGraph.Package model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Package, generatorPaths: GeneratorPaths) throws -> TuistGraph.Package {
        switch manifest {
        case let .local(path: local):
            return .local(path: try generatorPaths.resolve(path: local))
        case let .remote(url: url, requirement: version):
            return .remote(url: url, requirement: .from(manifest: version))
        }
    }
}

extension TuistGraph.Requirement {
    /// Maps a ProjectDescription.Package.Requirement instance into a TuistGraph.Package.Requirement model.
    /// - Parameters:
    ///   - manifest: Manifest representation of Package.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Package.Requirement) -> TuistGraph.Requirement {
        switch manifest {
        case let .branch(branch):
            return .branch(branch)
        case let .exact(version):
            return .exact(version.description)
        case let .range(from, to):
            return .range(from: from.description, to: to.description)
        case let .revision(revision):
            return .revision(revision)
        case let .upToNextMajor(version):
            return .upToNextMajor(version.description)
        case let .upToNextMinor(version):
            return .upToNextMinor(version.description)
        }
    }
}
