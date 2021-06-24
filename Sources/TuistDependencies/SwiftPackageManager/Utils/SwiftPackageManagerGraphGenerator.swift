import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

// MARK: - Swift Package Manager Graph Generator Errors

enum SwiftPackageManagerGraphGeneratorError: FatalError, Equatable {
    /// Thrown when no supported platforms are found for a package.
    case noSupportedPlatforms(name: String, configured: Set<ProjectDescription.Platform>, package: Set<ProjectDescription.Platform>)

    /// Thrown when `PackageInfo.Target.Dependency.byName` dependency cannot be resolved.
    case unknownByNameDependency(String)

    /// Thrown when `PackageInfo.Platform` name cannot be mapped to a `DeploymentTarget`.
    case unknownPlatform(String)

    /// Thrown when unsupported `PackageInfo.Target.TargetBuildSettingDescription` `Tool`/`SettingName` pair is found.
    case unsupportedSetting(PackageInfo.Target.TargetBuildSettingDescription.Tool, PackageInfo.Target.TargetBuildSettingDescription.SettingName)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .noSupportedPlatforms, .unknownByNameDependency, .unknownPlatform, .unsupportedSetting:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .noSupportedPlatforms(name, configured, package):
            return "No supported platform found for the \(name) dependency. Configured: \(configured), package: \(package)."
        case let .unknownByNameDependency(name):
            return "The package associated to the \(name) dependency cannot be found."
        case let .unknownPlatform(platform):
            return "The \(platform) platform is not supported."
        case let .unsupportedSetting(tool, setting):
            return "The \(tool) and \(setting) pair is not a supported setting."
        }
    }
}

// MARK: - Swift Package Manager Graph Generator

/// A protocol that defines an interface to generate the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
public protocol SwiftPackageManagerGraphGenerating {
    /// Generates the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
    /// - Parameter path: The path to the directory that contains the `checkouts` directory where `SwiftPackageManager` installed dependencies.
    /// - Parameter platforms: The supported platforms.
    func generate(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>) throws -> DependenciesGraph
}

