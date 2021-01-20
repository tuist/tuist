import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.CarthageDependency.Origin {
    static func from(manifest: ProjectDescription.Dependency.CarthageOrigin) throws -> Self {
        switch manifest {
        case let .github(path):
            return .github(path: path)
        case let .git(path):
            return .git(path: path)
        case let .binary(path):
            return .binary(path: path)
        }
    }
}

extension TuistGraph.CarthageDependency.Requirement {
    static func from(manifest: ProjectDescription.Dependency.CarthageRequirement) throws -> Self {
        switch manifest {
        case let .exact(version):
            return .exact(version.description)
        case let .upToNext(version):
            return .upToNext(version.description)
        case let .atLeast(version):
            return .atLeast(version.description)
        case let .branch(branch):
            return .branch(branch)
        case let .revision(revision):
            return .revision(revision)
        }
    }
}
