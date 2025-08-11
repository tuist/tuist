import FileSystem
import Foundation
import Mockable
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistRootDirectoryLocator
import TuistSimulator
import TuistSupport
import XcodeGraph

// MARK: - PackageInfo Mapper Errors

enum PackageInfoMapperError: LocalizedError, Equatable {
    /// Thrown when the default path folder is not present.
    case defaultPathNotFound(AbsolutePath, String, [String])

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

    case modulemapMissing(moduleMapPath: String, package: String, target: String)

    var errorDescription: String? {
        switch self {
        case let .defaultPathNotFound(packageFolder, targetName, predefinedPaths):
            return """
            Default source path not found for target \(targetName) in package at \(packageFolder.pathString). \
            Source path must be one of \(predefinedPaths.map { "\($0)/\(targetName)" })
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
        case let .modulemapMissing(moduleMapPath, package, target):
            return "Target \(target) of package \(package) is a system library. Module map is missing at \(moduleMapPath)."
        }
    }
}

public enum PackageType {
    case local
    case external(artifactPaths: [String: AbsolutePath])
}

// MARK: - PackageInfo Mapper

/// Protocol that allows to map a `PackageInfo` to a `ProjectDescription.Project`.
@Mockable
public protocol PackageInfoMapping {
    /// Resolves external SwiftPackageManager dependencies.
    /// - Returns: Mapped project
    func resolveExternalDependencies(
        path: AbsolutePath,
        packageInfos: [String: PackageInfo],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]],
        packageModuleAliases: [String: [String: String]]
    ) async throws -> [String: [ProjectDescription.TargetDependency]]

    /// Maps a `PackageInfo` to a `ProjectDescription.Project`.
    /// - Returns: Mapped project
    func map(
        packageInfo: PackageInfo,
        path: AbsolutePath,
        packageType: PackageType,
        packageSettings: TuistCore.PackageSettings,
        packageModuleAliases: [String: [String: String]]
    ) async throws -> ProjectDescription.Project?
}

// swiftlint:disable:next type_body_length
public final class PackageInfoMapper: PackageInfoMapping {
    /// Predefined source directories, in order of preference.
    /// https://github.com/apple/swift-package-manager/blob/751f0b2a00276be2c21c074f4b21d952eaabb93b/Sources/PackageLoading/PackageBuilder.swift#L488
    fileprivate static let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]
    fileprivate static let predefinedTestDirectories = ["Tests", "Sources", "Source", "src", "srcs"]
    private let moduleMapGenerator: SwiftPackageManagerModuleMapGenerating
    private let fileSystem: FileSysteming
    private let rootDirectoryLocator: RootDirectoryLocating

    public init(
        moduleMapGenerator: SwiftPackageManagerModuleMapGenerating = SwiftPackageManagerModuleMapGenerator(),
        fileSystem: FileSysteming = FileSystem(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.moduleMapGenerator = moduleMapGenerator
        self.fileSystem = fileSystem
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    /// Resolves all SwiftPackageManager dependencies.
    /// - Parameters:
    ///   - packageInfos: All available `PackageInfo`s
    ///   - packageToFolder: Mapping from a package name to its local folder
    ///   - packageToTargetsToArtifactPaths: Mapping from a package name its targets' names to artifacts' paths
    /// - Returns: Mapped project
    public func resolveExternalDependencies(
        path: AbsolutePath,
        packageInfos: [String: PackageInfo],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]],
        packageModuleAliases: [String: [String: String]]
    ) async throws -> [String: [ProjectDescription.TargetDependency]] {
        let targetDependencyToFramework: [String: Path] = try packageInfos.reduce(into: [:]) { result, packageInfo in
            try packageInfo.value.targets.forEach { target in
                guard target.type == .binary else { return }
                if let path = target.path, !path.hasSuffix(".zip") {
                    // local non .zip binary
                    result[target.name] = .path(
                        packageToFolder[packageInfo.key]!.appending(try RelativePath(validating: path))
                            .pathString
                    )
                }
                // remote or .zip binaries are checked out by SPM in artifacts/<Package.name>/<Target>.xcframework
                // or in artifacts/<Package.identity>/<Target>.xcframework when using SPM 5.6 and later
                else if let artifactPath = packageToTargetsToArtifactPaths[packageInfo.key]?[target.name] {
                    result[target.name] = .path(artifactPath.pathString)
                }
                // If the binary path is not present in the `.build/workspace-state.json`, we try to use a default path.
                // If the target is not used by a downstream target, the generation will ignore a missing binary artifact.
                // Otherwise, users will get an error that the xcframework was not found.
                else {
                    result[target.name] = .path(
                        packageToFolder[packageInfo.key]!.appending(
                            components: target.name,
                            "\(target.name).xcframework"
                        )
                        .pathString
                    )
                }
            }
        }

        var externalDependencies: [String: [ProjectDescription.TargetDependency]] = try packageInfos
            .reduce(into: [:]) { result, packageInfo in
                let moduleAliases = packageModuleAliases[packageInfo.value.name]
                for product in packageInfo.value.products {
                    result[moduleAliases?[product.name] ?? product.name] = try product.targets.flatMap { target in
                        try ResolvedDependency.fromTarget(
                            name: moduleAliases?[target] ?? target,
                            targetDependencyToFramework: targetDependencyToFramework,
                            condition: nil
                        )
                        .map {
                            switch $0 {
                            case let .xcframework(path, condition):
                                return .xcframework(path: path, expectedSignature: nil, condition: condition)
                            case let .target(name, condition):
                                let name = moduleAliases?[name] ?? name
                                return .project(
                                    target: name,
                                    path: .path(packageToFolder[packageInfo.key]!.pathString),
                                    condition: condition
                                )
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
        // Include dependencies added as binary targets
        let remoteXcframeworksPath = path.appending(components: [
            "artifacts",
            path.removingLastComponent().url.lastPathComponent.lowercased(),
        ])
        let remoteXcframeworks = try await fileSystem.glob(directory: remoteXcframeworksPath, include: ["**/*.xcframework"])
            .collect()
        for xcframework in remoteXcframeworks {
            let dependencyName = xcframework.relative(to: remoteXcframeworksPath).basenameWithoutExt
            let xcframeworkPath = Path
                .relativeToRoot(xcframework.relative(to: try await rootDirectoryLocator.locate(from: path)).pathString)
            externalDependencies[dependencyName] = [.xcframework(path: xcframeworkPath, expectedSignature: nil)]
        }
        return externalDependencies
    }

    /// There are certain Swift Package targets that need to run on macOS. Examples of these are Swift Macros.
    ///
    /// It's important that we take that into account when generating and serializing the graph, which contains information about
    /// targets' macros, into disk.  It's important to note that these targets require its dependencies, direct or transitive, to
    /// compile for macOS too. This function traverses the graph and returns all the targets that need to compile for macOS in a
    /// set. The set is then used in the serialization logic when:
    ///
    /// - Unfolding the target into platform-specific targets.
    /// - Declaring dependencies.
    ///
    /// All the complexity associated to this might go away once we have support for multi-platform targets.
    private func macOSTargets(
        _ resolvedDependencies: [String: [ResolvedDependency]],
        packageInfos: [String: PackageInfo]
    ) -> Set<String> {
        let targetTypes = packageInfos.reduce(into: [String: PackageInfo.Target.TargetType]()) { partialResult, item in
            for target in item.value.targets {
                partialResult[target.name] = target.type
            }
        }

        var targets = Set<String>()

        func visit(target: String, parentMacOS: Bool) {
            let isMacOS = targetTypes[target] == .macro || parentMacOS
            if isMacOS {
                targets.insert(target)
            }
            let dependencies = resolvedDependencies[target] ?? []
            for dependency in dependencies {
                switch dependency {
                case let .target(name, _):
                    visit(target: name, parentMacOS: isMacOS)
                case let .externalTarget(_, name, _):
                    visit(target: name, parentMacOS: isMacOS)
                case .xcframework:
                    break
                }
            }
        }

        for target in resolvedDependencies.keys.sorted() {
            visit(target: target, parentMacOS: false)
        }

        return targets
    }

    // swiftlint:disable:next function_body_length
    public func map(
        packageInfo: PackageInfo,
        path: AbsolutePath,
        packageType: PackageType,
        packageSettings: TuistCore.PackageSettings,
        packageModuleAliases: [String: [String: String]]
    ) async throws -> ProjectDescription.Project? {
        // Hardcoded mapping for some well known libraries, until the logic can handle those properly
        let productTypes = packageSettings.productTypes.merging(
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

        var mutableTargetToProducts: [String: Set<PackageInfo.Product>] = [:]
        for product in packageInfo.products {
            var targetsToProcess = Set(product.targets)
            while !targetsToProcess.isEmpty {
                let target = targetsToProcess.removeFirst()
                let alreadyProcessed = mutableTargetToProducts[target]?.contains(product) ?? false
                guard !alreadyProcessed else {
                    continue
                }
                mutableTargetToProducts[target, default: []].insert(product)
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
        let targetToProducts = mutableTargetToProducts

        let targets: [ProjectDescription.Target] = try await packageInfo.targets
            .concurrentCompactMap { target -> ProjectDescription.Target? in
                return try await self.map(
                    target: target,
                    targetToProducts: targetToProducts,
                    packageInfo: packageInfo,
                    packageType: packageType,
                    path: path,
                    packageFolder: path,
                    productTypes: productTypes,
                    productDestinations: packageSettings.productDestinations,
                    targetSettings: packageSettings.targetSettings,
                    packageModuleAliases: packageModuleAliases
                )
            }

        guard !targets.isEmpty else {
            return nil
        }

        let options: ProjectDescription.Project.Options
        if let projectOptions = packageSettings.projectOptions[packageInfo.name] {
            options = .from(manifest: projectOptions)
        } else {
            let automaticSchemesOptions: ProjectDescription.Project.Options.AutomaticSchemesOptions
            switch packageType {
            case .external:
                automaticSchemesOptions = .disabled
            case .local:
                automaticSchemesOptions = .enabled()
            }
            options = .options(
                automaticSchemesOptions: automaticSchemesOptions,
                disableSynthesizedResourceAccessors: true
            )
        }

        return ProjectDescription.Project(
            name: packageInfo.name,
            options: options,
            settings: packageInfo.projectSettings(
                packageFolder: path,
                baseSettings: packageSettings.baseSettings,
                swiftToolsVersion: Version(stringLiteral: packageInfo.toolsVersion.description)
            ),
            targets: targets,
            resourceSynthesizers: .default
        )
    }

    fileprivate class func sanitize(targetName: String) -> String {
        targetName.replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    // swiftlint:disable:next function_body_length
    private func map(
        target: PackageInfo.Target,
        targetToProducts: [String: Set<PackageInfo.Product>],
        packageInfo: PackageInfo,
        packageType: PackageType,
        path: AbsolutePath,
        packageFolder: AbsolutePath,
        productTypes: [String: XcodeGraph.Product],
        productDestinations: [String: XcodeGraph.Destinations],
        targetSettings: [String: XcodeGraph.Settings],
        packageModuleAliases: [String: [String: String]]
    ) async throws -> ProjectDescription.Target? {
        // Ignores or passes a target based on the `type` and the `packageType`.
        // After that, it assumes that no target is ignored.
        switch target.type {
        case .regular, .system, .macro:
            break
        case .test, .executable:
            switch packageType {
            case .external:
                Logger.current.debug("Target \(target.name) of type \(target.type) ignored")
                return nil
            case .local:
                break
            }
        default:
            Logger.current.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        let products = targetToProducts[target.name] ?? Set()

        guard let product = ProjectDescription.Product.from(
            name: target.name,
            type: target.type,
            products: products,
            productTypes: productTypes
        )
        else {
            Logger.current.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let targetPath = try await target.basePath(packageFolder: packageFolder)

        let moduleMap: ModuleMap?
        switch target.type {
        case .system:
            // System library targets assume the module map is located at the source directory root
            // https://github.com/apple/swift-package-manager/blob/main/Sources/PackageLoading/ModuleMapGenerator.swift
            let packagePath = try await target.basePath(packageFolder: path)
            let moduleMapPath = packagePath.appending(component: ModuleMap.filename)

            guard try await fileSystem.exists(moduleMapPath), !FileHandler.shared.isFolder(moduleMapPath) else {
                throw PackageInfoMapperError.modulemapMissing(
                    moduleMapPath: moduleMapPath.pathString,
                    package: packageInfo.name,
                    target: target.name
                )
            }

            moduleMap = ModuleMap.custom(moduleMapPath, umbrellaHeaderPath: nil)
        case .regular:
            moduleMap = try await moduleMapGenerator.generate(
                packageDirectory: path,
                moduleName: target.name,
                publicHeadersPath: target.publicHeadersPath(packageFolder: path)
            )
        default:
            moduleMap = nil
        }

        var destinations: ProjectDescription.Destinations
        switch target.type {
        case .macro, .executable:
            destinations = Set([.mac])
        case .test:
            var testDestinations = Set(XcodeGraph.Destination.allCases)
            for dependencyTarget in target.dependencies {
                if let dependencyProducts = targetToProducts[dependencyTarget.name] {
                    let dependencyDestinations = unionDestinationsOfProducts(dependencyProducts, in: productDestinations)
                    testDestinations.formIntersection(dependencyDestinations)
                }
            }
            destinations = ProjectDescription.Destinations.from(destinations: testDestinations)
        default:
            switch packageType {
            case .local:
                let productDestinations = unionDestinationsOfProducts(products, in: productDestinations)
                destinations = ProjectDescription.Destinations.from(destinations: productDestinations)
            case .external:
                destinations = Set(Destination.allCases)
            }
        }

        let version = try Version(versionString: try SwiftVersionProvider.current.swiftVersion(), usesLenientParsing: true)
        let minDeploymentTargets = ProjectDescription.DeploymentTargets.oldestVersions(for: version)

        let deploymentTargets = try ProjectDescription.DeploymentTargets.from(
            minDeploymentTargets: minDeploymentTargets,
            package: packageInfo.platforms,
            destinations: destinations,
            packageName: packageInfo.name
        )

        var headers: ProjectDescription.Headers?
        var sources: SourceFilesList?
        var resources: ProjectDescription.ResourceFileElements?

        if target.type.supportsPublicHeaderPath {
            headers = try Headers.from(moduleMap: moduleMap)
        }

        if target.type.supportsSources {
            sources = try SourceFilesList.from(sources: target.sources, path: targetPath, excluding: target.exclude)
        }

        if target.type.supportsResources {
            resources = try await ResourceFileElements.from(
                sources: target.sources,
                resources: target.resources,
                path: targetPath,
                excluding: target.exclude,
                fileSystem: fileSystem
            )
        }

        var dependencies: [ProjectDescription.TargetDependency] = []

        // Module aliases of used dependencies.
        // These need to be mapped in `OTHER_SWIFT_FLAGS` using the `-module-alias` build flag.
        var dependencyModuleAliases: [String: String] = [:]

        if target.type.supportsDependencies {
            let linkerDependencies: [ProjectDescription.TargetDependency] = target.settings.compactMap { setting in
                do {
                    let condition = try ProjectDescription.PlatformCondition.from(setting.condition)

                    switch (setting.tool, setting.name) {
                    case (.linker, .linkedFramework):
                        return .sdk(name: setting.value[0], type: .framework, status: .required, condition: condition)
                    case (.linker, .linkedLibrary):
                        return .sdk(name: setting.value[0], type: .library, status: .required, condition: condition)
                    case (_, .interoperabilityMode):
                        return nil
                    case (.c, _), (.cxx, _), (_, .enableUpcomingFeature), (.swift, _), (.linker, .headerSearchPath), (
                        .linker,
                        .define
                    ),
                    (.linker, .unsafeFlags), (_, .enableExperimentalFeature), (_, .swiftLanguageMode):
                        return nil
                    }
                } catch {
                    return nil
                }
            }

            dependencies = try linkerDependencies + target.dependencies.compactMap {
                switch $0 {
                case let .product(name: name, package: _, moduleAliases: moduleAliases, condition: condition):
                    try mapDependency(
                        name: name,
                        packageInfo: packageInfo,
                        packageType: packageType,
                        condition: condition,
                        moduleAliases: moduleAliases,
                        dependencyModuleAliases: &dependencyModuleAliases
                    )
                case let .byName(name: name, condition: condition),
                     let .target(
                         name: name,
                         condition: condition
                     ):
                    try mapDependency(
                        name: name,
                        packageInfo: packageInfo,
                        packageType: packageType,
                        condition: condition,
                        moduleAliases: packageModuleAliases[packageInfo.name],
                        dependencyModuleAliases: &dependencyModuleAliases
                    )
                }
            }
        }

        let targetName = packageModuleAliases[packageInfo.name]?[target.name] ?? target.name
        let productName = PackageInfoMapper
            .sanitize(targetName: targetName)
            .replacingOccurrences(of: "-", with: "_")

        let settings = try await Settings.from(
            target: target,
            productName: productName,
            packageFolder: packageFolder,
            settings: target.settings,
            moduleMap: moduleMap,
            targetSettings: targetSettings[target.name],
            dependencyModuleAliases: dependencyModuleAliases
        )

        return .target(
            name: PackageInfoMapper.sanitize(targetName: targetName),
            destinations: destinations,
            product: product,
            productName: productName,
            bundleId: targetName
                .replacingOccurrences(of: "_", with: ".").replacingOccurrences(of: "/", with: "."),
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: sources,
            resources: resources,
            buildableFolders: [],
            headers: headers,
            dependencies: dependencies,
            settings: settings
        )
    }

    private func mapDependency(
        name: String,
        packageInfo: PackageInfo,
        packageType: PackageType,
        condition: PackageInfo.PackageConditionDescription?,
        moduleAliases: [String: String]?,
        dependencyModuleAliases: inout [String: String]
    ) throws -> ProjectDescription.TargetDependency? {
        let platformCondition: ProjectDescription.PlatformCondition?
        do {
            platformCondition = try ProjectDescription.PlatformCondition.from(condition)
        } catch {
            return nil
        }
        if let target = packageInfo.targets.first(where: { $0.name == name }) {
            if target.type == .binary, case let .external(artifactPaths: artifactPaths) = packageType,
               let artifactPath = artifactPaths[target.name]
            {
                return .xcframework(
                    path: .path(artifactPath.pathString),
                    expectedSignature: nil,
                    status: .required,
                    condition: platformCondition
                )
            }
            if let aliasedName = moduleAliases?[name] {
                dependencyModuleAliases[name] = aliasedName
                return .target(name: aliasedName, condition: platformCondition)
            } else {
                return .target(name: name, condition: platformCondition)
            }
        } else {
            if let aliasedName = moduleAliases?[name] {
                dependencyModuleAliases[name] = aliasedName
                return .external(name: aliasedName, condition: platformCondition)
            } else {
                return .external(name: name, condition: platformCondition)
            }
        }
    }

    /// Returns a union of products' destinations.
    private func unionDestinationsOfProducts(
        _ products: Set<PackageInfo.Product>,
        in productToDestinations: [String: XcodeGraph.Destinations]
    ) -> XcodeGraph.Destinations {
        Set(
            products.flatMap { product in
                if product.type == .executable {
                    return Set([XcodeGraph.Destination.mac])
                }
                return productToDestinations[product.name] ?? Set(Destination.allCases)
            }
        )
    }
}

extension ProjectDescription.DeploymentTargets {
    /// A dictionary that contains the oldest supported version of each platform
    public static func oldestVersions(for swiftVersion: TSCUtility.Version) -> ProjectDescription.DeploymentTargets {
        if swiftVersion < Version(5, 7, 0) {
            return .multiplatform(
                iOS: "9.0",
                macOS: "10.10",
                watchOS: "2.0",
                tvOS: "9.0",
                visionOS: "1.0"
            )
        } else if swiftVersion < Version(5, 9, 0) {
            return .multiplatform(
                iOS: "11.0",
                macOS: "10.13",
                watchOS: "4.0",
                tvOS: "11.0",
                visionOS: "1.0"
            )
        } else {
            return .multiplatform(
                iOS: "12.0",
                macOS: "10.13",
                watchOS: "4.0",
                tvOS: "12.0",
                visionOS: "1.0"
            )
        }
    }

    fileprivate static func from(
        minDeploymentTargets: ProjectDescription.DeploymentTargets,
        package: [PackageInfo.Platform],
        destinations: ProjectDescription.Destinations,
        packageName _: String
    ) throws -> Self {
        let versionPairs: [(ProjectDescription.Platform, String)] = package.compactMap { packagePlatform in
            guard let tuistPlatform = ProjectDescription.Platform(rawValue: packagePlatform.tuistPlatformName) else { return nil }
            return (tuistPlatform, packagePlatform.version)
        }
        // maccatalyst and iOS will be the same, this chooses the first one defined, hopefully they dont disagree
        let platformInfos = Dictionary(versionPairs) { first, _ in first }
        let destinationTypes = destinations.platforms

        func versionFor(platform: ProjectDescription.Platform) throws -> String? {
            guard destinationTypes.contains(platform) else { return nil }
            return try max(minDeploymentTargets[platform], platformInfos[platform])
        }

        return .multiplatform(
            iOS: try versionFor(platform: .iOS),
            macOS: try versionFor(platform: .macOS),
            watchOS: try versionFor(platform: .watchOS),
            tvOS: try versionFor(platform: .tvOS),
            visionOS: try versionFor(platform: .visionOS)
        )
    }

    fileprivate static func max(_ lVersionString: String?, _ rVersionString: String?) throws -> String? {
        guard let rVersionString else { return lVersionString }
        guard let lVersionString else { return nil }
        let lVersion = try Version(versionString: lVersionString, usesLenientParsing: true)
        let rVersion = try Version(versionString: rVersionString, usesLenientParsing: true)
        return lVersion > rVersion ? lVersionString : rVersionString
    }
}

extension ProjectDescription.Product {
    fileprivate static func from(
        name: String,
        type: PackageInfo.Target.TargetType,
        products: Set<PackageInfo.Product>,
        productTypes: [String: XcodeGraph.Product]
    ) -> Self? {
        // Swift Macros are command line tools that run in the host (macOS) at compilation time.
        switch type {
        case .macro:
            return .macro
        case .executable:
            return .commandLineTool
        case .test:
            return .unitTests
        default:
            break
        }

        if let productType = productTypes[name] {
            return ProjectDescription.Product.from(product: productType)
        }

        var hasAutomaticProduct = false
        let product: ProjectDescription.Product? = products.reduce(nil) { result, product in
            switch product.type {
            case let .library(type):
                switch type {
                case .automatic:
                    hasAutomaticProduct = true
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

        if hasAutomaticProduct {
            // contains automatic product, default to static framework
            return .staticFramework
        } else if product != nil {
            // return found product if there is no automatic products
            return product
        } else {
            // only executable, plugin, or test products, ignore it
            return nil
        }
    }
}

extension SourceFilesList {
    fileprivate static func from(sources: [String]?, path: AbsolutePath, excluding: [String]) throws -> Self? {
        let sourcesPaths: [AbsolutePath]
        if let customSources = sources {
            sourcesPaths = try customSources.map { source in
                let absolutePath = path.appending(try RelativePath(validating: source))
                if absolutePath.extension == nil {
                    return absolutePath.appending(component: "**")
                }
                return absolutePath
            }
        } else {
            sourcesPaths = [path.appending(component: "**")]
        }
        guard !sourcesPaths.isEmpty else { return nil }
        return .sourceFilesList(
            globs: try sourcesPaths.map { absolutePath -> ProjectDescription.SourceFileGlob in
                .glob(
                    .path(absolutePath.pathString),
                    excluding: try excluding.map {
                        let excludePath = path.appending(try RelativePath(validating: $0))
                        let excludeGlob = excludePath.extension != nil ? excludePath : excludePath.appending(component: "**")
                        return .path(excludeGlob.pathString)
                    }
                )
            }
        )
    }
}

extension ProjectDescription.ResourceFileElements {
    fileprivate static func from(
        sources: [String]?,
        resources: [PackageInfo.Target.Resource],
        path: AbsolutePath,
        excluding: [String],
        fileSystem: FileSysteming
    ) async throws -> Self? {
        // Handles the conversion of a `.copy` resource rule of SPM
        //
        // - Parameters:
        //   - resourceAbsolutePath: The absolute path of that resource
        // - Returns: A ProjectDescription.ResourceFileElement mapped from a `.copy` resource rule of SPM
        @Sendable func handleCopyResource(resourceAbsolutePath: AbsolutePath) -> ProjectDescription.ResourceFileElement {
            .folderReference(path: .path(resourceAbsolutePath.pathString))
        }

        let excludedPaths = try excluding.map {
            path.appending(try RelativePath(validating: $0))
        }

        // Handles the conversion of a `.process` resource rule of SPM
        //
        // - Parameters:
        //   - resourceAbsolutePath: The absolute path of that resource
        // - Returns: A ProjectDescription.ResourceFileElement mapped from a `.process` resource rule of SPM
        @Sendable func handleProcessResource(resourceAbsolutePath: AbsolutePath) async throws -> ProjectDescription
            .ResourceFileElement?
        {
            let absolutePathGlob = if try await fileSystem.exists(resourceAbsolutePath, isDirectory: true),
                                      !resourceAbsolutePath.isOpaqueDirectory
            {
                resourceAbsolutePath
                    .appending(component: "**")
            } else {
                resourceAbsolutePath
            }
            if excludedPaths
                .contains(where: { absolutePathGlob.isDescendantOfOrEqual(to: $0) })
            {
                return nil
            }
            return .glob(
                pattern: .path(absolutePathGlob.pathString),
                excluding: try excluding.map {
                    let excludePath = path.appending(try RelativePath(validating: $0))
                    let excludeGlob = excludePath.extension != nil ? excludePath : excludePath.appending(component: "**")
                    return .path(excludeGlob.pathString)
                }
            )
        }

        var resourceFileElements: [ProjectDescription.ResourceFileElement] = try await resources.concurrentCompactMap {
            let resourceAbsolutePath = path.appending(try RelativePath(validating: $0.path))

            switch $0.rule {
            case .copy:
                // Single files or opaque directories are handled like a .process rule
                if !FileHandler.shared.isFolder(resourceAbsolutePath) || resourceAbsolutePath.isOpaqueDirectory {
                    return try await handleProcessResource(resourceAbsolutePath: resourceAbsolutePath)
                } else {
                    return handleCopyResource(resourceAbsolutePath: resourceAbsolutePath)
                }
            case .process:
                return try await handleProcessResource(resourceAbsolutePath: resourceAbsolutePath)
            }
        }
        .concurrentFilter {
            switch $0 {
            case let .glob(pattern: pattern, excluding: _, tags: _, inclusionCondition: _):
                // We will automatically skip including globs of non-existing directories for packages
                if try await !fileSystem.exists(try AbsolutePath(validating: String(pattern.pathString)).parentDirectory) {
                    return false
                }
                return true
            case .folderReference:
                return true
            @unknown default:
                return true
            }
        }

        // Add default resources path if necessary
        // They are handled like a `.process` rule
        if sources == nil {
            // Already included resources should not be added as default resource
            let excludedPaths: Set<AbsolutePath> = Set(
                resourceFileElements.compactMap {
                    switch $0 {
                    case let .folderReference(path: path, _, _):
                        AbsolutePath(stringLiteral: path.pathString)
                    case let .glob(pattern: path, _, _, _):
                        AbsolutePath(stringLiteral: path.pathString).upToLastNonGlob
                    @unknown default:
                        nil
                    }
                }
            )
            resourceFileElements += try await fileSystem.glob(
                directory: path,
                include: [
                    "**/*.{\(defaultSpmResourceFileExtensions.joined(separator: ","))}",
                ]
            )
            .collect()
            .filter { !$0.components.contains(where: { $0.hasSuffix(".xcframework") }) }
            .filter { candidatePath in
                try excludedPaths.allSatisfy {
                    try !AbsolutePath(validating: $0.pathString.lowercased())
                        .isAncestorOfOrEqual(to: AbsolutePath(validating: candidatePath.pathString.lowercased()))
                }
            }
            .sorted()
            .concurrentCompactMap { try await handleProcessResource(resourceAbsolutePath: $0) }
        }

        // Check for empty resource files
        guard !resourceFileElements.isEmpty else { return nil }

        return .resources(resourceFileElements.uniqued())
    }

    /// These files are automatically added as resource if they are inside targets directory.
    /// Check https://developer.apple.com/documentation/swift_packages/bundling_resources_with_a_swift_package
    private static let defaultSpmResourceFileExtensions = Set([
        "xib",
        "storyboard",
        "xcdatamodeld",
        "xcmappingmodel",
        "xcassets",
        "strings",
        "stringsdict",
    ])

    private static func defaultResourcePaths(
        from path: AbsolutePath,
        filter: @escaping (Foundation.URL) -> Bool
    ) -> [AbsolutePath] {
        Array(FileHandler.shared.files(
            in: path,
            filter: filter,
            nameFilter: nil,
            extensionFilter: defaultSpmResourceFileExtensions
        ))
    }
}

extension ProjectDescription.TargetDependency {
    fileprivate static func from(
        resolvedDependencies: [PackageInfoMapper.ResolvedDependency],
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        packageToProject: [String: AbsolutePath]
    ) throws -> [Self] {
        let targetDependencies = resolvedDependencies.compactMap { dependency -> Self? in
            switch dependency {
            case let .target(name, condition):
                return .target(name: name, condition: condition)
            case let .xcframework(path, condition):
                return .xcframework(path: path, expectedSignature: nil, condition: condition)
            case let .externalTarget(project, target, condition):
                return .project(
                    target: target,
                    path: .path(packageToProject[project]!.pathString),
                    condition: condition
                )
            }
        }

        let linkerDependencies: [ProjectDescription.TargetDependency] = settings.compactMap { setting in
            do {
                let condition = try ProjectDescription.PlatformCondition.from(setting.condition)

                switch (setting.tool, setting.name) {
                case (.linker, .linkedFramework):
                    return .sdk(name: setting.value[0], type: .framework, status: .required, condition: condition)
                case (.linker, .linkedLibrary):
                    return .sdk(name: setting.value[0], type: .library, status: .required, condition: condition)
                case (_, .interoperabilityMode):
                    return nil
                case (.c, _), (.cxx, _), (_, .enableUpcomingFeature), (.swift, _), (.linker, .headerSearchPath), (
                    .linker,
                    .define
                ),
                (.linker, .unsafeFlags), (_, .enableExperimentalFeature), (_, .swiftLanguageMode):
                    return nil
                }
            } catch {
                return nil
            }
        }

        return targetDependencies + linkerDependencies
    }
}

extension ProjectDescription.Headers {
    fileprivate static func from(moduleMap: ModuleMap?) throws -> Self? {
        guard let moduleMap else { return nil }
        // As per SPM logic, headers should be added only when using the umbrella header without modulemap:
        // https://github.com/apple/swift-package-manager/blob/9b9bed7eaf0f38eeccd0d8ca06ae08f6689d1c3f/Sources/Xcodeproj/pbxproj.swift#L588-L609
        switch moduleMap {
        case let .directory(moduleMapPath: _, umbrellaDirectory: umbrellaDirectory):
            return .headers(
                public: .list(
                    [
                        .glob("\(umbrellaDirectory.pathString)/*.h"),
                    ]
                )
            )
        case .none, .header, .custom:
            return nil
        }
    }
}

extension ProjectDescription.Settings {
    // swiftlint:disable:next function_body_length
    fileprivate static func from(
        target: PackageInfo.Target,
        productName: String,
        packageFolder: AbsolutePath,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        moduleMap: ModuleMap?,
        targetSettings: XcodeGraph.Settings?,
        dependencyModuleAliases: [String: String]
    ) async throws -> Self? {
        let mainPath = try await target.basePath(packageFolder: packageFolder)
        let mainRelativePath = mainPath.relative(to: packageFolder)

        var dependencyHeaderSearchPaths: [String] = []
        if let moduleMap {
            if moduleMap != .none, target.type != .system {
                let publicHeadersPath = try await target.publicHeadersPath(packageFolder: packageFolder)
                let publicHeadersRelativePath = publicHeadersPath.relative(to: packageFolder)
                dependencyHeaderSearchPaths.append("$(SRCROOT)/\(publicHeadersRelativePath.pathString)")
            }
        }

        let mapper = SettingsMapper(
            headerSearchPaths: dependencyHeaderSearchPaths,
            mainRelativePath: mainRelativePath,
            settings: settings
        )

        var settingsDictionary: XcodeGraph.SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": ["$(inherited)"],
        ]

        // Force enable testing search paths
        let forceEnabledTestingSearchPath: Set<String> = [
            "Mocker", // https://github.com/WeTransfer/Mocker
            "Nimble", // https://github.com/Quick/Nimble
            "NimbleObjectiveC", // https://github.com/Quick/Nimble
            "Quick", // https://github.com/Quick/Quick
            "QuickObjCRuntime", // https://github.com/Quick/Quick
            "RxTest", // https://github.com/ReactiveX/RxSwift
            "RxTest-Dynamic", // https://github.com/ReactiveX/RxSwift
            "SnapshotTesting", // https://github.com/pointfreeco/swift-snapshot-testing
            "IssueReportingTestSupport", // https://github.com/pointfreeco/swift-issue-reporting
            "SwiftyMocky", // https://github.com/MakeAWishFoundation/SwiftyMocky
            "TempuraTesting", // https://github.com/BendingSpoons/tempura-swift
            "TSCTestSupport", // https://github.com/apple/swift-tools-support-core
            "ViewInspector", // https://github.com/nalexn/ViewInspector
            "XCTVapor", // https://github.com/vapor/vapor
            "MockableTest", // https://github.com/Kolos65/Mockable.git
            "Testing", // https://github.com/apple/swift-testing
            "Cuckoo", // https://github.com/Brightify/Cuckoo
            "_SwiftSyntaxTestSupport", // https://github.com/swiftlang/swift-syntax
            "SwiftSyntaxMacrosTestSupport", // https://github.com/swiftlang/swift-syntax
        ]

        let resolvedSettings = try mapper.mapSettings()
        settingsDictionary.merge(resolvedSettings) { $1 }

        if forceEnabledTestingSearchPath.contains(target.name) {
            if settingsDictionary["ENABLE_TESTING_SEARCH_PATHS"] == nil {
                settingsDictionary["ENABLE_TESTING_SEARCH_PATHS"] = "YES"
            }
        }

        if let moduleMapPath = moduleMap?.moduleMapPath {
            settingsDictionary["MODULEMAP_FILE"] = .string("$(SRCROOT)/\(moduleMapPath.relative(to: packageFolder))")
        }

        if let moduleMap {
            switch moduleMap {
            case .directory, .header, .custom:
                settingsDictionary["DEFINES_MODULE"] = "NO"
                switch settingsDictionary["OTHER_CFLAGS"] ?? .array(["$(inherited)"]) {
                case let .array(values):
                    settingsDictionary["OTHER_CFLAGS"] = .array(values + ["-fmodule-name=\(productName)"])
                case let .string(value):
                    settingsDictionary["OTHER_CFLAGS"] = .array(
                        value.split(separator: " ").map(String.init) + ["-fmodule-name=\(productName)"]
                    )
                }
            case .none:
                break
            }
        }

        let moduleAliases = dependencyModuleAliases.flatMap { ["-module-alias", "\($0.key)=\($0.value)"] }
        if !moduleAliases.isEmpty {
            settingsDictionary["OTHER_SWIFT_FLAGS"] = switch settingsDictionary["OTHER_SWIFT_FLAGS"] ?? .array([]) {
            case let .array(values):
                .array(values + moduleAliases)
            case let .string(value):
                .array(
                    value.split(separator: " ").map(String.init) + moduleAliases
                )
            }
        }

        var baseSettingsDictionary = ProjectDescription.SettingsDictionary.from(settingsDictionary: settingsDictionary)

        if let userDefinedBaseSettings = targetSettings?.base {
            baseSettingsDictionary.merge(
                .from(settingsDictionary: userDefinedBaseSettings),
                uniquingKeysWith: {
                    switch ($0, $1) {
                    case let (.array(leftArray), .array(rightArray)):
                        return SettingValue.array(leftArray + rightArray)
                    default:
                        return $1
                    }
                }
            )
        }

        let configurations: [ProjectDescription.Configuration] = targetSettings?.configurations
            .map { buildConfiguration, configuration in
                .from(
                    buildConfiguration: buildConfiguration,
                    configuration: configuration,
                    packageFolder: packageFolder
                )
            }
            .sorted { $0.name.rawValue < $1.name.rawValue }
            ?? []

        var result: ProjectDescription.Settings = if configurations.isEmpty {
            .settings(base: baseSettingsDictionary)
        } else {
            .settings(
                base: baseSettingsDictionary,
                configurations: configurations
            )
        }

        if let defaultSettings = targetSettings?.defaultSettings {
            result.defaultSettings = .from(defaultSettings: defaultSettings)
        }

        for (index, configuration) in result.configurations.enumerated() {
            result.configurations[index].settings.merge(
                .from(
                    settingsDictionary: try mapper.settingsForBuildConfiguration(configuration.name.rawValue)
                ),
                uniquingKeysWith: { $1 }
            )
        }

        return result
    }

    fileprivate struct PackageTarget: Hashable {
        let package: String
        let target: PackageInfo.Target
    }
}

extension ProjectDescription.PackagePlatform {
    fileprivate func destinations() -> ProjectDescription.Destinations {
        switch self {
        case .iOS:
            return [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
        case .macCatalyst:
            return [.macCatalyst]
        case .macOS:
            return [.mac]
        case .tvOS:
            return [.appleTv]
        case .watchOS:
            return [.appleWatch]
        case .visionOS:
            return [.appleVision]
        }
    }
}

extension ProjectDescription.Product {
    fileprivate static func from(product: XcodeGraph.Product) -> Self {
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
        case .systemExtension:
            return .systemExtension
        case .extensionKitExtension:
            return .extensionKitExtension
        case .macro:
            return .macro
        }
    }
}

extension ProjectDescription.SettingsDictionary {
    public static func from(settingsDictionary: XcodeGraph.SettingsDictionary) -> Self {
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

extension ProjectDescription.Configuration {
    public static func from(
        buildConfiguration: BuildConfiguration,
        configuration: XcodeGraph.Configuration?,
        packageFolder: AbsolutePath
    ) -> Self {
        let name = ConfigurationName(stringLiteral: buildConfiguration.name)
        let settings = ProjectDescription.SettingsDictionary.from(settingsDictionary: configuration?.settings ?? [:])
        let xcconfig = configuration?.xcconfig.map { Path.path($0.relative(to: packageFolder).pathString) }
        switch buildConfiguration.variant {
        case .debug:
            return .debug(name: name, settings: settings, xcconfig: xcconfig)
        case .release:
            return .release(name: name, settings: settings, xcconfig: xcconfig)
        }
    }
}

extension ProjectDescription.DefaultSettings {
    fileprivate static func from(defaultSettings: XcodeGraph.DefaultSettings) -> Self {
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

extension ProjectDescription.Destinations {
    fileprivate static func from(destinations: XcodeGraph.Destinations) -> Self {
        Set(
            destinations.map {
                switch $0 {
                case .iPhone:
                    return .iPhone
                case .iPad:
                    return .iPad
                case .mac:
                    return .mac
                case .macWithiPadDesign:
                    return .macWithiPadDesign
                case .macCatalyst:
                    return .macCatalyst
                case .appleWatch:
                    return .appleWatch
                case .appleTv:
                    return .appleTv
                case .appleVision:
                    return .appleVision
                case .appleVisionWithiPadDesign:
                    return .appleVisionWithiPadDesign
                }
            }
        )
    }
}

extension PackageInfo {
    fileprivate func projectSettings(
        packageFolder: AbsolutePath,
        baseSettings: XcodeGraph.Settings,
        swiftToolsVersion: XcodeGraph.Version?
    ) -> ProjectDescription.Settings? {
        var settingsDictionary: ProjectDescription.SettingsDictionary = [
            // Xcode settings configured by SPM by default
            "ALWAYS_SEARCH_USER_PATHS": "YES",
            "CLANG_ENABLE_OBJC_WEAK": "NO",
            "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "NO",
            "FRAMEWORK_SEARCH_PATHS": ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"],
            "GCC_NO_COMMON_BLOCKS": "NO",
            "USE_HEADERMAP": "NO",
            "GCC_PREPROCESSOR_DEFINITIONS": .array(["$(inherited)", "SWIFT_PACKAGE=1"]),
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)", "SWIFT_PACKAGE"]),
            // Disable warnings in generated projects
            "GCC_WARN_INHIBIT_ALL_WARNINGS": "YES",
            "SWIFT_SUPPRESS_WARNINGS": "YES",
        ]

        settingsDictionary.merge(.from(settingsDictionary: baseSettings.base), uniquingKeysWith: { $1 })

        if toolsVersion >= Version(5, 9, 0) {
            let packageNameValues = ["$(inherited)", "-package-name", name.quotedIfContainsSpaces]
            settingsDictionary["OTHER_SWIFT_FLAGS"] = switch settingsDictionary["OTHER_SWIFT_FLAGS"] {
            case let .array(swiftFlags):
                .array(swiftFlags + packageNameValues)
            case let .string(swiftFlags):
                .array(swiftFlags.split(separator: " ").map(String.init) + packageNameValues)
            case .none:
                .array(packageNameValues)
            }
        }

        if let cLanguageStandard {
            settingsDictionary["GCC_C_LANGUAGE_STANDARD"] = .string(cLanguageStandard)
        }

        if let cxxLanguageStandard {
            settingsDictionary["CLANG_CXX_LANGUAGE_STANDARD"] = .string(cxxLanguageStandard)
        }

        if let swiftLanguageVersion = swiftVersion(for: swiftToolsVersion) {
            settingsDictionary["SWIFT_VERSION"] = .string(swiftLanguageVersion)
        }

        let configurations = baseSettings.configurations.lazy
            .sorted(by: { $0.key < $1.key })
            .map { buildConfiguration, configuration -> ProjectDescription.Configuration in
                var configuration = configuration ?? Configuration(settings: [:])
                configuration.settings = configuration.settings

                return .from(
                    buildConfiguration: buildConfiguration,
                    configuration: configuration,
                    packageFolder: packageFolder
                )
            }

        if configurations.isEmpty {
            return .settings(base: settingsDictionary)
        } else {
            return .settings(base: settingsDictionary, configurations: configurations)
        }
    }

    private func swiftVersion(for configuredSwiftVersion: XcodeGraph.Version?) -> String? {
        // Take the latest swift version compatible with the configured one
        let maxAllowedSwiftLanguageVersion = swiftLanguageVersions?
            .filter {
                guard let configuredSwiftVersion else {
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
    func basePath(packageFolder: AbsolutePath) async throws -> AbsolutePath {
        let fileSystem = FileSystem()
        if let path {
            return packageFolder.appending(try RelativePath(validating: path))
        } else {
            let predefinedDirectories: [String]
            switch type {
            case .test:
                predefinedDirectories = PackageInfoMapper.predefinedTestDirectories
            default:
                predefinedDirectories = PackageInfoMapper.predefinedSourceDirectories
            }
            let firstMatchingPath = try await predefinedDirectories
                .map { packageFolder.appending(components: [$0, name]) }
                .concurrentFilter { try await fileSystem.exists($0) }
                .first
            guard let mainPath = firstMatchingPath else {
                throw PackageInfoMapperError.defaultPathNotFound(packageFolder, name, predefinedDirectories)
            }
            return mainPath
        }
    }

    func publicHeadersPath(packageFolder: AbsolutePath) async throws -> AbsolutePath {
        let mainPath = try await basePath(packageFolder: packageFolder)
        return mainPath.appending(try RelativePath(validating: publicHeadersPath ?? "include"))
    }
}

extension PackageInfo.Target.Dependency {
    /// The literal name of the dependency.
    var name: String {
        switch self {
        case let .target(name: name, _):
            return name
        case let .product(name: name, _, _, _):
            return name
        case let .byName(name: name, _):
            return name
        }
    }
}

extension PackageInfoMapper {
    public enum ResolvedDependency: Equatable {
        case target(name: String, condition: ProjectDescription.PlatformCondition? = nil)
        case xcframework(path: Path, condition: ProjectDescription.PlatformCondition? = nil)
        case externalTarget(package: String, target: String, condition: ProjectDescription.PlatformCondition? = nil)

        fileprivate var condition: ProjectDescription.PlatformCondition? {
            switch self {
            case let .target(_, condition):
                return condition
            case let .xcframework(_, condition):
                return condition
            case let .externalTarget(_, _, condition):
                return condition
            }
        }

        fileprivate var targetName: String? {
            switch self {
            case let .target(targetName, _), let .externalTarget(_, targetName, _):
                return targetName
            case .xcframework:
                return nil
            }
        }

        fileprivate static func fromTarget(
            name: String,
            targetDependencyToFramework: [String: Path],
            condition packageConditionDescription: PackageInfo.PackageConditionDescription?
        ) -> [Self] {
            do {
                let condition = try ProjectDescription.PlatformCondition.from(packageConditionDescription)

                if let framework = targetDependencyToFramework[name] {
                    return [.xcframework(path: framework, condition: condition)]
                } else {
                    return [.target(name: PackageInfoMapper.sanitize(targetName: name), condition: condition)]
                }
            } catch {
                return []
            }
        }
    }
}

extension ProjectDescription.PlatformCondition {
    struct OnlyConditionsWithUnsupportedPlatforms: Error {}

    /// Map from a package condition to ProjectDescription.PlatformCondition
    /// - Parameter condition: condition representing platforms that a given dependency applies to
    /// - Returns: set of PlatformFilters to be used with `GraphDependencyRefrence`
    fileprivate static func from(_ condition: PackageInfo.PackageConditionDescription?) throws -> Self? {
        guard let condition else { return nil }
        let filters: [ProjectDescription.PlatformFilter] = condition.platformNames.compactMap { name in
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

        // If empty, we know there are no supported platforms and this dependency should not be included in the graph
        if filters.isEmpty {
            throw OnlyConditionsWithUnsupportedPlatforms()
        }

        return .when(Set(filters))
    }
}

extension PackageInfo.Platform {
    var tuistPlatformName: String {
        // catalyst is mapped to iOS platform in tuist
        platformName == "maccatalyst" ? "ios" : platformName
    }
}