public final class SwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    public init(swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController()) {
        self.swiftPackageManagerController = swiftPackageManagerController
    }

    public func generate(at path: AbsolutePath, platforms: Set<TuistGraph.Platform>) throws -> DependenciesGraph {
        let packageFolders = try FileHandler.shared.contentsOfDirectory(path.appending(component: "checkouts"))
        let packageInfos: [(name: String, folder: AbsolutePath, artifactsFolder: AbsolutePath, info: PackageInfo)]
        packageInfos = try packageFolders.map { packageFolder in
            let name = packageFolder.basename
            let packageInfo = try swiftPackageManagerController.loadPackageInfo(at: packageFolder)
            return (
                name: name,
                folder: packageFolder,
                artifactsFolder: path.appending(component: "artifacts").appending(component: name),
                info: packageInfo
            )
        }

        let productToPackage: [String: String] = packageInfos.reduce(into: [:]) { result, packageInfo in
            packageInfo.info.products.forEach { result[$0.name] = packageInfo.name }
        }

        return try packageInfos.reduce(DependenciesGraph.none) { result, packageInfo in
            try Self.writeProject(
                for: packageInfo.info,
                name: packageInfo.name,
                at: packageInfo.folder,
                platforms: platforms,
                productToPackage: productToPackage
            )
            let packageDependenciesGraph = DependenciesGraph(
                externalDependencies: packageInfo.info.products.reduce(into: [:]) { result, product in
                    result[product.name] = product.targets.map { .project(target: $0, path: packageInfo.folder) }
                }
            )
            return try result.merging(with: packageDependenciesGraph)
        }
    }

    private static func writeProject(
        for packageInfo: PackageInfo,
        name: String,
        at folder: AbsolutePath,
        platforms: Set<TuistGraph.Platform>,
        productToPackage: [String: String]
    ) throws {
        let targets = try packageInfo.targets.compactMap { target in
            try Self.targetDefinition(
                for: target,
                packageName: name,
                packageInfo: packageInfo,
                at: folder,
                platforms: platforms,
                productToPackage: productToPackage
            )
        }
        let project = ProjectDescription.Project(
            name: name,
            targets: targets,
            resourceSynthesizers: []
        )
        let projectData = String(data: try JSONEncoder().encode(project), encoding: .utf8)!
        try FileHandler.shared.write(projectData, path: folder.appending(component: Manifest.project.serializedFileName!), atomically: true)
    }

    private static func targetDefinition(
        for target: PackageInfo.Target,
        packageName: String,
        packageInfo: PackageInfo,
        at folder: AbsolutePath,
        platforms: Set<TuistGraph.Platform>,
        productToPackage: [String: String]
    ) throws -> ProjectDescription.Target? {
        guard target.type == .regular else {
            logger.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        guard let product = target.mapProduct(packageInfo: packageInfo) else {
            logger.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let path = folder.appending(RelativePath(target.path ?? "Sources/\(target.name)"))

        return .init(
            name: target.name,
            platform: try target.mapPlatform(configured: platforms, package: packageInfo.platforms, packageName: packageName),
            product: product,
            bundleId: "",
            infoPlist: .default,
            sources: target.mapSources(path: path),
            resources: target.mapResources(path: path),
            dependencies: try target.mapDependencies(packageName: packageName, packageInfo: packageInfo, productToPackage: productToPackage),
            settings: try target.mapSettings()
        )
    }
}

extension PackageInfo.Target {
    func mapPlatform(
        configured: Set<TuistGraph.Platform>,
        package: [PackageInfo.Platform],
        packageName: String
    ) throws -> ProjectDescription.Platform {
        let configuredPlatforms = Set(configured.map(\.descriptionPlatform))
        let packagePlatform = Set(try package.map { try $0.descriptionPlatform() })
        let validPlatforms = configuredPlatforms.intersection(packagePlatform)

        #warning("Handle multiple platforms when supported in ProjectDescription.Target")
        if validPlatforms.contains(.iOS) {
            return .iOS
        }

        guard let platform = validPlatforms.first else {
            throw SwiftPackageManagerGraphGeneratorError.noSupportedPlatforms(
                name: packageName,
                configured: configuredPlatforms,
                package: packagePlatform
            )

        }

        return platform
    }

    func mapProduct(packageInfo: PackageInfo) -> ProjectDescription.Product? {
        return packageInfo.products
            .filter { $0.targets.contains(name) }
            .compactMap {
                switch $0.type {
                case let .library(type):
                    switch type {
                    case .automatic:
                        #warning("Make this configurable from Dependencies.swift")
                        return .staticLibrary
                    case .dynamic:
                        return .dynamicLibrary
                    case .static:
                        return .staticLibrary
                    }
                case .executable, .plugin, .test:
                    return nil
                }
            }
            .first
    }

    func mapSources(path: AbsolutePath) -> SourceFilesList? {
        let sourcesPaths: [AbsolutePath]
        if let customSources = self.sources {
            sourcesPaths = customSources.map { path.appending(RelativePath($0)) }
        } else {
            sourcesPaths = [path]
        }
        guard !sourcesPaths.isEmpty else { return nil }
        return .init(globs: sourcesPaths.map(\.pathString))
    }

    func mapResources(path: AbsolutePath) -> ResourceFileElements? {
        let resourcesPaths = self.resources.map { path.appending(RelativePath($0.path)) }
        guard !resourcesPaths.isEmpty else { return nil }
        return .init(resources: resourcesPaths.map { .glob(pattern: Path($0.pathString)) })
    }

    func mapDependencies(
        packageName: String,
        packageInfo: PackageInfo,
        productToPackage: [String: String]
    ) throws -> [ProjectDescription.TargetDependency] {
        let targetDependencies: [ProjectDescription.TargetDependency] = try dependencies.map { dependency in
            switch dependency {
            case let .target(name, _):
                return .target(name: name)
            case let .product(name, package, _):
                return .project(target: name, path: Path(RelativePath("../\(package)").pathString))
            case let .byName(name, _):
                guard let package = productToPackage[name] else {
                    throw SwiftPackageManagerGraphGeneratorError.unknownByNameDependency(name)
                }

                if package == packageName {
                    return .target(name: name)
                } else {
                    return .project(target: name, path: Path(RelativePath("../\(package)").pathString))
                }
            }
        }

        let linkerDependencies: [ProjectDescription.TargetDependency] = self.settings.compactMap { setting in
            switch (setting.tool, setting.name) {
            case (.linker, .linkedFramework), (.linker, .linkedLibrary):
                return .sdk(name: setting.value[0], status: .required)
            case (.c, _), (.cxx, _), (.swift, _), (.linker, .headerSearchPath), (.linker, .define), (.linker, .unsafeFlags):
                return nil
            }
        }

        return targetDependencies + linkerDependencies
    }

    func mapSettings() throws -> ProjectDescription.Settings? {
        var cHeaderSearchPaths: [String] = []
        var cxxHeaderSearchPaths: [String] = []
        var cDefines: [String: String] = [:]
        var cxxDefines: [String: String] = [:]
        var swiftDefines: [String: String] = [:]
        var cFlags: [String] = []
        var cxxFlags: [String] = []
        var swiftFlags: [String] = []

        try self.settings.forEach { setting in
            switch (setting.tool, setting.name) {
            case (.c, .headerSearchPath):
                cHeaderSearchPaths.append(setting.value[0])
            case (.c, .define):
                let (name, value) = setting.extractDefine
                cDefines[name] = value
            case (.c, .unsafeFlags):
                cFlags.append(contentsOf: setting.value)

            case (.cxx, .define):
                let (name, value) = setting.extractDefine
                cxxDefines[name] = value
            case (.cxx, .headerSearchPath):
                cxxHeaderSearchPaths.append(setting.value[0])
            case (.cxx, .unsafeFlags):
                cxxFlags.append(contentsOf: setting.value)

            case (.swift, .define):
                let (name, value) = setting.extractDefine
                swiftDefines[name] = value
            case (.swift, .unsafeFlags):
                swiftFlags.append(contentsOf: setting.value)

            case (.linker, .linkedFramework), (.linker, .linkedLibrary):
                return // Handled as dependency

            case (.c, .linkedFramework), (.c, .linkedLibrary), (.cxx, .linkedFramework), (.cxx, .linkedLibrary),
                 (.swift, .headerSearchPath), (.swift, .linkedFramework), (.swift, .linkedLibrary),
                 (.linker, .headerSearchPath), (.linker, .define), (.linker, .unsafeFlags):
                throw SwiftPackageManagerGraphGeneratorError.unsupportedSetting(setting.tool, setting.name)
            }
        }

        // TODO: map to ProjectDescription.Settings
        return nil
    }
}

extension PackageInfo.Target.TargetBuildSettingDescription.Setting {
    fileprivate var extractDefine: (name: String, value: String) {
        let define = self.value[0]
        if define.contains("=") {
            let split = define.split(separator: "=", maxSplits: 1)
            return (name: String(split[0]), value: String(split[1]))
        } else {
            return (name: define, value: "1")
        }
    }
}

extension TuistGraph.Platform {
    fileprivate var descriptionPlatform: ProjectDescription.Platform {
        switch self {
        case .iOS:
            return .iOS
        case .macOS:
            return .macOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        }
    }
}

extension PackageInfo.Platform {
    fileprivate func descriptionPlatform() throws -> ProjectDescription.Platform {
        switch self.platformName {
        case "ios":
            return .iOS
        case "macos":
            return .macOS
        case "tvos":
            return .tvOS
        case "watchos":
            return .watchOS
        default:
            throw SwiftPackageManagerGraphGeneratorError.unknownPlatform(self.platformName)
        }
    }
}
