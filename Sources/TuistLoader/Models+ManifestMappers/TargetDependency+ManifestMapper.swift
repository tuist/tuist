import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.TargetDependency {
    /// Maps a ProjectDescription.TargetDependency instance into a TuistGraph.TargetDependency instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the target dependency model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TargetDependency, generatorPaths: GeneratorPaths) throws -> TuistGraph.TargetDependency {
        switch manifest {
        case let .target(name):
            return .target(name: name)
        case let .project(target, projectPath):
            return .project(target: target, path: try generatorPaths.resolve(path: projectPath))
        case let .framework(frameworkPath):
            return .framework(path: try generatorPaths.resolve(path: frameworkPath))
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return .library(
                path: try generatorPaths.resolve(path: libraryPath),
                publicHeaders: try generatorPaths.resolve(path: publicHeaders),
                swiftModuleMap: try swiftModuleMap.map { try generatorPaths.resolve(path: $0) }
            )
        case let .package(product):
            return .package(product: product)

        case let .sdk(name, status):
            return .sdk(
                name: name,
                status: .from(manifest: status)
            )
        case let .cocoapods(path):
            return .cocoapods(path: try generatorPaths.resolve(path: path))
        case let .xcFramework(path):
            return .xcFramework(path: try generatorPaths.resolve(path: path))
        case .xctest:
            return .xctest
        }
    }
}
