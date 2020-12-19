import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.CarthageDependency.Requirement {
    static func from(manifest: ProjectDescription.Dependency.CarthageRequirement) throws -> Self {
        switch manifest {
        case let .exact(version):
            return .exact(version.description)
        case let .upToNextMajor(version):
            return .upToNextMajor(version.description)
        case let .upToNextMinor(version):
            return .upToNextMinor(version.description)
        case let .branch(branch):
            return .branch(branch)
        case let .revision(revision):
            return .revision(revision)
        }
    }
}
