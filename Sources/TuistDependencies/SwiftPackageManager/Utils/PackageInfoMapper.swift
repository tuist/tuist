import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - PackageInfo Mapper Errors

enum PackageInfoMapperError: FatalError, Equatable {
    /// Thrown when the default path folder is not present.
    case defaultPathNotFound(AbsolutePath, String)

    /// Thrown when the parsing of minimum deployment target failed.
    case minDeploymentTargetParsingFailed(ProjectDescription.Platform)

    /// Thrown when no supported platforms are found for a package.
    case noSupportedPlatforms(
        name: String,
        configured: Set<ProjectDescription.Platform>,
        package: Set<ProjectDescription.Platform>
    )

    /// Thrown when `PackageInfo.Target.Dependency.byName` dependency cannot be resolved.
    case unknownByNameDependency(String)

    /// Thrown when `PackageInfo.Platform` name cannot be mapped to a `DeploymentTarget`.
    case unknownPlatform(String)

    /// Thrown when `PackageInfo.Target.Dependency.product` dependency cannot be resolved.
    case unknownProductDependency(String, String)

    /// Thrown when a target defined in a product is not present in the package
    case unknownProductTarget(package: String, product: String, target: String)

    /// Thrown when unsupported `PackageInfo.Target.TargetBuildSettingDescription` `Tool`/`SettingName` pair is found.
    case unsupportedSetting(
        PackageInfo.Target.TargetBuildSettingDescription.Tool,
        PackageInfo.Target.TargetBuildSettingDescription.SettingName
    )

    /// Thrown when a binary target defined in a package doesn't have a corresponding artifact
    case missingBinaryArtifact(package: String, target: String)

    case modulemapMissing(moduleMapPath: String, package: String, target: String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .noSupportedPlatforms, .unknownByNameDependency, .unknownPlatform, .unknownProductDependency, .unknownProductTarget,
             .modulemapMissing:
            return .abort
        case .minDeploymentTargetParsingFailed, .defaultPathNotFound, .unsupportedSetting, .missingBinaryArtifact:
            return .bug
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .defaultPathNotFound(packageFolder, targetName):
            return """
            Default source path not found for target \(targetName) in package at \(packageFolder.pathString). \
            Source path must be one of \(PackageInfoMapper.predefinedSourceDirectories.map { "\($0)/\(targetName)" })
            """
        case let .minDeploymentTargetParsingFailed(platform):
            return "The minimum deployment target for \(platform) platform cannot be parsed."
        case let .noSupportedPlatforms(name, configured, package):
            return "No supported platform found for the \(name) dependency. Configured: \(configured), package: \(package)."
        case let .unknownByNameDependency(name):
            return "The package associated to the \(name) dependency cannot be found."
        case let .unknownPlatform(platform):
            return "The \(platform) platform is not supported."
        case let .unknownProductDependency(name, package):
            return "The product \(name) of package \(package) cannot be found."
        case let .unknownProductTarget(package, product, target):
            return "The target \(target) of product \(product) cannot be found in package \(package)."
        case let .unsupportedSetting(tool, setting):
            return "The \(tool) and \(setting) pair is not a supported setting."
        case let .missingBinaryArtifact(package, target):
            return "The artifact for binary target \(target) of package \(package) cannot be found."
        case let .modulemapMissing(moduleMapPath, package, target):
            return "Target \(target) of package \(package) is a system library. Module map is missing at \(moduleMapPath)."
        }
    }
}

// MARK: - PackageInfo Mapper

/// Protocol that allows to map a `PackageInfo` to a `ProjectDescription.Project`.
public protocol PackageInfoMapping {
    /// Preprocesses SwiftPackageManager dependencies.
    /// - Parameters:
    ///   - packageInfos: All available `PackageInfo`s
    ///   - idToPackage: Mapping from an identifier to its package
    ///   - packageToFolder: Mapping from a package name to its local folder
    ///   - packageToTargetsToArtifactPaths: Mapping from a package name its targets' names to artifacts' paths
    ///   - platforms: The configured platforms
    /// - Returns: Mapped project
    func preprocess(
        packageInfos: [String: PackageInfo],
        idToPackage: [String: String],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]],
        platforms: Set<TuistGraph.Platform>
    ) throws -> PackageInfoMapper.PreprocessInfo

    /// Maps a `PackageInfo` to a `ProjectDescription.Project`.
    /// - Parameters:
    ///   - packageInfo: `PackageInfo` to be mapped
    ///   - packageInfos: All available `PackageInfo`s
    ///   - name: Name of the package
    ///   - path: Path of the package
    ///   - productTypes: Product type mapping
    ///   - baseSettings: Base settings
    ///   - targetSettings: Settings to apply to denoted targets
    ///   - configuration: Configure automatic schemes and resource accessors generation for Swift Package
    ///   - projectOptions: Additional options related to the `Project`
    ///   - targetToPlatform: Mapping from a target name to its platform
    ///   - minDeploymentTargets: Minimum support deployment target per platform
    ///   - platforms: Set of supported platforms
    ///   - targetToProducts: Mapping from a target name to its products
    ///   - targetToResolvedDependencies: Mapping from a target name to its dependencies
    ///   - targetToModuleMap: Mapping from a target name to its module map
    ///   - packageToProject: Mapping from a package name to its path
    ///   - swiftToolsVersion: The version of Swift tools that will be used to map dependencies
    /// - Returns: Mapped project
    func map(
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        name: String,
        path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary],
        projectOptions: TuistGraph.Project.Options?,
        minDeploymentTargets: [ProjectDescription.Platform: ProjectDescription.DeploymentTarget],
        platforms: Set<ProjectDescription.Platform>,
        targetToProducts: [String: Set<PackageInfo.Product>],
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        targetToModuleMap: [String: ModuleMap],
        packageToProject: [String: AbsolutePath],
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> ProjectDescription.Project?
}

