import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Dependency: ModelConvertible {
    init(manifest: ProjectDescription.TargetDependency, generatorPaths: GeneratorPaths) throws {
        switch manifest {
        case let .target(name):
            self = .target(name: name)
        case let .project(target, projectPath):
            self = .project(target: target, path: try generatorPaths.resolve(path: projectPath))
        case let .framework(frameworkPath):
            self = .framework(path: try generatorPaths.resolve(path: frameworkPath))
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            self = .library(path: try generatorPaths.resolve(path: libraryPath),
                            publicHeaders: try generatorPaths.resolve(path: publicHeaders),
                            swiftModuleMap: try swiftModuleMap.map { try generatorPaths.resolve(path: $0) })
        case let .package(product):
            self = .package(product: product)
        case let .sdk(name, status):
            self = .sdk(name: name, status: try TuistCore.SDKStatus(manifest: status, generatorPaths: generatorPaths))
        case let .cocoapods(path):
            self = .cocoapods(path: try generatorPaths.resolve(path: path))
        case let .xcFramework(path):
            self = .xcFramework(path: try generatorPaths.resolve(path: path))
        }
    }
}
