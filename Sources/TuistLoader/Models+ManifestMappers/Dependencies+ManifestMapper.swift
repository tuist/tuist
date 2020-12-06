import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Dependencies {
    static func from(manifest: ProjectDescription.Dependencies) throws -> Self {
        let carthageDependencyModels = try manifest.carthage
            .map { try TuistCore.CarthageDependency.from(manifest: $0) }

        return Self(carthageDependencies: carthageDependencyModels)
    }
}

extension TuistCore.CarthageDependency {
    static func from(manifest: ProjectDescription.CarthageDependency) throws -> Self {
        let requirement = try TuistCore.CarthageDependency.Requirement.from(manifest: manifest.requirement)
        let platforms = try manifest.platforms.map { try TuistCore.Platform.from(manifest: $0) }

        return Self(name: manifest.name, requirement: requirement, platforms: Set(platforms))
    }
}

extension TuistCore.CarthageDependency.Requirement {
    static func from(manifest: ProjectDescription.CarthageDependency.Requirement) throws -> Self {
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
