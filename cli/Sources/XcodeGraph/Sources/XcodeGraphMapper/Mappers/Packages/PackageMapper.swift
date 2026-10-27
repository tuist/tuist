import FileSystem
import Foundation
import Mockable
import Path
import XcodeGraph

@Mockable
protocol PackageMapping {
    func map(
        _ packageInfo: PackageInfo,
        packages: [String: AbsolutePath],
        at path: AbsolutePath
    ) async throws -> Project
}

struct PackageMapper: PackageMapping {
    private let fileSystem: FileSysteming

    init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    func map(
        _ packageInfo: PackageInfo,
        packages: [String: AbsolutePath],
        at path: AbsolutePath
    ) async throws -> Project {
        var targets: [Target] = []
        for target in packageInfo.targets {
            targets.append(
                try await mapTarget(
                    target,
                    packageInfo: packageInfo,
                    packages: packages,
                    path: path
                )
            )
        }
        return Project(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path,
            name: packageInfo.name,
            organizationName: nil,
            classPrefix: nil,
            defaultKnownRegions: nil,
            developmentRegion: nil,
            options: Project.Options(
                automaticSchemesOptions: .disabled,
                disableBundleAccessors: true,
                disableShowEnvironmentVarsInScriptPhases: true,
                disableSynthesizedResourceAccessors: true,
                textSettings: Project.Options.TextSettings(
                    usesTabs: nil,
                    indentWidth: nil,
                    tabWidth: nil,
                    wrapsLines: nil
                )
            ),
            settings: Settings(configurations: [:]),
            filesGroup: .group(name: packageInfo.name),
            targets: targets,
            packages: [],
            schemes: [],
            ideTemplateMacros: nil,
            additionalFiles: [],
            resourceSynthesizers: [],
            lastUpgradeCheck: nil,
            type: .local
        )
    }

    private func mapTarget(
        _ target: PackageInfo.Target,
        packageInfo: PackageInfo,
        packages: [String: AbsolutePath],
        path: AbsolutePath
    ) async throws -> Target {
        // Some of the products, such as "regular" are approximations until XcodeGraph supports these SwiftPM-specific products
        let product: Product = switch target.type {
        case .regular:
            .staticFramework
        case .executable:
            .commandLineTool
        case .macro:
            .macro
        case .plugin:
            .commandLineTool
        case .system:
            .framework
        case .binary:
            .framework
        case .test:
            .unitTests
        }

        let directory: AbsolutePath
        switch target.type {
        case .test:
            directory = path.appending(components: "Tests", target.name)
        default:
            directory = path.appending(components: "Sources", target.name)
        }
        let sources: [SourceFile] = try await fileSystem.glob(
            directory: directory,
            include: [
                "**/*.{\(Target.validSourceExtensions.joined(separator: ","))}",
            ]
        )
        .collect()
        .map { SourceFile(path: $0) }

        let dependencies: [TargetDependency] = target.dependencies.compactMap { dependency in
            switch dependency {
            case let .target(name: name, condition: condition):
                return .target(name: name, status: .required, condition: mapCondition(condition))
            case let .byName(name: name, condition: condition):
                if let target = packageInfo.targets.first(where: { $0.name == name }) {
                    return .target(name: target.name, status: .required, condition: mapCondition(condition))
                } else {
                    if let path = packages[name] {
                        return .project(
                            target: name,
                            path: path,
                            status: .required,
                            condition: mapCondition(condition)
                        )
                    } else {
                        return .package(
                            product: name,
                            type: .runtime,
                            condition: mapCondition(condition)
                        )
                    }
                }
            case let .product(
                name: name,
                package: package,
                moduleAliases: _,
                condition: condition
            ):
                if let path = packages[package] {
                    return .project(
                        target: name,
                        path: path,
                        status: .required,
                        condition: mapCondition(condition)
                    )
                } else {
                    return .package(
                        product: name,
                        type: .runtime,
                        condition: mapCondition(condition)
                    )
                }
            }
        }

        return Target(
            name: target.name,
            destinations: Destinations(Destination.allCases),
            product: product,
            productName: nil,
            bundleId: "",
            sources: sources,
            filesGroup: .group(name: target.name),
            dependencies: dependencies
        )
    }

    private func mapCondition(_ condition: PackageInfo.PackageConditionDescription?) -> PlatformCondition? {
        guard let condition else { return nil }
        let filters: [PlatformFilter] = condition.platformNames.compactMap { name in
            switch name {
            case "ios":
                return .ios
            case "maccatalyst":
                return .catalyst
            case "macos":
                return .macos
            case "tvos":
                return .tvos
            case "watchos":
                return .watchos
            case "visionos":
                return .visionos
            default:
                return nil
            }
        }

        return .when(Set(filters))
    }
}
