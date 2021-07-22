import ProjectDescription
import TSCBasic
import TuistGraph
import TuistSupport

// MARK: - PackageInfo Mapper Errors

enum PackageInfoMapperError: FatalError, Equatable {
    /// Thrown when no supported platforms are found for a package.
    case noSupportedPlatforms(name: String, configured: Set<ProjectDescription.Platform>, package: Set<ProjectDescription.Platform>)

    /// Thrown when `PackageInfo.Target.Dependency.byName` dependency cannot be resolved.
    case unknownByNameDependency(String)

    /// Thrown when `PackageInfo.Platform` name cannot be mapped to a `DeploymentTarget`.
    case unknownPlatform(String)

    /// Thrown when `PackageInfo.Target.Dependency.product` dependency cannot be resolved.
    case unknownProductDependency(String, String)

    /// Thrown when unsupported `PackageInfo.Target.TargetBuildSettingDescription` `Tool`/`SettingName` pair is found.
    case unsupportedSetting(PackageInfo.Target.TargetBuildSettingDescription.Tool, PackageInfo.Target.TargetBuildSettingDescription.SettingName)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .noSupportedPlatforms, .unknownByNameDependency, .unknownPlatform, .unknownProductDependency:
            return .abort
        case .unsupportedSetting:
            return .bug
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
        case let .unknownProductDependency(name, package):
            return "The product \(name) of the package \(package) cannot be found."
        case let .unsupportedSetting(tool, setting):
            return "The \(tool) and \(setting) pair is not a supported setting."
        }
    }
}

// MARK: - PackageInfo Mapper

/// Protocol that allows to map a `PackageInfo` to a `ProjectDescription.Project`.
public protocol PackageInfoMapping {
    /// Maps a `PackageInfo` to a `ProjectDescription.Project`.
    /// - Parameters:
    ///   - packageInfo: `PackageInfo` to be mapped
    ///   - packageInfos: All available `PackageInfo`s
    ///   - name: Name of the package
    ///   - path: Path of the package
    ///   - productTypes: Product type mapping
    ///   - platforms: Configured platforms
    ///   - deploymentTargets: Configured deployment targets
    ///   - packageToProject: Mapping from a package name to its path
    ///   - productToPackage: Mapping from a product to its package
    ///   - targetDependencyToFramework: Mapping from a target dependency to its framework
    /// - Returns: Mapped project
    func map(
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        name: String,
        path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        deploymentTargets: Set<TuistGraph.DeploymentTarget>,
        packageToProject: [String: Path],
        productToPackage: [String: String],
        targetDependencyToFramework: [String: Path]
    ) throws -> ProjectDescription.Project
}

public final class PackageInfoMapper: PackageInfoMapping {
    public init() {}