public final class PackageInfoMapper: PackageInfoMapping {
    public struct PreprocessInfo {
        let platformToMinDeploymentTarget: [ProjectDescription.Platform: ProjectDescription.DeploymentTarget]
        let productToExternalDependencies: [ProjectDescription.Platform: [String: [ProjectDescription.TargetDependency]]]
        let platforms: Set<ProjectDescription.Platform>
        let targetToProducts: [String: Set<PackageInfo.Product>]
        let targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]]
        let targetToModuleMap: [String: ModuleMap]
    }

    // Predefined source directories, in order of preference.
    // https://github.com/apple/swift-package-manager/blob/751f0b2a00276be2c21c074f4b21d952eaabb93b/Sources/PackageLoading/PackageBuilder.swift#L488
    fileprivate static let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]
    fileprivate let moduleMapGenerator: SwiftPackageManagerModuleMapGenerating

    public init(moduleMapGenerator: SwiftPackageManagerModuleMapGenerating = SwiftPackageManagerModuleMapGenerator()) {
        self.moduleMapGenerator = moduleMapGenerator
    }

    /// Resolves all SwiftPackageManager dependencies.
    /// - Parameters:
    ///   - packageInfos: All available `PackageInfo`s
    ///   - idToPackage: Mapping from an identifier to its package
    ///   - packageToFolder: Mapping from a package name to its local folder
    ///   - packageToTargetsToArtifactPaths: Mapping from a package name its targets' names to artifacts' paths
    ///   - platforms: The configured platforms
    /// - Returns: Mapped project
    public func preprocess( // swiftlint:disable:this function_body_length
        packageInfos: [String: PackageInfo],
        idToPackage: [String: String],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]],
        platforms: Set<TuistGraph.Platform>
    ) throws -> PreprocessInfo {
        let targetDependencyToFramework: [String: Path] = try packageInfos.reduce(into: [:]) { result, packageInfo in
            try packageInfo.value.targets.forEach { target in
                guard target.type == .binary else { return }
                if let path = target.path {
                    // local binary
                    result[target.name] = Path(packageToFolder[packageInfo.key]!.appending(RelativePath(path)).pathString)
                } else {
                    // remote binaries are checked out by SPM in artifacts/<Package.name>/<Target>.xcframework
                    // or in artifacts/<Package.identity>/<Target>.xcframework when using SPM 5.6 and later
                    guard let artifactPath = packageToTargetsToArtifactPaths[packageInfo.key]?[target.name] else {
                        throw PackageInfoMapperError.missingBinaryArtifact(package: packageInfo.key, target: target.name)
                    }
                    result[target.name] = Path(artifactPath.pathString)
                }
            }
        }

        let targetToProducts: [String: Set<PackageInfo.Product>] = packageInfos.values.reduce(into: [:]) { result, packageInfo in
            for product in packageInfo.products {
                var targetsToProcess = Set(product.targets)
                while !targetsToProcess.isEmpty {
                    let target = targetsToProcess.removeFirst()
                    let alreadyProcessed = result[target]?.contains(product) ?? false
                    guard !alreadyProcessed else {
                        continue
                    }
                    result[target, default: []].insert(product)
                    let dependencies = packageInfo.targets.first(where: { $0.name == target })!.dependencies
                    for dependency in dependencies {
                        switch dependency {
                        case let .target(name, _):
                            targetsToProcess.insert(name)
                        case let .byName(name, _) where packageInfo.targets.contains(where: { $0.name == name }):
                            targetsToProcess.insert(name)
                        case .byName, .product:
                            continue
                        }
                    }
                }
            }
        }

        let resolvedDependencies: [String: [ResolvedDependency]] = try packageInfos.values
            .reduce(into: [:]) { result, packageInfo in
                try packageInfo.targets
                    .filter { targetToProducts[$0.name] != nil }
                    .forEach { target in
                        guard result[target.name] == nil else { return }
                        result[target.name] = try ResolvedDependency.from(
                            dependencies: target.dependencies,
                            packageInfo: packageInfo,
                            packageInfos: packageInfos,
                            idToPackage: idToPackage,
                            targetDependencyToFramework: targetDependencyToFramework
                        )
                    }
            }

        var externalDependencies: [ProjectDescription.Platform: [String: [ProjectDescription.TargetDependency]]] = .init()

        for platform in platforms {
            externalDependencies[ProjectDescription.Platform.from(graph: platform)] = try packageInfos
                .reduce(into: [:]) { result, packageInfo in
                    try packageInfo.value.products.forEach { product in
                        result[product.name] = try product.targets.flatMap { target in
                            try ResolvedDependency.fromTarget(
                                name: target,
                                targetDependencyToFramework: targetDependencyToFramework,
                                condition: nil
                            )
                            .map {
                                switch $0 {
                                case let .xcframework(path, _):
                                    return .xcframework(path: path)
                                case let .target(name, _):
                                    // When multiple platforms are supported, add the platform name as a suffix to the target
                                    let targetName = platforms.count == 1 ? name : "\(name)_\(platform.rawValue)"
                                    return .project(target: targetName, path: Path(packageToFolder[packageInfo.key]!.pathString))
                                case .externalTarget:
                                    throw PackageInfoMapperError.unknownProductTarget(
                                        package: packageInfo.key,
                                        product: product.name,
                                        target: target
                                    )
                                }
                            }
                        }
                    }
                }
        }

        let version = try Version(versionString: try System.shared.swiftVersion(), usesLenientParsing: true)
        let minDeploymentTargets = Platform.oldestVersions(isLegacy: version < TSCUtility.Version(5, 7, 0)).reduce(
            into: [ProjectDescription.Platform: ProjectDescription.DeploymentTarget]()
        ) { acc, next in
            switch next.key {
            case .iOS:
                acc[.iOS] = .iOS(targetVersion: next.value, devices: [.ipad, .iphone])
            case .macOS:
                acc[.macOS] = .macOS(targetVersion: next.value)
            case .tvOS:
                acc[.tvOS] = .tvOS(targetVersion: next.value)
            case .watchOS:
                acc[.watchOS] = .watchOS(targetVersion: next.value)
            }
        }

        let targetToModuleMap: [String: ModuleMap]
        targetToModuleMap = try packageInfos.reduce(into: [:]) { result, packageInfo in
            try packageInfo.value.targets.forEach { target in
                switch target.type {
                case .system:
                    /// System library targets assume the module map is located at the source directory root
                    /// https://github.com/apple/swift-package-manager/blob/main/Sources/PackageLoading/ModuleMapGenerator.swift
                    let packagePath = try target.basePath(packageFolder: packageToFolder[packageInfo.key]!)
                    let moduleMapPath = packagePath.appending(component: ModuleMap.filename)

                    guard FileHandler.shared.exists(moduleMapPath), !FileHandler.shared.isFolder(moduleMapPath) else {
                        throw PackageInfoMapperError.modulemapMissing(
                            moduleMapPath: moduleMapPath.pathString,
                            package: packageInfo.key,
                            target: target.name
                        )
                    }

                    result[target.name] = ModuleMap.custom(moduleMapPath)
                case .regular:
                    result[target.name] = try moduleMapGenerator.generate(
                        moduleName: target.name,
                        publicHeadersPath: target.publicHeadersPath(packageFolder: packageToFolder[packageInfo.key]!)
                    )
                default:
                    return
                }
            }
        }

        return .init(
            platformToMinDeploymentTarget: minDeploymentTargets,
            productToExternalDependencies: externalDependencies,
            platforms: Set(platforms.map { ProjectDescription.Platform.from(graph: $0) }),
            targetToProducts: targetToProducts,
            targetToResolvedDependencies: resolvedDependencies,
            targetToModuleMap: targetToModuleMap
        )
    }

    // swiftlint:disable:next function_body_length
    public func map(
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        name: String,
        path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary],
        projectOptions: TuistGraph.Project.Options?,
        minDeploymentTargets: [ProjectDescription.Platform: ProjectDescription.DeploymentTarget],
        platforms: Set<ProjectDescription.Platform>,
        targetToProducts: [String: Set<PackageInfo.Product>],
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        targetToModuleMap: [String: ModuleMap],
        packageToProject: [String: AbsolutePath],
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> ProjectDescription.Project? {
        // Hardcoded mapping for some well known libraries, until the logic can handle those properly
        let productTypes = productTypes.merging(
            // Force dynamic frameworks
            Dictionary(
                uniqueKeysWithValues: [
                    "Checksum", // https://github.com/rnine/Checksum
                    "RxSwift", // https://github.com/ReactiveX/RxSwift
                ].map {
                    ($0, .framework)
                }
            ),
            uniquingKeysWith: { userDefined, _ in userDefined }
        )

        let targetSettings = targetSettings.merging(
            // Force enable testing search paths
            Dictionary(
                uniqueKeysWithValues: [
                    "Nimble", // https://github.com/Quick/Nimble
                    "Quick", // https://github.com/Quick/Quick
                    "RxTest", // https://github.com/ReactiveX/RxSwift
                    "RxTest-Dynamic", // https://github.com/ReactiveX/RxSwift
                    "SnapshotTesting", // https://github.com/pointfreeco/swift-snapshot-testing
                    "SwiftyMocky", // https://github.com/MakeAWishFoundation/SwiftyMocky
                    "TempuraTesting", // https://github.com/BendingSpoons/tempura-swift
                    "TSCTestSupport", // https://github.com/apple/swift-tools-support-core
                    "ViewInspector", // https://github.com/nalexn/ViewInspector
                ].map {
                    ($0, ["ENABLE_TESTING_SEARCH_PATHS": "YES"])
                }
            ),
            uniquingKeysWith: { userDefined, defaultDictionary in
                userDefined.merging(defaultDictionary, uniquingKeysWith: { userDefined, _ in userDefined })
            }
        )

        let targets: [ProjectDescription.Target] = try packageInfo.targets
            .flatMap { target -> [ProjectDescription.Target] in
                guard let products = targetToProducts[target.name] else { return [] }

                return try platforms.compactMap { platform in
                    try ProjectDescription.Target.from(
                        target: target,
                        products: products,
                        packageName: name,
                        packageInfo: packageInfo,
                        packageInfos: packageInfos,
                        packageFolder: path,
                        packageToProject: packageToProject,
                        productTypes: productTypes,
                        baseSettings: baseSettings,
                        targetSettings: targetSettings,
                        platform: platform,
                        minDeploymentTargets: minDeploymentTargets,
                        targetToResolvedDependencies: targetToResolvedDependencies,
                        targetToModuleMap: targetToModuleMap,
                        addPlatformSuffix: platforms.count != 1
                    )
                }
            }

        guard !targets.isEmpty else {
            return nil
        }

        let options: ProjectDescription.Project.Options
        if let projectOptions = projectOptions {
            options = .from(manifest: projectOptions)
        } else {
            options = .options(
                automaticSchemesOptions: .disabled,
                disableSynthesizedResourceAccessors: true
            )
        }

        return ProjectDescription.Project(
            name: name,
            options: options,
            settings: packageInfo.projectSettings(
                swiftToolsVersion: swiftToolsVersion,
                buildConfigs: baseSettings.configurations.map { key, _ in key }
            ),
            targets: targets,
            resourceSynthesizers: .default
        )
    }

    fileprivate class func sanitize(targetName: String) -> String {
        targetName.replacingOccurrences(of: ".", with: "_")
    }
}

