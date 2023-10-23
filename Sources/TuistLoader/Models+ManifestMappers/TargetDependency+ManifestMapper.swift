import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - TargetDependency Mapper Error

public enum TargetDependencyMapperError: FatalError {
    case invalidExternalDependency(name: String, platform: String)

    public var type: ErrorType { .abort }

    public var description: String {
        switch self {
        case let .invalidExternalDependency(name, platform):
            return "`\(name)` is not a valid configured external dependency for platform \(platform)"
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
        case let .target(name, platformFilters):
            return [.target(name: name, platformFilters: platformFilters.asGraphFilters)]
        case let .project(target, projectPath, platformFilters):
            return [.project(target: target, path: try generatorPaths.resolve(path: projectPath), platformFilters: platformFilters.asGraphFilters)]
        case let .framework(frameworkPath, status, platformFilters):
            return [
                .framework(
                    path: try generatorPaths.resolve(path: frameworkPath),
                    status: .from(manifest: status),
                    platformFilters: platformFilters.asGraphFilters
                ),
            ]
        case let .library(libraryPath, publicHeaders, swiftModuleMap, platformFilters):
            return [
                .library(
                    path: try generatorPaths.resolve(path: libraryPath),
                    publicHeaders: try generatorPaths.resolve(path: publicHeaders),
                    swiftModuleMap: try swiftModuleMap.map { try generatorPaths.resolve(path: $0) },
                    platformFilters: platformFilters.asGraphFilters
                ),
            ]
        case let .package(product, type, platformFilters):
            switch type {
            case .macro:
                return [.package(product: product, type: .macro, platformFilters: platformFilters.asGraphFilters)]
            case .runtime:
                return [.package(product: product, type: .runtime, platformFilters: platformFilters.asGraphFilters)]
            case .plugin:
                return [.package(product: product, type: .plugin, platformFilters: platformFilters.asGraphFilters)]
            }
        case let .packagePlugin(product, _):
            logger.warning(".packagePlugin is deprecated. Use .package(product:, type: .plugin) instead.")
            return [.package(product: product, type: .plugin)]
        case let .sdk(name, type, status, platformFilters):
            return [
                .sdk(
                    name: "\(type.filePrefix)\(name).\(type.fileExtension)",
                    status: .from(manifest: status),
                    platformFilters: platformFilters.asGraphFilters
                ),
            ]
        case let .xcframework(path, status, platformFilters):
            return [
                .xcframework(
                    path: try generatorPaths.resolve(path: path),
                    status: .from(manifest: status),
                    platformFilters: platformFilters.asGraphFilters
                ),
            ]
        case .xctest:
            return [.xctest]
        case let .external(name, filters):
            // Welp dependencies.swift needs more work to support these
            guard let dependencies = externalDependencies[name] else {
                throw TargetDependencyMapperError.invalidExternalDependency(name: name, platform: "Dont commit me")
            }

            return dependencies.map({ $0.withFilters(filters.asGraphFilters) })
        }
    }
}

extension ProjectDescription.PlatformFilters {
    var asGraphFilters: TuistGraph.PlatformFilters {
        Set<TuistGraph.PlatformFilter>(map(\.graphPlatformFilter))
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
