import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
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

    /// Thrown when a target defined in a product is not present in the package
    case unknownProductTarget(package: String, product: String, target: String)

    /// Thrown when unsupported `PackageInfo.Target.TargetBuildSettingDescription` `Tool`/`SettingName` pair is found.
    case unsupportedSetting(PackageInfo.Target.TargetBuildSettingDescription.Tool, PackageInfo.Target.TargetBuildSettingDescription.SettingName)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .noSupportedPlatforms, .unknownByNameDependency, .unknownPlatform, .unknownProductDependency, .unknownProductTarget:
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
            return "The product \(name) of package \(package) cannot be found."
        case let .unknownProductTarget(package, product, target):
            return "The target \(target) of product \(product) cannot be found in package \(package)."
        case let .unsupportedSetting(tool, setting):
            return "The \(tool) and \(setting) pair is not a supported setting."
        }
    }
}

// MARK: - PackageInfo Mapper

/// Protocol that allows to map a `PackageInfo` to a `ProjectDescription.Project`.
public protocol PackageInfoMapping {
    /// Preprocesses SwiftPackageManager dependencies.
    /// - Parameters:
    ///   - packageInfos: All available `PackageInfo`s
    ///   - productToPackage: Mapping from a product to its package
    ///   - packageToFolder: Mapping from a package name to its local folder
    ///   - targetDependencyToFramework: Mapping from a target dependency to its framework
    /// - Returns: Mapped project
    func preprocess(
        packageInfos: [String: PackageInfo],
        productToPackage: [String: String],
        packageToFolder: [String: AbsolutePath],
        artifactsFolder: AbsolutePath
    ) throws -> ( // swiftlint:disable:this large_tuple
        targetToProducts: [String: Set<PackageInfo.Product>],
        resolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        externalDependencies: [String: [ProjectDescription.TargetDependency]]
    )

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
    ///   - swiftToolsVersion: The version of Swift tools that will be used to map dependencies
    /// - Returns: Mapped project
    func map(
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        name: String,
        path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        deploymentTargets: Set<TuistGraph.DeploymentTarget>,
        targetToProducts: [String: Set<PackageInfo.Product>],
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        packageToProject: [String: AbsolutePath],
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> ProjectDescription.Project?
}

public final class PackageInfoMapper: PackageInfoMapping {
    let moduleMapGenerator: SwiftPackageManagerModuleMapGenerating

    public init(moduleMapGenerator: SwiftPackageManagerModuleMapGenerating = SwiftPackageManagerModuleMapGenerator()) {
        self.moduleMapGenerator = moduleMapGenerator
    }