extension ProjectDescription.Target {
    // swiftlint:disable:next function_body_length
    fileprivate static func from(
        target: PackageInfo.Target,
        products: Set<PackageInfo.Product>,
        packageName: String,
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        packageFolder: AbsolutePath,
        packageToProject: [String: AbsolutePath],
        productTypes: [String: TuistGraph.Product],
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary],
        platform: ProjectDescription.Platform,
        minDeploymentTargets: [ProjectDescription.Platform: ProjectDescription.DeploymentTarget],
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        targetToModuleMap: [String: ModuleMap],
        addPlatformSuffix: Bool
    ) throws -> Self? {
        guard target.type.isSupported else {
            logger.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        guard let product = ProjectDescription.Product.from(name: target.name, products: products, productTypes: productTypes)
        else {
            logger.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let path = try target.basePath(packageFolder: packageFolder)

        let moduleMap = targetToModuleMap[target.name]!

        let deploymentTarget = try ProjectDescription.DeploymentTarget.from(
            platform: platform,
            minDeploymentTargets: minDeploymentTargets,
            package: packageInfo.platforms,
            packageName: packageName
        )

        var publicHeadersPath: AbsolutePath?
        var headers: ProjectDescription.Headers?
        var sources: SourceFilesList?
        var resources: ResourceFileElements?

        if target.type.supportsPublicHeaderPath {
            publicHeadersPath = try target.publicHeadersPath(packageFolder: packageFolder)
            headers = try Headers.from(moduleMap: moduleMap, publicHeadersPath: publicHeadersPath!)
        }

        if target.type.supportsSources {
            sources = SourceFilesList.from(sources: target.sources, path: path, excluding: target.exclude)
        }

        if target.type.supportsResources {
            resources = ResourceFileElements.from(
                sources: target.sources,
                resources: target.resources,
                path: path,
                excluding: target.exclude
            )
        }

        var dependencies: [ProjectDescription.TargetDependency] = []

        if target.type.supportsDependencies {
            let resolvedDependencies = targetToResolvedDependencies[target.name] ?? []

            dependencies = try ProjectDescription.TargetDependency.from(
                resolvedDependencies: resolvedDependencies,
                platform: platform,
                settings: target.settings,
                packageToProject: packageToProject,
                addPlatformSuffix: addPlatformSuffix
            )
        }

        let settings = try Settings.from(
            target: target,
            packageFolder: packageFolder,
            packageName: packageName,
            packageInfos: packageInfos,
            packageToProject: packageToProject,
            targetToResolvedDependencies: targetToResolvedDependencies,
            settings: target.settings,
            platform: platform,
            targetToModuleMap: targetToModuleMap,
            baseSettings: baseSettings,
            targetSettings: targetSettings
        )

        return ProjectDescription.Target(
            name: addPlatformSuffix ? "\(PackageInfoMapper.sanitize(targetName: target.name))_\(platform.rawValue)" :
                PackageInfoMapper
                .sanitize(targetName: target.name),
            platform: platform,
            product: product,
            productName: PackageInfoMapper
                .sanitize(targetName: target.name)
                .replacingOccurrences(of: "-", with: "_"),
            bundleId: target.name
                .replacingOccurrences(of: "_", with: "."),
            deploymentTarget: deploymentTarget,
            infoPlist: .default,
            sources: sources,
            resources: resources,
            headers: headers,
            dependencies: dependencies,
            settings: settings
        )
    }
}

extension ProjectDescription.DeploymentTarget {
    fileprivate static func from(
        platform: ProjectDescription.Platform,
        minDeploymentTargets: [ProjectDescription.Platform: ProjectDescription.DeploymentTarget],
        package: [PackageInfo.Platform],
        packageName _: String
    ) throws -> Self {
        if let packagePlatform = package.first(where: { $0.tuistPlatformName == platform.rawValue }) {
            // Deployment targets below the minimum one raises warnings
            let targetVersion = try Self.max(packagePlatform.version, minDeploymentTargets[platform]?.targetVersion)

            switch platform {
            case .iOS:
                let hasMacCatalyst = package.contains(where: { $0.platformName == "maccatalyst" })
                return .iOS(
                    targetVersion: targetVersion,
                    devices: hasMacCatalyst ? [.iphone, .ipad, .mac] : [.iphone, .ipad]
                )
            case .macOS:
                return .macOS(targetVersion: targetVersion)
            case .watchOS:
                return .watchOS(targetVersion: targetVersion)
            case .tvOS:
                return .tvOS(targetVersion: targetVersion)
            }
        } else {
            return minDeploymentTargets[platform]!
        }
    }

    fileprivate static func max(_ lVersionString: String, _ rVersionString: String?) throws -> String {
        guard let rVersionString = rVersionString else { return lVersionString }
        let lVersion = try Version(versionString: lVersionString, usesLenientParsing: true)
        let rVersion = try Version(versionString: rVersionString, usesLenientParsing: true)
        return lVersion > rVersion ? lVersionString : rVersionString
    }
}

extension ProjectDescription.Product {
    fileprivate static func from(
        name: String,
        products: Set<PackageInfo.Product>,
        productTypes: [String: TuistGraph.Product]
    ) -> Self? {
        if let productType = productTypes[name] {
            return ProjectDescription.Product.from(product: productType)
        }

        var hasLibraryProducts = false
        let product: ProjectDescription.Product? = products.map(\.type).reduce(nil) { result, productType in
            switch productType {
            case let .library(type):
                hasLibraryProducts = true
                switch type {
                case .automatic:
                    return result
                case .static:
                    return .staticFramework
                case .dynamic:
                    if result == .staticFramework {
                        // If any of the products is static, the target must be static
                        return result
                    } else {
                        return .framework
                    }
                }
            case .executable, .plugin, .test:
                return result
            }
        }

        if product != nil {
            return product
        } else if hasLibraryProducts {
            // only automatic products, default to static framework
            return .staticFramework
        } else {
            // only executable, plugin, or test products, ignore it
            return nil
        }
    }
}

extension SourceFilesList {
    fileprivate static func from(sources: [String]?, path: AbsolutePath, excluding: [String]) -> Self? {
        let sourcesPaths: [AbsolutePath]
        if let customSources = sources {
            sourcesPaths = customSources.map { source in
                let absolutePath = path.appending(RelativePath(source))
                if absolutePath.extension == nil {
                    return absolutePath.appending(component: "**")
                }
                return absolutePath
            }
        } else {
            sourcesPaths = [path.appending(component: "**")]
        }
        guard !sourcesPaths.isEmpty else { return nil }
        return .init(
            globs: sourcesPaths.map { absolutePath -> ProjectDescription.SourceFileGlob in
                .glob(
                    Path(absolutePath.pathString),
                    excluding: excluding.map {
                        let excludePath = path.appending(RelativePath($0))
                        let excludeGlob = excludePath.extension != nil ? excludePath : excludePath.appending(component: "**")
                        return Path(excludeGlob.pathString)
                    }
                )
            }
        )
    }
}

extension ResourceFileElements {
    fileprivate static func from(
        sources: [String]?,
        resources: [PackageInfo.Target.Resource],
        path: AbsolutePath,
        excluding: [String]
    ) -> Self? {
        /// Handles the conversion of a `.copy` resource rule of SPM
        ///
        /// - Parameters:
        ///   - resourceAbsolutePath: The absolute path of that resource
        /// - Returns: A ProjectDescription.ResourceFileElement mapped from a `.copy` resource rule of SPM
        func handleCopyResource(resourceAbsolutePath: AbsolutePath) -> ProjectDescription.ResourceFileElement {
            .folderReference(path: Path(resourceAbsolutePath.pathString))
        }

        /// Handles the conversion of a `.process` resource rule of SPM
        ///
        /// - Parameters:
        ///   - resourceAbsolutePath: The absolute path of that resource
        /// - Returns: A ProjectDescription.ResourceFileElement mapped from a `.process` resource rule of SPM
        func handleProcessResource(resourceAbsolutePath: AbsolutePath) -> ProjectDescription.ResourceFileElement {
            let absolutePathGlob = resourceAbsolutePath.extension != nil ? resourceAbsolutePath : resourceAbsolutePath
                .appending(component: "**")
            return .glob(
                pattern: Path(absolutePathGlob.pathString),
                excluding: excluding.map {
                    let excludePath = path.appending(RelativePath($0))
                    let excludeGlob = excludePath.extension != nil ? excludePath : excludePath.appending(component: "**")
                    return Path(excludeGlob.pathString)
                }
            )
        }

        var resourceFileElements: [ProjectDescription.ResourceFileElement] = resources.map {
            let resourceAbsolutePath = path.appending(RelativePath($0.path))

            switch $0.rule {
            case .copy:
                // Single files or opaque directories are handled like a .process rule
                if !FileHandler.shared.isFolder(resourceAbsolutePath) || resourceAbsolutePath.isOpaqueDirectory {
                    return handleProcessResource(resourceAbsolutePath: resourceAbsolutePath)
                } else {
                    return handleCopyResource(resourceAbsolutePath: resourceAbsolutePath)
                }
            case .process:
                return handleProcessResource(resourceAbsolutePath: resourceAbsolutePath)
            }
        }

        // Add default resources path if necessary
        // They are handled like a `.process` rule
        if sources == nil {
            resourceFileElements += defaultResourcePaths(from: path).map { handleProcessResource(resourceAbsolutePath: $0) }
        }

        // Check for empty resource files
        guard !resourceFileElements.isEmpty else { return nil }

        return .init(resources: resourceFileElements)
    }

    // These files are automatically added as resource if they are inside targets directory.
    // Check https://developer.apple.com/documentation/swift_packages/bundling_resources_with_a_swift_package
    private static let defaultSpmResourceFileExtensions = [
        "xib",
        "storyboard",
        "xcdatamodeld",
        "xcmappingmodel",
        "xcassets",
        "strings",
    ]

    private static func defaultResourcePaths(from path: AbsolutePath) -> [AbsolutePath] {
        ResourceFileElements.defaultSpmResourceFileExtensions.flatMap {
            FileHandler.shared.glob(path, glob: "**/*.\($0)")
        }
    }
}

extension ProjectDescription.TargetDependency {
    fileprivate static func from(
        resolvedDependencies: [PackageInfoMapper.ResolvedDependency],
        platform: ProjectDescription.Platform,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        packageToProject: [String: AbsolutePath],
        addPlatformSuffix: Bool
    ) throws -> [Self] {
        let targetDependencies = resolvedDependencies.compactMap { dependency -> Self? in
            if let condition = dependency.condition, !condition.platforms.contains(platform) {
                return nil
            }
            switch dependency {
            case let .target(name, _):
                return .target(name: addPlatformSuffix ? "\(name)_\(platform.rawValue)" : name)
            case let .xcframework(path, _):
                return .xcframework(path: path)
            case let .externalTarget(project, target, _):
                return .project(
                    target: addPlatformSuffix ? "\(target)_\(platform.rawValue)" : target,
                    path: Path(packageToProject[project]!.pathString)
                )
            }
        }

        let linkerDependencies: [ProjectDescription.TargetDependency] = settings.compactMap { setting in
            if let condition = setting.condition {
                guard condition.platformNames.contains(platform.rawValue) else {
                    return nil
                }
            }

            switch (setting.tool, setting.name) {
            case (.linker, .linkedFramework):
                return .sdk(name: setting.value[0], type: .framework, status: .required)
            case (.linker, .linkedLibrary):
                return .sdk(name: setting.value[0], type: .library, status: .required)
            case (.c, _), (.cxx, _), (.swift, _), (.linker, .headerSearchPath), (.linker, .define), (.linker, .unsafeFlags):
                return nil
            }
        }

        return targetDependencies + linkerDependencies
    }
}

extension ProjectDescription.Headers {
    fileprivate static func from(moduleMap: ModuleMap, publicHeadersPath: AbsolutePath) throws -> Self? {
        // As per SPM logic, headers should be added only when using the umbrella header without modulemap:
        // https://github.com/apple/swift-package-manager/blob/9b9bed7eaf0f38eeccd0d8ca06ae08f6689d1c3f/Sources/Xcodeproj/pbxproj.swift#L588-L609
        switch moduleMap {
        case .header, .nestedHeader:
            let publicHeaders = FileHandler.shared.filesAndDirectoriesContained(in: publicHeadersPath)!
                .filter { $0.extension == "h" }
            let list: [FileListGlob] = publicHeaders.map { .glob(Path($0.pathString)) }
            return .headers(public: .list(list))
        case .none, .custom, .directory:
            return nil
        }
    }
}

extension ProjectDescription.Settings {
    // swiftlint:disable:next function_body_length
    fileprivate static func from(
        target: PackageInfo.Target,
        packageFolder: AbsolutePath,
        packageName: String,
        packageInfos: [String: PackageInfo],
        packageToProject: [String: AbsolutePath],
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        platform: ProjectDescription.Platform,
        targetToModuleMap: [String: ModuleMap],
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary]
    ) throws -> Self? {
        var headerSearchPaths: [String] = []
        var defines = ["SWIFT_PACKAGE": "1"]
        var swiftDefines = ["SWIFT_PACKAGE"]
        var cFlags: [String] = []
        var cxxFlags: [String] = []
        var swiftFlags: [String] = []
        var linkerFlags: [String] = []

        let mainPath = try target.basePath(packageFolder: packageFolder)
        let mainRelativePath = mainPath.relative(to: packageFolder)

        let moduleMap = targetToModuleMap[target.name]!
        if moduleMap != .none, target.type != .system {
            let publicHeadersPath = try target.publicHeadersPath(packageFolder: packageFolder)
            let publicHeadersRelativePath = publicHeadersPath.relative(to: packageFolder)
            headerSearchPaths.append("$(SRCROOT)/\(publicHeadersRelativePath.pathString)")
        }

        let allDependencies = Self.recursiveTargetDependencies(
            of: target,
            packageName: packageName,
            packageInfos: packageInfos,
            targetToResolvedDependencies: targetToResolvedDependencies
        )

        headerSearchPaths += try allDependencies
            .compactMap { dependency in
                // Add dependencies search paths if they require a modulemap
                guard let packagePath = packageToProject[dependency.package] else { return nil }
                let headersPath = try dependency.target.publicHeadersPath(packageFolder: packagePath)
                let moduleMap = targetToModuleMap[dependency.target.name]!
                switch moduleMap {
                case .none, .header, .nestedHeader:
                    return nil
                case .directory, .custom:
                    return "$(SRCROOT)/\(headersPath.relative(to: packageFolder))"
                }
            }
            .sorted()

        if target.type.supportsCustomSettings {
            try settings.forEach { setting in
                if let condition = setting.condition {
                    guard condition.platformNames.contains(platform.rawValue) else {
                        return
                    }
                }

                switch (setting.tool, setting.name) {
                case (.c, .headerSearchPath), (.cxx, .headerSearchPath):
                    headerSearchPaths.append("$(SRCROOT)/\(mainRelativePath.pathString)/\(setting.value[0])")
                case (.c, .define), (.cxx, .define):
                    let (name, value) = setting.extractDefine
                    defines[name] = value
                case (.c, .unsafeFlags):
                    cFlags.append(contentsOf: setting.value)
                case (.cxx, .unsafeFlags):
                    cxxFlags.append(contentsOf: setting.value)
                case (.swift, .define):
                    swiftDefines.append(setting.value[0])
                case (.swift, .unsafeFlags):
                    swiftFlags.append(contentsOf: setting.value)
                case (.linker, .unsafeFlags):
                    linkerFlags.append(contentsOf: setting.value)

                case (.linker, .linkedFramework), (.linker, .linkedLibrary):
                    // Handled as dependency
                    return

                case (.c, .linkedFramework), (.c, .linkedLibrary), (.cxx, .linkedFramework), (.cxx, .linkedLibrary),
                     (.swift, .headerSearchPath), (.swift, .linkedFramework), (.swift, .linkedLibrary),
                     (.linker, .headerSearchPath), (.linker, .define):
                    throw PackageInfoMapperError.unsupportedSetting(setting.tool, setting.name)
                }
            }
        }

        var settingsDictionary: ProjectDescription.SettingsDictionary = [
            // Xcode settings configured by SPM by default
            "ALWAYS_SEARCH_USER_PATHS": "YES",
            "CLANG_ENABLE_OBJC_WEAK": "NO",
            "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "NO",
            "FRAMEWORK_SEARCH_PATHS": ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"],
            "GCC_NO_COMMON_BLOCKS": "NO",
            "USE_HEADERMAP": "NO",
            // Disable warnings in generated projects
            "GCC_WARN_INHIBIT_ALL_WARNINGS": "YES",
            "SWIFT_SUPPRESS_WARNINGS": "YES",
        ]

        if let moduleMapPath = moduleMap.path {
            settingsDictionary["MODULEMAP_FILE"] = .string("$(SRCROOT)/\(moduleMapPath.relative(to: packageFolder))")
        }

        if !headerSearchPaths.isEmpty {
            settingsDictionary["HEADER_SEARCH_PATHS"] = .array(["$(inherited)"] + headerSearchPaths.map { $0 })
        }

        if !defines.isEmpty {
            let sortedDefines = defines.sorted { $0.key < $1.key }
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(["$(inherited)"] + sortedDefines.map { key, value in
                "\(key)=\(value.spm_shellEscaped())"
            })
        }

        if !swiftDefines.isEmpty {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = .array(["$(inherited)"] + swiftDefines)
        }

        if !cFlags.isEmpty {
            settingsDictionary["OTHER_CFLAGS"] = .array(["$(inherited)"] + cFlags)
        }

        if !cxxFlags.isEmpty {
            settingsDictionary["OTHER_CPLUSPLUSFLAGS"] = .array(["$(inherited)"] + cxxFlags)
        }

        if !swiftFlags.isEmpty {
            settingsDictionary["OTHER_SWIFT_FLAGS"] = .array(["$(inherited)"] + swiftFlags)
        }

        if !linkerFlags.isEmpty {
            settingsDictionary["OTHER_LDFLAGS"] = .array(["$(inherited)"] + linkerFlags)
        }

        if let settingsToOverride = targetSettings[target.name] {
            let projectDescriptionSettingsToOverride = ProjectDescription.SettingsDictionary
                .from(settingsDictionary: settingsToOverride)
            settingsDictionary.merge(projectDescriptionSettingsToOverride)
        }

        return .from(settings: baseSettings, adding: settingsDictionary, packageFolder: packageFolder)
    }

    fileprivate struct PackageTarget: Hashable {
        let package: String
        let target: PackageInfo.Target
    }

    fileprivate static func recursiveTargetDependencies(
        of target: PackageInfo.Target,
        packageName: String,
        packageInfos: [String: PackageInfo],
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]]
    ) -> Set<PackageTarget> {
        let result = transitiveClosure(
            [PackageTarget(package: packageName, target: target)],
            successors: { packageTarget in
                let resolvedDependencies = targetToResolvedDependencies[packageTarget.target.name] ?? []
                return resolvedDependencies.flatMap { resolvedDependency -> [PackageTarget] in
                    switch resolvedDependency {
                    case let .target(name, _):
                        guard let packageInfo = packageInfos[packageTarget.package],
                              let target = packageInfo.targets.first(where: { $0.name == name })
                        else {
                            return []
                        }
                        return [PackageTarget(package: packageTarget.package, target: target)]
                    case let .externalTarget(package, target, _):
                        guard let packageInfo = packageInfos[package] else { return [] }
                        return packageInfo.targets
                            .filter { $0.name == target }
                            .map {
                                PackageTarget(package: package, target: $0)
                            }
                    case .xcframework:
                        return []
                    }
                }
            }
        )
        return result
    }
}

