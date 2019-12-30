import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Package: ModelConvertible {
    init(manifest: ProjectDescription.Package, generatorPaths: GeneratorPaths) throws {
        switch manifest {
        case let .local(path: local):
            self = .local(path: try generatorPaths.resolve(path: local))
        case let .remote(url: url, requirement: version):
            self = .remote(url: url, requirement: try .init(manifest: version, generatorPaths: generatorPaths))
        }
    }
}

extension TuistCore.Package.Requirement: ModelConvertible {
    init(manifest: ProjectDescription.Package.Requirement, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case let .branch(branch):
            self = .branch(branch)
        case let .exact(version):
            self = .exact(version.description)
        case let .range(from, to):
            self = .range(from: from.description, to: to.description)
        case let .revision(revision):
            self = .revision(revision)
        case let .upToNextMajor(version):
            self = .upToNextMajor(version.description)
        case let .upToNextMinor(version):
            self = .upToNextMinor(version.description)
        }
    }
}
