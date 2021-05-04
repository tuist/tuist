import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.CarthageDependencies {
    /// Creates `TuistGraph.CarthageDependencies` instance from `ProjectDescription.CarthageDependencies` instance.
    static func from(manifest: ProjectDescription.CarthageDependencies) throws -> Self {
        let dependencies = manifest.dependencies.map { TuistGraph.CarthageDependencies.Dependency.from(manifest: $0) }
        let options = manifest.options.map { TuistGraph.CarthageDependencies.Options.from(manifest: $0) }

        return .init(dependencies, options: Set(options))
    }
}

extension TuistGraph.CarthageDependencies.Dependency {
    /// Creates `TuistGraph.CarthageDependencies.Dependency` instance from `ProjectDescription.CarthageDependencies.Dependency` instance.
    static func from(manifest: ProjectDescription.CarthageDependencies.Dependency) -> Self {
        switch manifest {
        case let .github(path, requirement, copyPath, names):
            return .github(path: path, requirement: .from(manifest: requirement), copyPath: copyPath, names: names)
        case let .git(path, requirement, copyPath, names):
            return .git(path: path, requirement: .from(manifest: requirement), copyPath: copyPath, names: names)
        case let .binary(path, requirement, copyPath, names):
            return .binary(path: path, requirement: .from(manifest: requirement), copyPath: copyPath, names: names)
        }
    }
}

extension TuistGraph.CarthageDependencies.Requirement {
    /// Creates `TuistGraph.CarthageDependencies.Requirement` instance from `ProjectDescription.CarthageDependencies.Requirement` instance.
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
    /// Creates `TuistGraph.CarthageDependencies.Options` instance from `ProjectDescription.CarthageDependencies.Options` instance.
    static func from(manifest: ProjectDescription.CarthageDependencies.Options) -> Self {
        switch manifest {
        case .useXCFrameworks:
            return .useXCFrameworks
        case .noUseBinaries:
            return .noUseBinaries
        }
    }
}