extension PackageInfo.Target.TargetBuildSettingDescription.Setting {
    fileprivate var extractDefine: (name: String, value: String) {
        let define = value[0]
        if define.contains("=") {
            let split = define.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
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
        case "ios", "maccatalyst":
            return .iOS
        case "macos":
            return .macOS
        case "tvos":
            return .tvOS
        case "watchos":
            return .watchOS
        default:
            throw PackageInfoMapperError.unknownPlatform(platformName)
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
        case .xpc:
            return .xpc
        }
    }
}

extension ProjectDescription.SettingsDictionary {
    fileprivate static func from(settingsDictionary: TuistGraph.SettingsDictionary) -> Self {
        settingsDictionary.mapValues { value in
            switch value {
            case let .string(stringValue):
                return ProjectDescription.SettingValue.string(stringValue)
            case let .array(arrayValue):
                return ProjectDescription.SettingValue.array(arrayValue)
            }
        }
    }
}

extension ProjectDescription.Settings {
    fileprivate static func from(
        settings: TuistGraph.Settings,
        adding: ProjectDescription.SettingsDictionary,
        packageFolder: AbsolutePath
    ) -> Self {
        .settings(
            base: .from(settingsDictionary: settings.base).merging(adding, uniquingKeysWith: { $1 }),
            configurations: settings.configurations
                .map { buildConfiguration, configuration in
                    .from(buildConfiguration: buildConfiguration, configuration: configuration, packageFolder: packageFolder)
                }
                .sorted { $0.name.rawValue < $1.name.rawValue },
            defaultSettings: .from(defaultSettings: settings.defaultSettings)
        )
    }
}

