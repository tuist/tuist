import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
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
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter platforms: The supported platforms.
    func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>
    ) throws -> ProjectDescription.DependenciesGraph
}

public final class SwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    public init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
    }

    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>
    ) throws -> ProjectDescription.DependenciesGraph {
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

        let externalDependencies: [String: [ProjectDescription.TargetDependency]] = packageInfos.reduce(into: [:]) { result, packageInfo in
            packageInfo.info.products.forEach { product in
                result[product.name] = product.targets.map { .project(target: $0, path: Path(packageInfo.folder.pathString)) }
            }
        }
        let externalProjects: [Path: ProjectDescription.Project] = try packageInfos.reduce(into: [:]) { result, packageInfo in
            let manifest = try ProjectDescription.Project.from(
                packageInfo: packageInfo.info,
                name: packageInfo.name,
                folder: packageInfo.folder,
                productTypes: productTypes,
                platforms: platforms,
                productToPackage: productToPackage
            )
            result[Path(packageInfo.folder.pathString)] = manifest
        }

        return DependenciesGraph(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }
}

extension ProjectDescription.Project {
    fileprivate static func from(
        packageInfo: PackageInfo,
        name: String,
        folder: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        productToPackage: [String: String]
    ) throws -> Self {
        let targets = try packageInfo.targets.compactMap { target in
            try Target.from(
                target: target,
                packageName: name,
                packageInfo: packageInfo,
                folder: folder,
                productTypes: productTypes,
                platforms: platforms,
                productToPackage: productToPackage
            )
        }
        return ProjectDescription.Project(
            name: name,
            targets: targets,
            resourceSynthesizers: []
        )
    }
}

extension ProjectDescription.Target {
    fileprivate static func from(
        target: PackageInfo.Target,
        packageName: String,
        packageInfo: PackageInfo,
        folder: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        productToPackage: [String: String]
    ) throws -> Self? {
        guard target.type == .regular else {
            logger.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        guard let product = target.mapProduct(packageInfo: packageInfo, productTypes: productTypes) else {
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

    func mapProduct(packageInfo: PackageInfo, productTypes: [String: TuistGraph.Product]) -> ProjectDescription.Product? {
        return packageInfo.products
            .filter { $0.targets.contains(name) }
            .compactMap {
                switch $0.type {
                case let .library(type):
                    if let productType = productTypes[name] {
                        return ProjectDescription.Product.from(product: productType)
                    }

                    switch type {
                    case .static, .automatic:
                        return .staticLibrary
                    case .dynamic:
                        return .dynamicLibrary
                    }
                case .executable, .plugin, .test:
                    return nil
                }
            }
            .first
    }

    func mapSources(path: AbsolutePath) -> SourceFilesList? {
        let sourcesPaths: [AbsolutePath]
        if let customSources = sources {
            sourcesPaths = customSources.map { path.appending(RelativePath($0)) }
        } else {
            sourcesPaths = [path]
        }
        guard !sourcesPaths.isEmpty else { return nil }
        return .init(globs: sourcesPaths.map(\.pathString))
    }

    func mapResources(path: AbsolutePath) -> ResourceFileElements? {
        let resourcesPaths = resources.map { path.appending(RelativePath($0.path)) }
        guard !resourcesPaths.isEmpty else { return nil }
        return .init(resources: resourcesPaths.map { .glob(pattern: Path($0.pathString)) })
    }

    func mapDependencies(
        packageName: String,
        packageInfo _: PackageInfo,
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

        let linkerDependencies: [ProjectDescription.TargetDependency] = settings.compactMap { setting in
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

        try settings.forEach { setting in
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
        switch platformName {
        case "ios":
            return .iOS
        case "macos":
            return .macOS
        case "tvos":
            return .tvOS
        case "watchos":
            return .watchOS
        default:
            throw SwiftPackageManagerGraphGeneratorError.unknownPlatform(platformName)
        }
    }
}

extension ProjectDescription.Product {
    fileprivate static func from(product: TuistGraph.Product) -> Self {
        switch product {
        case .app:
            return .app
        case .staticLibrary:
            return .staticLibrary
        case .dynamicLibrary:
            return .dynamicLibrary
        case .framework:
            return .framework
        case .staticFramework:
            return .staticFramework
        case .unitTests:
            return .unitTests
        case .uiTests:
            return .uiTests
        case .bundle:
            return .bundle
        case .commandLineTool:
            return .commandLineTool
        case .appExtension:
            return .appExtension
        case .watch2App:
            return .watch2App
        case .watch2Extension:
            return .watch2Extension
        case .tvTopShelfExtension:
            return .tvTopShelfExtension
        case .messagesExtension:
            return .messagesExtension
        case .stickerPackExtension:
            return .stickerPackExtension
        case .appClip:
            return .appClip
        }
    }
}