    /// Resolves all SwiftPackageManager dependencies.
    /// - Parameters:
    ///   - packageInfos: All available `PackageInfo`s
    ///   - productToPackage: Mapping from a product to its package
    ///   - packageToFolder: Mapping from a package name to its local folder
    ///   - targetDependencyToFramework: Mapping from a target dependency to its framework
    /// - Returns: Mapped project
    public func preprocess( // swiftlint:disable:this function_body_length
        packageInfos: [String: PackageInfo],
        productToPackage: [String: String],
        packageToFolder: [String: AbsolutePath],
        artifactsFolder: AbsolutePath
    ) throws -> ( // swiftlint:disable:this large_tuple
        targetToProducts: [String: Set<PackageInfo.Product>],
        resolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        externalDependencies: [String: [ProjectDescription.TargetDependency]]
    ) {
        let targetDependencyToFramework: [String: Path] = packageInfos.reduce(into: [:]) { result, packageInfo in
            let artifactsFolderForPackage = artifactsFolder.appending(component: packageInfo.key)
            packageInfos[packageInfo.key]?.targets.forEach { target in
                guard target.type == .binary else { return }
                if let path = target.path {
                    // local binary
                    result[target.name] = Path(RelativePath(path).pathString)
                } else {
                    // remote binaries are checkedout by SPM in artifacts/<Package>/<Target>.xcframework
                    result[target.name] = Path(artifactsFolderForPackage.appending(component: "\(target.name).xcframework").pathString)
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

        let resolvedDependencies: [String: [ResolvedDependency]] = try packageInfos.values.reduce(into: [:]) { result, packageInfo in
            try packageInfo.targets
                .filter { targetToProducts[$0.name] != nil }
                .forEach { target in
                    guard result[target.name] == nil else { return }
                    result[target.name] = try ResolvedDependency.from(
                        dependencies: target.dependencies,
                        packageInfo: packageInfo,
                        packageInfos: packageInfos,
                        productToPackage: productToPackage,
                        targetDependencyToFramework: targetDependencyToFramework
                    )
                }
        }

        let externalDependencies: [String: [ProjectDescription.TargetDependency]] = try packageInfos.reduce(into: [:]) { result, packageInfo in
            try packageInfo.value.products.forEach { product in
                result[product.name] = try product.targets.map { target in
                    let resolvedDependency = ResolvedDependency.fromTarget(name: target, targetDependencyToFramework: targetDependencyToFramework)
                    switch resolvedDependency {
                    case let .xcframework(path):
                        return .xcframework(path: path)
                    case let .target(name):
                        return .project(target: name, path: Path(packageToFolder[packageInfo.key]!.pathString))
                    case .externalTargets:
                        throw PackageInfoMapperError.unknownProductTarget(package: packageInfo.key, product: product.name, target: target)
                    }
                }
            }
        }

        return (targetToProducts: targetToProducts, resolvedDependencies: resolvedDependencies, externalDependencies: externalDependencies)
    }

    public func map(
        packageInfo: PackageInfo,
        packageInfos: [String: PackageInfo],
        name: String,
        path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        deploymentTargets: Set<TuistGraph.DeploymentTarget>,
        targetToProducts: [String: Set<PackageInfo.Product>],
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        packageToProject: [String: AbsolutePath],
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> ProjectDescription.Project? {
        let targets = try packageInfo.targets.compactMap { target -> ProjectDescription.Target? in
            guard let products = targetToProducts[target.name] else { return nil }
            return try Target.from(
                target: target,
                products: products,
                packageName: name,
                packageInfo: packageInfo,
                packageInfos: packageInfos,
                packageFolder: path,
                packageToProject: packageToProject,
                productTypes: productTypes,
                platforms: platforms,
                deploymentTargets: deploymentTargets,
                targetToResolvedDependencies: targetToResolvedDependencies,
                moduleMapGenerator: moduleMapGenerator
            )
        }

        guard !targets.isEmpty else {
            return nil
        }

        return ProjectDescription.Project(
            name: name,
            settings: packageInfo.projectSettings(swiftToolsVersion: swiftToolsVersion),
            targets: targets,
            resourceSynthesizers: []
        )
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
        platforms: Set<TuistGraph.Platform>,
        deploymentTargets: Set<TuistGraph.DeploymentTarget>,
        targetToResolvedDependencies: [String: [PackageInfoMapper.ResolvedDependency]],
        moduleMapGenerator: SwiftPackageManagerModuleMapGenerating
    ) throws -> Self? {
        guard target.type == .regular else {
            logger.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        guard let product = ProjectDescription.Product.from(name: target.name, products: products, productTypes: productTypes) else {
            logger.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let path = packageFolder.appending(target.relativePath)
        let publicHeadersPath = path.appending(target.relativePublicHeadersPath)
        let moduleMap = try moduleMapGenerator.generate(moduleName: target.name, publicHeadersPath: publicHeadersPath)

        let platform = try ProjectDescription.Platform.from(configured: platforms, package: packageInfo.platforms, packageName: packageName)
        let deploymentTarget = try ProjectDescription.DeploymentTarget.from(
            configuredPlatforms: platforms,
            configuredDeploymentTargets: deploymentTargets,
            package: packageInfo.platforms,
            packageName: packageName
        )
        let sources = SourceFilesList.from(sources: target.sources, path: path, excluding: target.exclude)
        let resources = ResourceFileElements.from(resources: target.resources, path: path, excluding: target.exclude)
        let headers = try Headers.from(moduleMapType: moduleMap.type, publicHeadersPath: publicHeadersPath)

        let resolvedDependencies = targetToResolvedDependencies[target.name] ?? []

        let dependencies = try ProjectDescription.TargetDependency.from(
            resolvedDependencies: resolvedDependencies,
            platform: platform,
            settings: target.settings,
            packageToProject: packageToProject
        )
        let settings = try Settings.from(
            target: target,
            packageFolder: packageFolder,
            packageName: packageName,
            packageInfos: packageInfos,
            packageToProject: packageToProject,
            targetToResolvedDependencies: targetToResolvedDependencies,
            settings: target.settings,
            platform: platform,
            moduleMap: moduleMap
        )

        return ProjectDescription.Target(
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
                return .iOS(targetVersion: packagePlatform.version, devices: [.iphone, .ipad])
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
    fileprivate static func from(resources: [PackageInfo.Target.Resource], path: AbsolutePath, excluding: [String]) -> Self? {
        let resourcesPaths = resources.map { path.appending(RelativePath($0.path)) }
        guard !resourcesPaths.isEmpty else { return nil }
        return .init(
            resources: resourcesPaths.map { absolutePath in
                let absolutePathGlob = absolutePath.extension != nil ? absolutePath : absolutePath.appending(component: "**")
                return .glob(
                    pattern: Path(absolutePathGlob.pathString),
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

extension ProjectDescription.TargetDependency {
    fileprivate static func from(
        resolvedDependencies: [PackageInfoMapper.ResolvedDependency],
        platform: ProjectDescription.Platform,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        packageToProject: [String: AbsolutePath]
    ) throws -> [Self] {
        let targetDependencies = resolvedDependencies.flatMap { dependency -> [Self] in
            switch dependency {
            case let .target(name):
                return [.target(name: name)]
            case let .xcframework(path):
                return [.xcframework(path: path)]
            case let .externalTargets(project, targets):
                return targets.map { .project(target: $0, path: Path(packageToProject[project]!.pathString)) }
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
                return .sdk(name: "lib\(setting.value[0]).tbd", status: .required)
            case (.c, _), (.cxx, _), (.swift, _), (.linker, .headerSearchPath), (.linker, .define), (.linker, .unsafeFlags):
                return nil
            }
        }

        return targetDependencies + linkerDependencies
    }
}

extension ProjectDescription.Headers {
    fileprivate static func from(moduleMapType: ModuleMapType, publicHeadersPath: AbsolutePath) throws -> Self? {
        // As per SPM logic, headers should be added only when using the umbrella header without modulemap:
        // https://github.com/apple/swift-package-manager/blob/9b9bed7eaf0f38eeccd0d8ca06ae08f6689d1c3f/Sources/Xcodeproj/pbxproj.swift#L588-L609
        guard
            moduleMapType == .header,
            let publicHeaders = FileHandler.shared.filesAndDirectoriesContained(in: publicHeadersPath)?.filter({ $0.extension == "h" }),
            !publicHeaders.isEmpty
        else {
            return nil
        }

        return Headers(public: ProjectDescription.FileList(globs: publicHeaders.map { Path($0.pathString) }))
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
        moduleMap: (type: ModuleMapType, path: AbsolutePath?)
    ) throws -> Self? {
        var headerSearchPaths: [String] = []
        var defines: [String: String] = ["SWIFT_PACKAGE": "1"]
        var swiftDefines: [String] = ["SWIFT_PACKAGE"]
        var cFlags: [String] = []
        var cxxFlags: [String] = []
        var swiftFlags: [String] = []
        var linkerFlags: [String] = []

        if moduleMap.type != .none {
            headerSearchPaths.append("$(SRCROOT)/\(target.relativePath.appending(target.relativePublicHeadersPath))")
        }

        let allDependencies = Self.recursiveTargetDependencies(
            of: target,
            packageName: packageName,
            packageInfos: packageInfos,
            targetToResolvedDependencies: targetToResolvedDependencies
        )

        headerSearchPaths += allDependencies
            .compactMap { dependency in
                guard let packagePath = packageToProject[dependency.package] else { return nil }
                let headersPath = packagePath.appending(dependency.target.relativePath.appending(dependency.target.relativePublicHeadersPath))
                guard FileHandler.shared.exists(headersPath) else { return nil }
                return "$(SRCROOT)/\(headersPath.relative(to: packageFolder))"
            }
            .sorted()

        try settings.forEach { setting in
            if let condition = setting.condition {
                guard condition.platformNames.contains(platform.rawValue) else {
                    return
                }
            }

            switch (setting.tool, setting.name) {
            case (.c, .headerSearchPath), (.cxx, .headerSearchPath):
                headerSearchPaths.append("$(SRCROOT)/\(target.relativePath.pathString)/\(setting.value[0])")
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

        var settingsDictionary: ProjectDescription.SettingsDictionary = [
            // Xcode settings configured by SPM by default
            "ALWAYS_SEARCH_USER_PATHS": "YES",
            "CLANG_ENABLE_OBJC_WEAK": "NO",
            "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "NO",
            "ENABLE_TESTING_SEARCH_PATHS": "YES",
            "FRAMEWORK_SEARCH_PATHS": ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"],
            "GCC_NO_COMMON_BLOCKS": "NO",
            "USE_HEADERMAP": "NO",
            // Disable warnings in generated projects
            "GCC_WARN_INHIBIT_ALL_WARNINGS": "YES",
        ]

        if let moduleMapPath = moduleMap.path {
            settingsDictionary["MODULEMAP_FILE"] = .string(moduleMapPath.pathString)
        }

        if !headerSearchPaths.isEmpty {
            settingsDictionary["HEADER_SEARCH_PATHS"] = .array(["$(inherited)"] + headerSearchPaths.map { $0 })
        }

        if !defines.isEmpty {
            let sortedDefines = defines.sorted { $0.key < $1.key }
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(["$(inherited)"] + sortedDefines.map { key, value in "\(key)=\(value)" })
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

        return .init(base: settingsDictionary)
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
                    case let .target(name):
                        guard
                            let packageInfo = packageInfos[packageTarget.package],
                            let target = packageInfo.targets.first(where: { $0.name == name })
                        else {
                            return []
                        }
                        return [PackageTarget(package: packageTarget.package, target: target)]
                    case let .externalTargets(package, targets):
                        guard let packageInfo = packageInfos[package] else { return [] }
                        return packageInfo.targets.filter { targets.contains($0.name) }.map {
                            return PackageTarget(package: package, target: $0)
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

extension PackageInfo {
    fileprivate func projectSettings(
        swiftToolsVersion: TSCUtility.Version?
    ) -> ProjectDescription.Settings? {
        var settingsDictionary: ProjectDescription.SettingsDictionary = [:]

        if let cLanguageStandard = self.cLanguageStandard {
            settingsDictionary["GCC_C_LANGUAGE_STANDARD"] = .string(cLanguageStandard)
        }

        if let cxxLanguageStandard = self.cxxLanguageStandard {
            settingsDictionary["CLANG_CXX_LANGUAGE_STANDARD"] = .string(cxxLanguageStandard)
        }

        if let swiftLanguageVersion = swiftVersion(for: swiftToolsVersion) {
            settingsDictionary["SWIFT_VERSION"] = .string(swiftLanguageVersion)
        }

        return settingsDictionary.isEmpty ? nil : .init(base: settingsDictionary)
    }

    fileprivate func swiftVersion(for configuredSwiftVersion: TSCUtility.Version?) -> String? {
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
    var relativePath: RelativePath {
        RelativePath(path ?? "Sources/\(name)")
    }

    var relativePublicHeadersPath: RelativePath {
        RelativePath(publicHeadersPath ?? "include")
    }
}

extension PackageInfoMapper {
    public enum ResolvedDependency: Equatable {
        case target(name: String)
        case xcframework(path: Path)
        case externalTargets(package: String, targets: [String])

        fileprivate static func from(
            dependencies: [PackageInfo.Target.Dependency],
            packageInfo: PackageInfo,
            packageInfos: [String: PackageInfo],
            productToPackage _: [String: String],
            targetDependencyToFramework: [String: Path]
        ) throws -> [ResolvedDependency] {
            return try dependencies.map { dependency -> Self in
                switch dependency {
                case let .target(name, _):
                    return Self.fromTarget(name: name, targetDependencyToFramework: targetDependencyToFramework)
                case let .product(name, package, _):
                    return try Self.fromProduct(package: package, product: name, packageInfos: packageInfos)
                case let .byName(name, _):
                    if packageInfo.targets.contains(where: { $0.name == name }) {
                        return Self.fromTarget(name: name, targetDependencyToFramework: targetDependencyToFramework)
                    } else {
                        guard let packageNameAndInfo = packageInfos.first(where: { $0.value.products.contains { $0.name == name } }) else {
                            throw PackageInfoMapperError.unknownByNameDependency(name)
                        }

                        return try Self.fromProduct(package: packageNameAndInfo.key, product: name, packageInfos: packageInfos)
                    }
                }
            }
        }

        fileprivate static func fromTarget(name: String, targetDependencyToFramework: [String: Path]) -> Self {
            if let framework = targetDependencyToFramework[name] {
                return .xcframework(path: framework)
            } else {
                return .target(name: name)
            }
        }

        private static func fromProduct(
            package: String,
            product: String,
            packageInfos: [String: PackageInfo]
        ) throws -> Self {
            guard
                let targets = packageInfos[package]?.products.first(where: { $0.name == product })?.targets
            else {
                throw PackageInfoMapperError.unknownProductDependency(product, package)
            }
            return .externalTargets(package: package, targets: targets)
        }
    }
}