extension ProjectDescription.Configuration {
    fileprivate static func from(
        buildConfiguration: BuildConfiguration,
        configuration: TuistGraph.Configuration?,
        packageFolder: AbsolutePath
    ) -> Self {
        let name = ConfigurationName(stringLiteral: buildConfiguration.name)
        let settings = ProjectDescription.SettingsDictionary.from(settingsDictionary: configuration?.settings ?? [:])
        let xcconfig = configuration?.xcconfig.map { Path($0.relative(to: packageFolder).pathString) }
        switch buildConfiguration.variant {
        case .debug:
            return .debug(name: name, settings: settings, xcconfig: xcconfig)
        case .release:
            return .release(name: name, settings: settings, xcconfig: xcconfig)
        }
    }
}

extension ProjectDescription.DefaultSettings {
    fileprivate static func from(defaultSettings: TuistGraph.DefaultSettings) -> Self {
        switch defaultSettings {
        case let .recommended(excluding):
            return .recommended(excluding: excluding)
        case let .essential(excluding):
            return .essential(excluding: excluding)
        case .none:
            return .none
        }
    }
}

extension ProjectDescription.DeploymentTarget {
    fileprivate static func from(deploymentTarget: TuistGraph.DeploymentTarget) -> Self {
        switch deploymentTarget {
        case let .iOS(version, devices, supportsMacDesignedForIOS):
            return .iOS(
                targetVersion: version,
                devices: .from(devices: devices),
                supportsMacDesignedForIOS: supportsMacDesignedForIOS
            )
        case let .macOS(version):
            return .macOS(targetVersion: version)
        case let .tvOS(version):
            return .tvOS(targetVersion: version)
        case let .watchOS(version):
            return .watchOS(targetVersion: version)
        }
    }
}