    public func map(
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        name: String,
        path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        deploymentTargets: Set<TuistGraph.DeploymentTarget>,
        packageToProject: [String: Path],
        productToPackage: [String: String],
        targetDependencyToFramework: [String: Path]
    ) throws -> ProjectDescription.Project {
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

        let targets = try packageInfo.targets.compactMap { target -> ProjectDescription.Target? in
            guard let products = targetToProducts[target.name] else { return nil }

            return try Target.from(
                target: target,
                products: products,
                packageName: name,
                packageInfo: packageInfo,
                packageInfos: packageInfos,
                folder: path,
                packageToProject: packageToProject,
                productTypes: productTypes,
                platforms: platforms,
                deploymentTargets: deploymentTargets,
                productToPackage: productToPackage,
                targetDependencyToFramework: targetDependencyToFramework
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
        products: Set<PackageInfo.Product>,
        packageName: String,
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        folder: AbsolutePath,
        packageToProject: [String: Path],
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        deploymentTargets: Set<TuistGraph.DeploymentTarget>,
        productToPackage: [String: String],
        targetDependencyToFramework: [String: Path]
    ) throws -> Self? {
        guard target.type == .regular else {
            logger.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        guard let product = ProjectDescription.Product.from(name: target.name, products: products, productTypes: productTypes) else {
            logger.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let path = folder.appending(RelativePath(target.path ?? "Sources/\(target.name)"))

        let platform = try ProjectDescription.Platform.from(configured: platforms, package: packageInfo.platforms, packageName: packageName)
        let deploymentTarget = try ProjectDescription.DeploymentTarget.from(
            configuredPlatforms: platforms,
            configuredDeploymentTargets: deploymentTargets,
            package: packageInfo.platforms,
            packageName: packageName
        )
        let sources = SourceFilesList.from(sources: target.sources, path: path, excluding: target.exclude)
        let resources = ResourceFileElements.from(resources: target.resources, path: path)
        let headers = ProjectDescription.Headers.from(path: path, publicHeadersPath: target.publicHeadersPath)
        let dependencies = try ProjectDescription.TargetDependency.from(
            packageInfo: packageInfo,
            platform: platform,
            packageInfos: packageInfos,
            dependencies: target.dependencies,
            settings: target.settings,
            packageToProject: packageToProject,
            productToPackage: productToPackage,
            targetDependencyToFramework: targetDependencyToFramework
        )
        let settings = try Settings.from(path: path, settings: target.settings, platform: platform)

        return .init(
            name: target.name,
            platform: platform,
            product: product,
            bundleId: target.name.replacingOccurrences(of: "_", with: "-"),
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

extension ProjectDescription.Platform {
    fileprivate static func from(
        configured: Set<TuistGraph.Platform>,
        package: [PackageInfo.Platform],
        packageName: String
    ) throws -> Self {
        let configuredPlatforms = Set(configured.map(\.descriptionPlatform))
        let packagePlatforms = Set(package.isEmpty ? ProjectDescription.Platform.allCases : try package.map { try $0.descriptionPlatform() })
        let validPlatforms = configuredPlatforms.intersection(packagePlatforms)

        #warning("Handle multiple platforms when supported in ProjectDescription.Target")
        if validPlatforms.contains(.iOS) {
            return .iOS
        }

        guard let platform = validPlatforms.first else {
            throw PackageInfoMapperError.noSupportedPlatforms(
                name: packageName,
                configured: configuredPlatforms,
                package: packagePlatforms
            )
        }

        return platform
    }
}

extension ProjectDescription.DeploymentTarget {
    fileprivate static func from(
        configuredPlatforms: Set<TuistGraph.Platform>,
        configuredDeploymentTargets: Set<TuistGraph.DeploymentTarget>,
        package: [PackageInfo.Platform],
        packageName: String
    ) throws -> Self? {
        let platform = try ProjectDescription.Platform.from(configured: configuredPlatforms, package: package, packageName: packageName)
        switch platform {
        case .iOS:
            if let packagePlatform = package.first(where: { $0.platformName == "ios" }) {
                return .iOS(targetVersion: packagePlatform.version, devices: [.iphone, .ipad, .mac])
            } else if let configuredDeploymentTarget = configuredDeploymentTargets.first(where: { $0.platform == "iOS" }) {
                return .from(deploymentTarget: configuredDeploymentTarget)
            }
        case .macOS:
            if let packagePlatform = package.first(where: { $0.platformName == "macos" }) {
                return .macOS(targetVersion: packagePlatform.version)
            } else if let configuredDeploymentTarget = configuredDeploymentTargets.first(where: { $0.platform == "macOS" }) {
                return .from(deploymentTarget: configuredDeploymentTarget)
            }
        case .watchOS:
            if let packagePlatform = package.first(where: { $0.platformName == "watchos" }) {
                return .watchOS(targetVersion: packagePlatform.version)
            } else if let configuredDeploymentTarget = configuredDeploymentTargets.first(where: { $0.platform == "watchOS" }) {
                return .from(deploymentTarget: configuredDeploymentTarget)
            }
        case .tvOS:
            if let packagePlatform = package.first(where: { $0.platformName == "tvos" }) {
                return .tvOS(targetVersion: packagePlatform.version)
            } else if let configuredDeploymentTarget = configuredDeploymentTargets.first(where: { $0.platform == "tvOS" }) {
                return .from(deploymentTarget: configuredDeploymentTarget)
            }
        }

        return nil
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
            sourcesPaths = customSources.map { path.appending(RelativePath($0)) }
        } else {
            sourcesPaths = [path]
        }
        guard !sourcesPaths.isEmpty else { return nil }
        return .init(
            globs: sourcesPaths.map { absolutePath -> ProjectDescription.SourceFileGlob in
                let glob = absolutePath.extension != nil ? absolutePath : absolutePath.appending(component: "**")
                return .init(
                    Path(glob.pathString),
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
    fileprivate static func from(resources: [PackageInfo.Target.Resource], path: AbsolutePath) -> Self? {
        let resourcesPaths = resources.map { path.appending(RelativePath($0.path)) }
        guard !resourcesPaths.isEmpty else { return nil }
        return .init(resources: resourcesPaths.map { absolutePath in
            let absolutePathGlob = absolutePath.extension != nil ? absolutePath : absolutePath.appending(component: "**")
            return .glob(pattern: Path(absolutePathGlob.pathString))
        })
    }
}

extension ProjectDescription.Headers {
    fileprivate static func from(path: AbsolutePath, publicHeadersPath: String?) -> Self? {
        let publicHeadersAbsolutePath = path.appending(RelativePath(publicHeadersPath ?? "include"))
        guard
            let publicHeaders = try? FileHandler.shared.contentsOfDirectory(publicHeadersAbsolutePath).filter({ $0.extension == "h" }),
            !publicHeaders.isEmpty
        else {
            return nil
        }

        return Headers(public: ProjectDescription.FileList(globs: publicHeaders.map { Path($0.pathString) }))
    }
}

extension ProjectDescription.TargetDependency {
    // swiftlint:disable:next function_body_length
    fileprivate static func from(
        packageInfo: PackageInfo,
        platform: ProjectDescription.Platform,
        packageInfos: [String: PackageInfo],
        dependencies: [PackageInfo.Target.Dependency],
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        packageToProject: [String: Path],
        productToPackage: [String: String],
        targetDependencyToFramework: [String: Path]
    ) throws -> [Self] {
        let targetDependencies = try dependencies.flatMap { dependency -> [ProjectDescription.TargetDependency] in
            switch dependency {
            case let .target(name, _):
                if let framework = targetDependencyToFramework[name] {
                    return [.xcframework(path: framework)]
                } else {
                    return [.target(name: name)]
                }
            case let .product(name, package, _):
                guard
                    let targets = packageInfos[package]?.products.first(where: { $0.name == name })?.targets,
                    let projectPath = packageToProject[package]
                else {
                    throw PackageInfoMapperError.unknownProductDependency(name, package)
                }
                return targets.map { .project(target: $0, path: projectPath) }
            case let .byName(name, _):
                if packageInfo.targets.contains(where: { $0.name == name }) {
                    if let framework = targetDependencyToFramework[name] {
                        return [.xcframework(path: framework)]
                    } else {
                        return [.target(name: name)]
                    }
                } else if let package = productToPackage[name] {
                    guard
                        let targets = packageInfos[package]?.products.first(where: { $0.name == name })?.targets,
                        let projectPath = packageToProject[package]
                    else {
                        throw PackageInfoMapperError.unknownProductDependency(name, package)
                    }
                    return targets.map { .project(target: $0, path: projectPath) }
                } else {
                    throw PackageInfoMapperError.unknownByNameDependency(name)
                }
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
                return .sdk(name: "\(setting.value[0]).framework", status: .required)
            case (.linker, .linkedLibrary):
                return .sdk(name: "\(setting.value[0]).tbd", status: .required)
            case (.c, _), (.cxx, _), (.swift, _), (.linker, .headerSearchPath), (.linker, .define), (.linker, .unsafeFlags):
                return nil
            }
        }

        return targetDependencies + linkerDependencies
    }
}

extension ProjectDescription.Settings {
    // swiftlint:disable:next function_body_length
    fileprivate static func from(
        path: AbsolutePath,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        platform: ProjectDescription.Platform
    ) throws -> Self? {
        var headerSearchPaths: [String] = []
        var defines: [String: String] = ["SWIFT_PACKAGE": "1"]
        var swiftDefines: [String] = ["SWIFT_PACKAGE"]
        var cFlags: [String] = []
        var cxxFlags: [String] = []
        var swiftFlags: [String] = []

        try settings.forEach { setting in
            if let condition = setting.condition {
                guard condition.platformNames.contains(platform.rawValue) else {
                    return
                }
            }

            switch (setting.tool, setting.name) {
            case (.c, .headerSearchPath), (.cxx, .headerSearchPath):
                headerSearchPaths.append(setting.value[0])
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

            case (.linker, .linkedFramework), (.linker, .linkedLibrary):
                // Handled as dependency
                return

            case (.c, .linkedFramework), (.c, .linkedLibrary), (.cxx, .linkedFramework), (.cxx, .linkedLibrary),
                 (.swift, .headerSearchPath), (.swift, .linkedFramework), (.swift, .linkedLibrary),
                 (.linker, .headerSearchPath), (.linker, .define), (.linker, .unsafeFlags):
                throw PackageInfoMapperError.unsupportedSetting(setting.tool, setting.name)
            }
        }

        // FRAMEWORK_SEARCH_PATHS is required for targets depending on system frameworks (for example, XCTest).
        // SPM always adds it to the Xcode build settings.
        var settingsDictionary: ProjectDescription.SettingsDictionary = [
            "FRAMEWORK_SEARCH_PATHS": "$(PLATFORM_DIR)/Developer/Library/Frameworks",
            "ENABLE_TESTING_SEARCH_PATHS": "YES",
        ]
        if !headerSearchPaths.isEmpty {
            settingsDictionary["HEADER_SEARCH_PATHS"] = .array(headerSearchPaths.map { path.appending(RelativePath($0)).pathString })
        }
        if !defines.isEmpty {
            let sortedDefines = defines.sorted { $0.key < $1.key }
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(sortedDefines.map { key, value in "\(key)=\(value)" })
        }
        if !swiftDefines.isEmpty {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = .array(swiftDefines)
        }
        if !cFlags.isEmpty {
            settingsDictionary["OTHER_CFLAGS"] = .array(cFlags)
        }
        if !cxxFlags.isEmpty {
            settingsDictionary["OTHER_CPLUSPLUSFLAGS"] = .array(cxxFlags)
        }
        if !swiftFlags.isEmpty {
            settingsDictionary["OTHER_SWIFT_FLAGS"] = .array(swiftFlags)
        }

        return .init(base: settingsDictionary)
    }
}

extension PackageInfo.Target.TargetBuildSettingDescription.Setting {
    fileprivate var extractDefine: (name: String, value: String) {
        let define = value[0]
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
        }
    }
}

extension ProjectDescription.DeploymentTarget {
    fileprivate static func from(deploymentTarget: TuistGraph.DeploymentTarget) -> Self {
        switch deploymentTarget {
        case let .iOS(version, devices):
            return .iOS(targetVersion: version, devices: .from(devices: devices))
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
        return .init(rawValue: devices.rawValue)
    }
}
