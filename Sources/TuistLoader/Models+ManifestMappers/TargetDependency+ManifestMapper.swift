import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - TargetDependency Mapper Error

public enum TargetDependencyMapperError: FatalError {
    case invalidExternalDependency(name: String)

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .invalidExternalDependency(name):
            return "`\(name)` is not a valid configured external dependency"
        }
    }
}

extension TuistGraph.TargetDependency {
    /// Maps a ProjectDescription.TargetDependency instance into a TuistGraph.TargetDependency instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the target dependency model.
    ///   - generatorPaths: Generator paths.
    ///   - externalDependencies: External dependencies graph.
    static func from(
        manifest: ProjectDescription.TargetDependency,
        generatorPaths: GeneratorPaths,
        externalDependencies: [String: [TuistGraph.TargetDependency]]
    ) throws -> [TuistGraph.TargetDependency] {
        switch manifest {
        case let .target(name):
            return [.target(name: name)]
        case let .project(target, projectPath):
            return [.project(target: target, path: try generatorPaths.resolve(path: projectPath))]
        case let .framework(frameworkPath):
            return [.framework(path: try generatorPaths.resolve(path: frameworkPath))]
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return [
                .library(
                    path: try generatorPaths.resolve(path: libraryPath),
                    publicHeaders: try generatorPaths.resolve(path: publicHeaders),
                    swiftModuleMap: try swiftModuleMap.map { try generatorPaths.resolve(path: $0) }
                ),
            ]
        case let .package(product):
            return [.package(product: product)]
        case let .sdk(name, type, status):
            return [
                .sdk(
                    name: "\(type.filePrefix)\(name).\(type.fileExtension)",
                    status: .from(manifest: status)
                ),
            ]
        case let .xcframework(path):
            return [.xcframework(path: try generatorPaths.resolve(path: path))]
        case .xctest:
            return [.xctest]
        case let .external(name):
            guard let dependencies = externalDependencies[name] else {
                throw TargetDependencyMapperError.invalidExternalDependency(name: name)
            }
            return dependencies
        }
    }
}

extension ProjectDescription.SDKType {
    /// The prefix associated to the type
    fileprivate var filePrefix: String {
        switch self {
        case .library:
            return "lib"
        case .framework:
            return ""
        }
    }

    /// The extension associated to the type
    fileprivate var fileExtension: String {
        switch self {
        case .library:
            return "tbd"
        case .framework:
            return "framework"
        }
    }
}