extension ProjectDescription.DeploymentDevice {
    fileprivate static func from(devices: TuistGraph.DeploymentDevice) -> Self {
        .init(rawValue: devices.rawValue)
    }
}

extension PackageInfo {
    fileprivate func projectSettings(
        swiftToolsVersion: TSCUtility.Version?,
        buildConfigs: [BuildConfiguration]? = nil
    ) -> ProjectDescription.Settings? {
        var settingsDictionary: ProjectDescription.SettingsDictionary = [:]

        if let cLanguageStandard = cLanguageStandard {
            settingsDictionary["GCC_C_LANGUAGE_STANDARD"] = .string(cLanguageStandard)
        }

        if let cxxLanguageStandard = cxxLanguageStandard {
            settingsDictionary["CLANG_CXX_LANGUAGE_STANDARD"] = .string(cxxLanguageStandard)
        }

        if let swiftLanguageVersion = swiftVersion(for: swiftToolsVersion) {
            settingsDictionary["SWIFT_VERSION"] = .string(swiftLanguageVersion)
        }

        if let buildConfigs = buildConfigs {
            let configs = buildConfigs
                .sorted()
                .map { config -> ProjectDescription.Configuration in
                    switch config.variant {
                    case .debug:
                        return ProjectDescription.Configuration.debug(name: .configuration(config.name))
                    case .release:
                        return ProjectDescription.Configuration.release(name: .configuration(config.name))
                    }
                }
            return .settings(base: settingsDictionary, configurations: configs)
        } else {
            return settingsDictionary.isEmpty ? nil : .settings(base: settingsDictionary)
        }
    }

