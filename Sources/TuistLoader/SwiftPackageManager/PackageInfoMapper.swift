import Foundation
import Mockable
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - PackageInfo Mapper Errors

enum PackageInfoMapperError: FatalError, Equatable {
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
        case let .missingBinaryArtifact(package, target):
            return "The artifact for binary target \(target) of package \(package) cannot be found."
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
        packageInfos: [String: PackageInfo],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]]
    ) throws -> [String: [ProjectDescription.TargetDependency]]

    /// Maps a `PackageInfo` to a `ProjectDescription.Project`.
    /// - Returns: Mapped project
    func map(
        packageInfo: PackageInfo,
        path: AbsolutePath,
        packageType: PackageType,
        packageSettings: TuistGraph.PackageSettings,
        packageToProject: [String: AbsolutePath]
    ) throws -> ProjectDescription.Project?
}

// swiftlint:disable:next type_body_length
public final class PackageInfoMapper: PackageInfoMapping {
    // Predefined source directories, in order of preference.
    // https://github.com/apple/swift-package-manager/blob/751f0b2a00276be2c21c074f4b21d952eaabb93b/Sources/PackageLoading/PackageBuilder.swift#L488
    fileprivate static let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]
    fileprivate static let predefinedTestDirectories = ["Tests", "Sources", "Source", "src", "srcs"]
    private let moduleMapGenerator: SwiftPackageManagerModuleMapGenerating

    public init(
        moduleMapGenerator: SwiftPackageManagerModuleMapGenerating = SwiftPackageManagerModuleMapGenerator()
    ) {
        self.moduleMapGenerator = moduleMapGenerator
    }

    /// Resolves all SwiftPackageManager dependencies.
    /// - Parameters:
    ///   - packageInfos: All available `PackageInfo`s
    ///   - packageToFolder: Mapping from a package name to its local folder
    ///   - packageToTargetsToArtifactPaths: Mapping from a package name its targets' names to artifacts' paths
    /// - Returns: Mapped project
    public func resolveExternalDependencies(
        packageInfos: [String: PackageInfo],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]]
    ) throws -> [String: [ProjectDescription.TargetDependency]] {
        let targetDependencyToFramework: [String: Path] = try packageInfos.reduce(into: [:]) { result, packageInfo in
            try packageInfo.value.targets.forEach { target in
                guard target.type == .binary else { return }
                if let path = target.path {
                    // local binary
                    result[target.name] = .path(
                        packageToFolder[packageInfo.key]!.appending(try RelativePath(validating: path))
                            .pathString
                    )
                } else {
                    // remote binaries are checked out by SPM in artifacts/<Package.name>/<Target>.xcframework
                    // or in artifacts/<Package.identity>/<Target>.xcframework when using SPM 5.6 and later
                    guard let artifactPath = packageToTargetsToArtifactPaths[packageInfo.key]?[target.name] else {
                        throw PackageInfoMapperError.missingBinaryArtifact(package: packageInfo.key, target: target.name)
                    }
                    result[target.name] = .path(artifactPath.pathString)
                }
            }
        }

        return try packageInfos
            .reduce(into: [:]) { result, packageInfo in
                for product in packageInfo.value.products {
                    result[product.name] = try product.targets.flatMap { target in
                        try ResolvedDependency.fromTarget(
                            name: target,
                            targetDependencyToFramework: targetDependencyToFramework,
                            condition: nil
                        )
                        .map {
                            switch $0 {
                            case let .xcframework(path, condition):
                                return .xcframework(path: path, condition: condition)
                            case let .target(name, condition):
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
    }

    /**
     There are certain Swift Package targets that need to run on macOS. Examples of these are Swift Macros.
     It's important that we take that into account when generating and serializing the graph, which contains information
     about targets' macros, into disk.  It's important to note that these targets require its dependencies, direct or transitive,
     to compile for macOS too. This function traverses the graph and returns all the targets that need to compile for macOS
     in a set. The set is then used in the serialization logic when:

     - Unfolding the target into platform-specific targets.
     - Declaring dependencies.

     All the complexity associated to this might go away once we have support for multi-platform targets.
     */
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
        packageSettings: TuistGraph.PackageSettings,
        packageToProject _: [String: AbsolutePath]
    ) throws -> ProjectDescription.Project? {
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

        let targetSettings = packageSettings.targetSettings.merging(
            // Force enable testing search paths
            Dictionary(
                uniqueKeysWithValues: [
                    "Mocker", // https://github.com/WeTransfer/Mocker
                    "Nimble", // https://github.com/Quick/Nimble
                    "NimbleObjectiveC", // https://github.com/Quick/Nimble
                    "Quick", // https://github.com/Quick/Quick
                    "RxTest", // https://github.com/ReactiveX/RxSwift
                    "RxTest-Dynamic", // https://github.com/ReactiveX/RxSwift
                    "SnapshotTesting", // https://github.com/pointfreeco/swift-snapshot-testing
                    "SwiftyMocky", // https://github.com/MakeAWishFoundation/SwiftyMocky
                    "TempuraTesting", // https://github.com/BendingSpoons/tempura-swift
                    "TSCTestSupport", // https://github.com/apple/swift-tools-support-core
                    "ViewInspector", // https://github.com/nalexn/ViewInspector
                    "XCTVapor", // https://github.com/vapor/vapor
                    "MockableTest", // https://github.com/Kolos65/Mockable.git
                    "Testing", // https://github.com/apple/swift-testing
                    "Cuckoo", // https://github.com/Brightify/Cuckoo
                ].map {
                    ($0, ["ENABLE_TESTING_SEARCH_PATHS": "YES"])
                }
            ),
            uniquingKeysWith: { userDefined, defaultDictionary in
                userDefined.merging(defaultDictionary, uniquingKeysWith: { userDefined, _ in userDefined })
            }
        )

        let baseSettings = packageSettings.baseSettings.with(
            base: packageSettings.baseSettings.base.combine(
                with: [
                    "OTHER_SWIFT_FLAGS": ["$(inherited)", "-package-name", packageInfo.name],
                ]
            )
        )

        var targetToProducts: [String: Set<PackageInfo.Product>] = [:]
        for product in packageInfo.products {
            var targetsToProcess = Set(product.targets)
            while !targetsToProcess.isEmpty {
                let target = targetsToProcess.removeFirst()
                let alreadyProcessed = targetToProducts[target]?.contains(product) ?? false
                guard !alreadyProcessed else {
                    continue
                }
                targetToProducts[target, default: []].insert(product)
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

        let targets: [ProjectDescription.Target] = try packageInfo.targets
            .compactMap { target -> ProjectDescription.Target? in
                return try map(
                    target: target,
                    products: targetToProducts[target.name] ?? Set(),
                    packageInfo: packageInfo,
                    packageType: packageType,
                    path: path,
                    packageFolder: path,
                    productTypes: productTypes,
                    productDestinations: packageSettings.productDestinations,
                    baseSettings: baseSettings,
                    targetSettings: targetSettings
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
                swiftToolsVersion: packageSettings.swiftToolsVersion,
                buildConfigs: baseSettings.configurations.map { key, _ in key }
            ),
            targets: targets,
            resourceSynthesizers: .default
        )
    }

    fileprivate class func sanitize(targetName: String) -> String {
        targetName.replacingOccurrences(of: ".", with: "_")
    }

    // swiftlint:disable:next function_body_length
    private func map(
        target: PackageInfo.Target,
        products: Set<PackageInfo.Product>,
        packageInfo: PackageInfo,
        packageType: PackageType,
        path: AbsolutePath,
        packageFolder: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        productDestinations: [String: TuistGraph.Destinations],
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary]
    ) throws -> ProjectDescription.Target? {
        switch target.type {
        case .regular, .system, .macro:
            break
        case .test, .executable:
            switch packageType {
            case .external:
                logger.debug("Target \(target.name) of type \(target.type) ignored")
                return nil
            case .local:
                break
            }
        default:
            logger.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        guard let product = ProjectDescription.Product.from(
            name: target.name,
            type: target.type,
            products: products,
            productTypes: productTypes
        )
        else {
            logger.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let targetPath = try target.basePath(packageFolder: packageFolder)

        let moduleMap: ModuleMap?
        switch target.type {
        case .system:
            /// System library targets assume the module map is located at the source directory root
            /// https://github.com/apple/swift-package-manager/blob/main/Sources/PackageLoading/ModuleMapGenerator.swift
            let packagePath = try target.basePath(packageFolder: path)
            let moduleMapPath = packagePath.appending(component: ModuleMap.filename)

            guard FileHandler.shared.exists(moduleMapPath), !FileHandler.shared.isFolder(moduleMapPath) else {
                throw PackageInfoMapperError.modulemapMissing(
                    moduleMapPath: moduleMapPath.pathString,
                    package: packageInfo.name,
                    target: target.name
                )
            }

            moduleMap = ModuleMap.custom(moduleMapPath, umbrellaHeaderPath: nil)
        case .regular:
            moduleMap = try moduleMapGenerator.generate(
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
        default:
            switch packageType {
            case .local:
                let productDestinations: Set<ProjectDescription.Destination> = Set(
                    products.flatMap { product in
                        if product.type == .executable {
                            return Set([TuistGraph.Destination.mac])
                        }
                        return productDestinations[product.name] ?? Set(Destination.allCases)
                    }
                    .map {
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
                destinations = Set(Destination.allCases).intersection(productDestinations)
            case .external:
                destinations = Set(Destination.allCases)
            }
        }

        let version = try Version(versionString: try System.shared.swiftVersion(), usesLenientParsing: true)
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
            resources = try ResourceFileElements.from(
                sources: target.sources,
                resources: target.resources,
                path: targetPath,
                excluding: target.exclude
            )
        }

        var dependencies: [ProjectDescription.TargetDependency] = []

        if target.type.supportsDependencies {
            let linkerDependencies: [ProjectDescription.TargetDependency] = target.settings.compactMap { setting in
                do {
                    let condition = try ProjectDescription.PlatformCondition.from(setting.condition)

                    switch (setting.tool, setting.name) {
                    case (.linker, .linkedFramework):
                        return .sdk(name: setting.value[0], type: .framework, status: .required, condition: condition)
                    case (.linker, .linkedLibrary):
                        return .sdk(name: setting.value[0], type: .library, status: .required, condition: condition)
                    case (.c, _), (.cxx, _), (_, .enableUpcomingFeature), (.swift, _), (.linker, .headerSearchPath), (
                        .linker,
                        .define
                    ),
                    (.linker, .unsafeFlags), (_, .enableExperimentalFeature):
                        return nil
                    }
                } catch {
                    return nil
                }
            }

            dependencies = try linkerDependencies + target.dependencies.compactMap {
                switch $0 {
                case let .byName(name: name, condition: condition), let .product(
                    name: name,
                    package: _,
                    moduleAliases: _,
                    condition: condition
                ),
                let .target(
                    name: name,
                    condition: condition
                ):
                    let platformCondition: ProjectDescription.PlatformCondition?
                    do {
                        platformCondition = try ProjectDescription.PlatformCondition.from(condition)
                    } catch {
                        return nil
                    }
                    if let target = packageInfo.targets.first(where: { $0.name == name }) {
                        if target.type == .binary, case let .external(artifactPaths: artifactPaths) = packageType {
                            guard let artifactPath = artifactPaths[target.name] else {
                                throw PackageInfoMapperError.missingBinaryArtifact(package: packageInfo.name, target: target.name)
                            }
                            return .xcframework(path: .path(artifactPath.pathString), status: .required, condition: nil)
                        }
                        return .target(name: name, condition: platformCondition)
                    } else {
                        return .external(name: name, condition: platformCondition)
                    }
                }
            }
        }

        let settings = try Settings.from(
            target: target,
            packageFolder: packageFolder,
            packageName: packageInfo.name,
            settings: target.settings,
            platforms: packageInfo.platforms,
            moduleMap: moduleMap,
            baseSettings: baseSettings,
            targetSettings: targetSettings
        )

        return .target(
            name: PackageInfoMapper.sanitize(targetName: target.name),
            destinations: destinations,
            product: product,
            productName: PackageInfoMapper
                .sanitize(targetName: target.name)
                .replacingOccurrences(of: "-", with: "_"),
            bundleId: target.name
                .replacingOccurrences(of: "_", with: "."),
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: sources,
            resources: resources,
            headers: headers,
            dependencies: dependencies,
            settings: settings
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
        let destinationPlatforms = destinations.platforms

        func versionFor(platform: ProjectDescription.Platform) throws -> String? {
            guard destinationPlatforms.contains(platform) else { return nil }
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
        productTypes: [String: TuistGraph.Product]
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

        var hasLibraryProducts = false
        let product: ProjectDescription.Product? = products.reduce(nil) { result, product in
            switch product.type {
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
        excluding: [String]
    ) throws -> Self? {
        /// Handles the conversion of a `.copy` resource rule of SPM
        ///
        /// - Parameters:
        ///   - resourceAbsolutePath: The absolute path of that resource
        /// - Returns: A ProjectDescription.ResourceFileElement mapped from a `.copy` resource rule of SPM
        func handleCopyResource(resourceAbsolutePath: AbsolutePath) -> ProjectDescription.ResourceFileElement {
            .folderReference(path: .path(resourceAbsolutePath.pathString))
        }

        /// Handles the conversion of a `.process` resource rule of SPM
        ///
        /// - Parameters:
        ///   - resourceAbsolutePath: The absolute path of that resource
        /// - Returns: A ProjectDescription.ResourceFileElement mapped from a `.process` resource rule of SPM
        func handleProcessResource(resourceAbsolutePath: AbsolutePath) throws -> ProjectDescription.ResourceFileElement {
            let absolutePathGlob = resourceAbsolutePath.extension != nil ? resourceAbsolutePath : resourceAbsolutePath
                .appending(component: "**")
            return .glob(
                pattern: .path(absolutePathGlob.pathString),
                excluding: try excluding.map {
                    let excludePath = path.appending(try RelativePath(validating: $0))
                    let excludeGlob = excludePath.extension != nil ? excludePath : excludePath.appending(component: "**")
                    return .path(excludeGlob.pathString)
                }
            )
        }

        var resourceFileElements: [ProjectDescription.ResourceFileElement] = try resources.map {
            let resourceAbsolutePath = path.appending(try RelativePath(validating: $0.path))

            switch $0.rule {
            case .copy:
                // Single files or opaque directories are handled like a .process rule
                if !FileHandler.shared.isFolder(resourceAbsolutePath) || resourceAbsolutePath.isOpaqueDirectory {
                    return try handleProcessResource(resourceAbsolutePath: resourceAbsolutePath)
                } else {
                    return handleCopyResource(resourceAbsolutePath: resourceAbsolutePath)
                }
            case .process:
                return try handleProcessResource(resourceAbsolutePath: resourceAbsolutePath)
            }
        }
        .filter {
            switch $0 {
            case let .glob(pattern: pattern, excluding: _, tags: _, inclusionCondition: _):
                // We will automatically skip including globs of non-existing directories for packages
                if !FileHandler.shared.exists(try AbsolutePath(validating: String(pattern.pathString)).parentDirectory) {
                    return false
                }
                return true
            case .folderReference:
                return true
            }
        }

        // Add default resources path if necessary
        // They are handled like a `.process` rule
        if sources == nil {
            resourceFileElements += try defaultResourcePaths(from: path)
                .map { try handleProcessResource(resourceAbsolutePath: $0) }
        }

        // Check for empty resource files
        guard !resourceFileElements.isEmpty else { return nil }

        return .resources(resourceFileElements)
    }

    // These files are automatically added as resource if they are inside targets directory.
    // Check https://developer.apple.com/documentation/swift_packages/bundling_resources_with_a_swift_package
    private static let defaultSpmResourceFileExtensions = Set([
        "xib",
        "storyboard",
        "xcdatamodeld",
        "xcmappingmodel",
        "xcassets",
        "strings",
    ])

    private static func defaultResourcePaths(from path: AbsolutePath) -> [AbsolutePath] {
        Array(FileHandler.shared.files(in: path, nameFilter: nil, extensionFilter: defaultSpmResourceFileExtensions))
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
                return .xcframework(path: path, condition: condition)
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
                case (.c, _), (.cxx, _), (_, .enableUpcomingFeature), (.swift, _), (.linker, .headerSearchPath), (
                    .linker,
                    .define
                ),
                (.linker, .unsafeFlags), (_, .enableExperimentalFeature):
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
        packageFolder: AbsolutePath,
        packageName _: String,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        platforms: [PackageInfo.Platform],
        moduleMap: ModuleMap?,
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary]
    ) throws -> Self? {
        let mainPath = try target.basePath(packageFolder: packageFolder)
        let mainRelativePath = mainPath.relative(to: packageFolder)

        var dependencyHeaderSearchPaths: [String] = []
        if let moduleMap {
            if moduleMap != .none, target.type != .system {
                let publicHeadersPath = try target.publicHeadersPath(packageFolder: packageFolder)
                let publicHeadersRelativePath = publicHeadersPath.relative(to: packageFolder)
                dependencyHeaderSearchPaths.append("$(SRCROOT)/\(publicHeadersRelativePath.pathString)")
            }
        }

        var settingsDictionary: TuistGraph.SettingsDictionary = [
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

        let mapper = SettingsMapper(
            headerSearchPaths: dependencyHeaderSearchPaths,
            mainRelativePath: mainRelativePath,
            settings: settings
        )

        let resolvedSettings = try mapper.settingsForPlatforms(platforms)

        settingsDictionary.merge(resolvedSettings) { $1 }

        if let moduleMapPath = moduleMap?.moduleMapPath {
            settingsDictionary["MODULEMAP_FILE"] = .string("$(SRCROOT)/\(moduleMapPath.relative(to: packageFolder))")
        }

        if let moduleMap {
            switch moduleMap {
            case .directory, .header, .custom:
                settingsDictionary["DEFINES_MODULE"] = "NO"
                switch settingsDictionary["OTHER_CFLAGS"] ?? .array(["$(inherited)"]) {
                case let .array(values):
                    settingsDictionary["OTHER_CFLAGS"] = .array(values + ["-fmodule-name=\(target.name)"])
                case let .string(value):
                    settingsDictionary["OTHER_CFLAGS"] = .array(
                        value.split(separator: " ").map(String.init) + ["-fmodule-name=\(target.name)"]
                    )
                }
            case .none:
                break
            }
        }

        var mappedSettingsDictionary = ProjectDescription.SettingsDictionary.from(settingsDictionary: settingsDictionary)

        if let settingsToOverride = targetSettings[target.name] {
            let projectDescriptionSettingsToOverride = ProjectDescription.SettingsDictionary
                .from(settingsDictionary: settingsToOverride)
            mappedSettingsDictionary.merge(projectDescriptionSettingsToOverride)
        }

        return .from(settings: baseSettings, adding: mappedSettingsDictionary, packageFolder: packageFolder)
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
    public static func from(settingsDictionary: TuistGraph.SettingsDictionary) -> Self {
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
    public static func from(
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
    public static func from(
        buildConfiguration: BuildConfiguration,
        configuration: TuistGraph.Configuration?,
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

extension PackageInfo {
    fileprivate func projectSettings(
        swiftToolsVersion: TSCUtility.Version?,
        buildConfigs: [BuildConfiguration]? = nil
    ) -> ProjectDescription.Settings? {
        var settingsDictionary: ProjectDescription.SettingsDictionary = [:]

        if let cLanguageStandard {
            settingsDictionary["GCC_C_LANGUAGE_STANDARD"] = .string(cLanguageStandard)
        }

        if let cxxLanguageStandard {
            settingsDictionary["CLANG_CXX_LANGUAGE_STANDARD"] = .string(cxxLanguageStandard)
        }

        if let swiftLanguageVersion = swiftVersion(for: swiftToolsVersion) {
            settingsDictionary["SWIFT_VERSION"] = .string(swiftLanguageVersion)
        }

        if let buildConfigs {
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
    func basePath(packageFolder: AbsolutePath) throws -> AbsolutePath {
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
            let firstMatchingPath = predefinedDirectories
                .map { packageFolder.appending(components: [$0, name]) }
                .first(where: { FileHandler.shared.exists($0) })
            guard let mainPath = firstMatchingPath else {
                throw PackageInfoMapperError.defaultPathNotFound(packageFolder, name, predefinedDirectories)
            }
            return mainPath
        }
    }

    func publicHeadersPath(packageFolder: AbsolutePath) throws -> AbsolutePath {
        let mainPath = try basePath(packageFolder: packageFolder)
        return mainPath.appending(try RelativePath(validating: publicHeadersPath ?? "include"))
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
