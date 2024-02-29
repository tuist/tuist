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
    static func from( // swiftlint:disable:this function_body_length
        manifest: ProjectDescription.TargetDependency,
        generatorPaths: GeneratorPaths,
        externalDependencies: [String: [TuistGraph.TargetDependency]]
    ) throws -> [TuistGraph.TargetDependency] {
        switch manifest {
        case let .target(name, condition):
            return [.target(name: name, condition: condition?.asGraphCondition)]
        case let .project(target, projectPath, condition):
            return [.project(
                target: target,
                path: try generatorPaths.resolve(path: projectPath),
                condition: condition?.asGraphCondition
            )]
        case let .framework(frameworkPath, status, condition):
            return [
                .framework(
                    path: try generatorPaths.resolve(path: frameworkPath),
                    status: .from(manifest: status),
                    condition: condition?.asGraphCondition
                ),
            ]
        case let .library(libraryPath, publicHeaders, swiftModuleMap, condition):
            return [
                .library(
                    path: try generatorPaths.resolve(path: libraryPath),
                    publicHeaders: try generatorPaths.resolve(path: publicHeaders),
                    swiftModuleMap: try swiftModuleMap.map { try generatorPaths.resolve(path: $0) },
                    condition: condition?.asGraphCondition
                ),
            ]
        case let .package(product, type, condition):
            switch type {
            case .macro:
                return [.package(product: product, type: .macro, condition: condition?.asGraphCondition)]
            case .runtime:
                return [.package(product: product, type: .runtime, condition: condition?.asGraphCondition)]
            case .plugin:
                return [.package(product: product, type: .plugin, condition: condition?.asGraphCondition)]
            }
        case let .sdk(name, type, status, condition):
            return [
                .sdk(
                    name: "\(type.filePrefix)\(name).\(type.fileExtension)",
                    status: .from(manifest: status),
                    condition: condition?.asGraphCondition
                ),
            ]
        case let .xcframework(path, status, condition):
            return [
                .xcframework(
                    path: try generatorPaths.resolve(path: path),
                    status: .from(manifest: status),
                    condition: condition?.asGraphCondition
                ),
            ]
        case .xctest:
            return [.xctest]
        case let .external(name, condition):
            guard let dependencies = externalDependencies[name] else {
                throw TargetDependencyMapperError.invalidExternalDependency(name: name)
            }

            return dependencies.map { $0.withCondition(condition?.asGraphCondition) }
        }
    }
}

extension ProjectDescription.PlatformFilters {
    var asGraphFilters: TuistGraph.PlatformFilters {
        Set<TuistGraph.PlatformFilter>(map(\.graphPlatformFilter))
    }
}

extension ProjectDescription.PlatformCondition {
    var asGraphCondition: TuistGraph.PlatformCondition? {
        .when(Set(platformFilters.asGraphFilters))
    }
}

extension ProjectDescription.PlatformFilter {
    fileprivate var graphPlatformFilter: TuistGraph.PlatformFilter {
        switch self {
        case .ios:
            .ios
        case .macos:
            .macos
        case .tvos:
            .tvos
        case .catalyst:
            .catalyst
        case .driverkit:
            .driverkit
        case .watchos:
            .watchos
        case .visionos:
            .visionos
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