    private func swiftVersion(for configuredSwiftVersion: TSCUtility.Version?) -> String? {
        /// Take the latest swift version compatible with the configured one
        let maxAllowedSwiftLanguageVersion = swiftLanguageVersions?
            .filter {
                guard let configuredSwiftVersion = configuredSwiftVersion else {
                    return true
                }
                return $0 <= configuredSwiftVersion
            }
            .sorted()
            .last

        return maxAllowedSwiftLanguageVersion?.description
    }
}

extension PackageInfo.Target {
    /// The path used as base for all the relative paths of the package (e.g. sources, resources, headers)
    func basePath(packageFolder: AbsolutePath) throws -> AbsolutePath {
        if let path = path {
            return packageFolder.appending(RelativePath(path))
        } else {
            let firstMatchingPath = PackageInfoMapper.predefinedSourceDirectories
                .map { packageFolder.appending(components: [$0, name]) }
                .first(where: { FileHandler.shared.exists($0) })
            guard let mainPath = firstMatchingPath else {
                throw PackageInfoMapperError.defaultPathNotFound(packageFolder, name)
            }
            return mainPath
        }
    }

    func publicHeadersPath(packageFolder: AbsolutePath) throws -> AbsolutePath {
        let mainPath = try basePath(packageFolder: packageFolder)
        return mainPath.appending(RelativePath(publicHeadersPath ?? "include"))
    }
}

