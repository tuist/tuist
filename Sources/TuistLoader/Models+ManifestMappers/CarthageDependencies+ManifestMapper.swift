import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.CarthageDependencies {
    static func from(manifest: ProjectDescription.CarthageDependencies) throws -> Self {
        let dependencies = manifest.dependencies.map { TuistGraph.CarthageDependencies.Dependency.from(manifest: $0) }
        let options = try TuistGraph.CarthageDependencies.Options.from(manifest: manifest.options)
        return .init(dependencies: dependencies, options: options)
    }
}

extension TuistGraph.CarthageDependencies.Dependency {
    static func from(manifest: ProjectDescription.CarthageDependencies.Dependency) -> Self {
        switch manifest {
        case let .github(path, requirement):
            return .github(path: path, requirement: .from(manifest: requirement))
        case let .git(path, requirement):
            return .git(path: path, requirement: .from(manifest: requirement))
        case let .binary(path, requirement):
            return .binary(path: path, requirement: .from(manifest: requirement))
        }
    }
}

extension TuistGraph.CarthageDependencies.Requirement {
    static func from(manifest: ProjectDescription.CarthageDependencies.Requirement) -> Self {
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

extension TuistGraph.CarthageDependencies.Options {
    static func from(manifest: ProjectDescription.CarthageDependencies.Options) throws -> Self {
        let platforms = try manifest.platforms.map { try TuistGraph.Platform.from(manifest: $0) }
        return .init(platforms: Set(platforms), useXCFrameworks: manifest.useXCFrameworks)
    }
}
