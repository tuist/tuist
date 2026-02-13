import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistLogging
import TuistSupport
import XcodeGraph

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

extension XcodeGraph.TargetDependency {
    /// Maps a ProjectDescription.TargetDependency instance into a XcodeGraph.TargetDependency instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the target dependency model.
    ///   - generatorPaths: Generator paths.
    ///   - externalDependencies: External dependencies graph.
    static func from( // swiftlint:disable:this function_body_length
        manifest: ProjectDescription.TargetDependency,
        generatorPaths: GeneratorPaths,
        externalDependencies: [String: [XcodeGraph.TargetDependency]]
    ) throws -> [XcodeGraph.TargetDependency] {
        // Normalize dictionary keys to lowercase for case-insensitive lookup
        let normalizedExternalDependencies = externalDependencies
            .reduce(into: [String: [XcodeGraph.TargetDependency]]()) { result, entry in
                result[entry.key.lowercased()] = entry.value
            }

        switch manifest {
        case let .target(name, status, condition):
            return [.target(
                name: name,
                status: .from(manifest: status),
                condition: condition?.asGraphCondition
            )]
        case let .macro(name: name):
            return [.target(
                name: name,
                status: .required,
                condition: nil
            )]
        case let .project(target, projectPath, status, condition):
            return [.project(
                target: target,
                path: try generatorPaths.resolve(path: projectPath),
                status: .from(manifest: status),
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
            case .runtimeEmbedded:
                return [.package(product: product, type: .runtimeEmbedded, condition: condition?.asGraphCondition)]
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
        case let .xcframework(path, expectedSignature, status, condition):
            let signature = expectedSignature == nil ? nil :
                XcodeGraph.XCFrameworkSignature.from(expectedSignature!)
            return [
                .xcframework(
                    path: try generatorPaths.resolve(path: path),
                    expectedSignature: signature,
                    status: .from(manifest: status),
                    condition: condition?.asGraphCondition
                ),
            ]
        case .xctest:
            return [.xctest]
        case let .external(name, condition):
            guard let dependencies = externalDependencies[name] ?? normalizedExternalDependencies[name.lowercased()] else {
                throw TargetDependencyMapperError.invalidExternalDependency(name: name)
            }

            return dependencies.map { $0.withCondition(condition?.asGraphCondition) }
        }
    }
}

extension XcodeGraph.ForeignBuild.Input {
    static func from(
        manifest: ProjectDescription.Target.ForeignBuild.Input,
        generatorPaths: GeneratorPaths,
        fileSystem: FileSysteming
    ) async throws -> [XcodeGraph.ForeignBuild.Input] {
        switch manifest {
        case let .file(path):
            return [.file(try generatorPaths.resolve(path: path))]
        case let .folder(path):
            return [.folder(try generatorPaths.resolve(path: path))]
        case let .glob(path):
            let resolvedPath = try generatorPaths.resolve(path: path)
            let pattern = String(resolvedPath.pathString.dropFirst())
            let matchedPaths = try await fileSystem.glob(directory: AbsolutePath.root, include: [pattern]).collect().sorted()
            return matchedPaths.map { .file($0) }
        case let .script(script):
            return [.script(script)]
        }
    }
}

extension ProjectDescription.PlatformFilters {
    var asGraphFilters: XcodeGraph.PlatformFilters {
        Set<XcodeGraph.PlatformFilter>(map(\.graphPlatformFilter))
    }
}

extension ProjectDescription.PlatformCondition {
    var asGraphCondition: XcodeGraph.PlatformCondition? {
        .when(Set(platformFilters.asGraphFilters))
    }
}

extension ProjectDescription.PlatformFilter {
    fileprivate var graphPlatformFilter: XcodeGraph.PlatformFilter {
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
        case .swiftLibrary:
            return "libswift"
        case .framework:
            return ""
        }
    }

    /// The extension associated to the type
    fileprivate var fileExtension: String {
        switch self {
        case .library, .swiftLibrary:
            return "tbd"
        case .framework:
            return "framework"
        }
    }
}

extension XcodeGraph.XCFrameworkSignature {
    static func from(_ signature: ProjectDescription.XCFrameworkSignature) -> Self {
        switch signature {
        case .unsigned:
            return .unsigned
        case let .selfSigned(fingerprint):
            return .selfSigned(fingerprint: fingerprint)
        case let .signedWithAppleCertificate(teamIdentifier, teamName):
            return .signedWithAppleCertificate(teamIdentifier: teamIdentifier, teamName: teamName)
        }
    }
}

extension XcodeGraph.BinaryLinking {
    static func from(manifest: ProjectDescription.Target.ForeignBuild.Output.Linking) -> Self {
        switch manifest {
        case .static: return .static
        case .dynamic: return .dynamic
        }
    }
}

extension XcodeGraph.ForeignBuild.Artifact {
    static func from(
        manifest: ProjectDescription.Target.ForeignBuild.Output,
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        switch manifest {
        case let .xcframework(path, linking):
            return .xcframework(
                path: try generatorPaths.resolve(path: path),
                linking: .from(manifest: linking)
            )
        }
    }
}