extension PackageInfoMapper {
    public enum ResolvedDependency: Equatable {
        case target(name: String, condition: Condition?)
        case xcframework(path: Path, condition: Condition?)
        case externalTarget(package: String, target: String, condition: Condition?)

        fileprivate var condition: Condition? {
            switch self {
            case let .target(_, condition):
                return condition
            case let .xcframework(_, condition):
                return condition
            case let .externalTarget(_, _, condition):
                return condition
            }
        }

        fileprivate static func from(
            dependencies: [PackageInfo.Target.Dependency],
            packageInfo: PackageInfo,
            packageInfos: [String: PackageInfo],
            idToPackage: [String: String],
            targetDependencyToFramework: [String: Path]
        ) throws -> [ResolvedDependency] {
            try dependencies.flatMap { dependency -> [Self] in
                switch dependency {
                case let .target(name, condition):
                    return Self.fromTarget(
                        name: name,
                        targetDependencyToFramework: targetDependencyToFramework,
                        condition: condition
                    )
                case let .product(name, package, condition):
                    return try Self.fromProduct(
                        package: idToPackage[package.lowercased()] ?? package,
                        product: name,
                        packageInfos: packageInfos,
                        targetDependencyToFramework: targetDependencyToFramework,
                        condition: condition
                    )
                case let .byName(name, condition):
                    if packageInfo.targets.contains(where: { $0.name == name }) {
                        return Self.fromTarget(
                            name: name,
                            targetDependencyToFramework: targetDependencyToFramework,
                            condition: condition
                        )
                    } else {
                        guard let packageNameAndInfo = packageInfos
                            .first(where: { $0.value.products.contains { $0.name == name } })
                        else {
                            throw PackageInfoMapperError.unknownByNameDependency(name)
                        }

                        return try Self.fromProduct(
                            package: packageNameAndInfo.key,
                            product: name,
                            packageInfos: packageInfos,
                            targetDependencyToFramework: targetDependencyToFramework,
                            condition: condition
                        )
                    }
                }
            }
        }

        fileprivate static func fromTarget(
            name: String,
            targetDependencyToFramework: [String: Path],
            condition packageConditionDescription: PackageInfo.PackageConditionDescription?
        ) -> [Self] {
            let condition = packageConditionDescription.flatMap(Condition.from)

            if let framework = targetDependencyToFramework[name] {
                return [.xcframework(path: framework, condition: condition)]
            } else {
                return [.target(name: PackageInfoMapper.sanitize(targetName: name), condition: condition)]
            }
        }

        private static func fromProduct(
            package: String,
            product: String,
            packageInfos: [String: PackageInfo],
            targetDependencyToFramework: [String: Path],
            condition packageConditionDescription: PackageInfo.PackageConditionDescription?
        ) throws -> [Self] {
            guard let packageProduct = packageInfos[package]?.products.first(where: { $0.name == product }) else {
                throw PackageInfoMapperError.unknownProductDependency(product, package)
            }
            let condition = packageConditionDescription.flatMap(Condition.from)

            return packageProduct.targets.map { name in
                if let framework = targetDependencyToFramework[name] {
                    return .xcframework(path: framework, condition: condition)
                } else {
                    return .externalTarget(
                        package: package,
                        target: PackageInfoMapper.sanitize(targetName: name),
                        condition: condition
                    )
                }
            }
        }
    }
}

extension PackageInfoMapper.ResolvedDependency {
    public struct Condition: Equatable {
        public let platforms: [ProjectDescription.Platform]

        public init(platforms: [ProjectDescription.Platform]) {
            self.platforms = platforms
        }

        fileprivate static func from(
            _ packageConditionDescription: PackageInfo.PackageConditionDescription
        ) -> Self? {
            let platforms = packageConditionDescription.platformNames.compactMap(ProjectDescription.Platform.init(rawValue:))

            return platforms.isEmpty ? nil : Self(platforms: platforms)
        }
    }
}

extension PackageInfo.Platform {
    var tuistPlatformName: String {
        // catalyst is mapped to iOS platform in tuist
        platformName == "maccatalyst" ? "ios" : platformName
    }
}
