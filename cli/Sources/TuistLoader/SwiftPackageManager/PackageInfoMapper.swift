import FileSystem
import Foundation
import Mockable
import Path
@_spi(TuistLoader) import ProjectDescription
import TSCUtility
import TuistConstants
import TuistCore
import TuistLogging
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

    /// Thrown when an included local package test target depends on an executable target that is not mapped.
    case unsupportedExecutableTargetInLocalPackageTest(package: String, target: String, executable: String)

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
        case let .unsupportedExecutableTargetInLocalPackageTest(package, target, executable):
            return """
            The test target `\(target)` in the local package `\(package)` depends on the executable target `\(executable)`, \
            which Tuist omits when mapping local package dependencies. Remove the executable target dependency, or set \
            `includeLocalPackageTestTargets` to `false` in `PackageSettings`.
            """
        case let .unsupportedSetting(tool, setting):
            return "The \(tool) and \(setting) pair is not a supported setting."
        case let .modulemapMissing(moduleMapPath, package, target):
            return "Target \(target) of package \(package) is a system library. Module map is missing at \(moduleMapPath)."
        }
    }
}

/// The platforms on which a package target links SwiftPM's prebuilt libraries instead of their source products.
enum PrebuiltPlatforms: Sendable {
    case all
    case macOS
}

/// How a package target links SwiftPM's prebuilt libraries (swift-syntax's `MacroSupport`) instead of their source products.
public struct PrebuiltTarget: Sendable {
    /// The platforms on which the target links the prebuilts of its swift-syntax products instead of those products.
    let platforms: PrebuiltPlatforms
    /// The prebuilts that the targets and products the target depends on link, whose modules it imports.
    let dependencyPrebuilts: [SwiftPackageManagerPrebuilt]
}

public enum PackageType {
    public enum ExternalOrigin {
        case local
        case remote
    }

    case local
    case external(
        origin: ExternalOrigin = .remote,
        artifactPaths: [String: AbsolutePath],
        packagePrebuilts: [String: [String: SwiftPackageManagerPrebuilt]] = [:],
        derivedXCFrameworksPath: AbsolutePath? = nil,
        // The targets that link the prebuilts, from `PackageInfoMapper.prebuiltTargets`, which accounts for the products
        // of other packages. When `nil`, the mapper only looks at the package itself.
        prebuiltTargets: [String: PrebuiltTarget]? = nil
    )

    func withPrebuiltTargets(_ prebuiltTargets: [String: PrebuiltTarget]) -> PackageType {
        guard case let .external(origin, artifactPaths, packagePrebuilts, derivedXCFrameworksPath, _) = self else { return self }
        return .external(
            origin: origin,
            artifactPaths: artifactPaths,
            packagePrebuilts: packagePrebuilts,
            derivedXCFrameworksPath: derivedXCFrameworksPath,
            prebuiltTargets: prebuiltTargets
        )
    }

    fileprivate var prebuiltTargets: [String: PrebuiltTarget]? {
        guard case let .external(_, _, _, _, prebuiltTargets) = self else { return nil }
        return prebuiltTargets
    }

    fileprivate func includesTestTargets(includeLocalPackageTestTargets: Bool) -> Bool {
        switch self {
        case .local:
            return true
        case .external(origin: .local, artifactPaths: _, packagePrebuilts: _, derivedXCFrameworksPath: _, prebuiltTargets: _):
            return includeLocalPackageTestTargets
        case .external(origin: .remote, artifactPaths: _, packagePrebuilts: _, derivedXCFrameworksPath: _, prebuiltTargets: _):
            return false
        }
    }

    fileprivate var isLocalExternal: Bool {
        if case .external(
            origin: .local,
            artifactPaths: _,
            packagePrebuilts: _,
            derivedXCFrameworksPath: _,
            prebuiltTargets: _
        ) = self {
            return true
        }
        return false
    }

    fileprivate var isRemoteExternal: Bool {
        if case .external(
            origin: .remote,
            artifactPaths: _,
            packagePrebuilts: _,
            derivedXCFrameworksPath: _,
            prebuiltTargets: _
        ) = self {
            return true
        }
        return false
    }

    fileprivate var packagePrebuilts: [String: [String: SwiftPackageManagerPrebuilt]] {
        switch self {
        case .local:
            return [:]
        case let .external(
            origin: _,
            artifactPaths: _,
            packagePrebuilts: packagePrebuilts,
            derivedXCFrameworksPath: _,
            prebuiltTargets: _
        ):
            return packagePrebuilts
        }
    }

    fileprivate func prebuilt(targetPackage: String?, product: String) -> SwiftPackageManagerPrebuilt? {
        guard let targetPackage else { return nil }
        return packagePrebuilts[targetPackage]?[product]
            ?? packagePrebuilts[targetPackage.lowercased()]?[product]
    }
}

// MARK: - PackageInfo Mapper

/// The dependencies that the products of the resolved Swift packages map to.
public struct ResolvedExternalDependencies: Equatable, Sendable {
    /// Product dependencies keyed by product name. `.external(name:)` dependencies resolve against them.
    public let products: [String: [ProjectDescription.TargetDependency]]

    /// Product dependencies keyed by lowercased package reference and then by product name. Product dependencies that name
    /// their package resolve against them. A package is referenced by its identity and, unless another package shares them,
    /// by its manifest name and the name part of its registry identity.
    public let packageProducts: [String: [String: [ProjectDescription.TargetDependency]]]

    public init(
        products: [String: [ProjectDescription.TargetDependency]],
        packageProducts: [String: [String: [ProjectDescription.TargetDependency]]]
    ) {
        self.products = products
        self.packageProducts = packageProducts
    }
}

/// Protocol that allows to map a `PackageInfo` to a `ProjectDescription.Project`.
@Mockable
public protocol PackageInfoMapping {
    /// Resolves external SwiftPackageManager dependencies.
    /// - Returns: Mapped project
    func resolveExternalDependencies(
        path: AbsolutePath,
        packagePath: AbsolutePath?,
        packageInfos: [String: PackageInfo],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]],
        packageModuleAliases: [String: [String: String]],
        packageSettings: TuistCore.PackageSettings
    ) async throws -> ResolvedExternalDependencies

    /// Maps a `PackageInfo` to a `ProjectDescription.Project`.
    /// - Returns: Mapped project
    func map(
        packageInfo: PackageInfo,
        path: AbsolutePath,
        packageType: PackageType,
        packageSettings: TuistCore.PackageSettings,
        packageModuleAliases: [String: [String: String]],
        packageProducts: [String: [String: [ProjectDescription.TargetDependency]]],
        enabledTraits: Set<String>
    ) async throws -> ProjectDescription.Project?
}

// swiftlint:disable:next type_body_length
public struct PackageInfoMapper: PackageInfoMapping {
    /// Predefined source directories, in order of preference.
    /// https://github.com/apple/swift-package-manager/blob/751f0b2a00276be2c21c074f4b21d952eaabb93b/Sources/PackageLoading/PackageBuilder.swift#L488
    fileprivate static let predefinedSourceDirectories = ["Sources", "Source", "src", "srcs"]
    fileprivate static let predefinedTestDirectories = ["Tests", "Sources", "Source", "src", "srcs"]
    private static let bundleIdentifierSeparators = CharacterSet(charactersIn: " /+")
    private static let bundleIdentifierAllowedCharacters =
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
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
    ///   - packageInfos: All available `PackageInfo`s, keyed by package identity
    ///   - packageToFolder: Mapping from a package identity to its local folder
    ///   - packageToTargetsToArtifactPaths: Mapping from a package identity to its targets' names to artifacts' paths
    /// - Returns: Mapped project
    public func resolveExternalDependencies(
        path: AbsolutePath,
        packagePath: AbsolutePath? = nil,
        packageInfos: [String: PackageInfo],
        packageToFolder: [String: AbsolutePath],
        packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]],
        packageModuleAliases: [String: [String: String]],
        packageSettings: TuistCore.PackageSettings
    ) async throws -> ResolvedExternalDependencies {
        var targetDependencyToFramework: [String: Path] = [:]
        let derivedXCFrameworksPath = path.appending(
            components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
            Constants.DerivedDirectory.dependenciesXCFrameworkDirectory
        )
        for packageInfo in packageInfos {
            for target in packageInfo.value.targets {
                guard target.type == .binary else { continue }
                if let path = target.path, !path.hasSuffix(".zip") {
                    // local non .zip binary
                    targetDependencyToFramework[target.name] = try await binaryArtifactDependencyPath(
                        targetName: target.name,
                        packageName: packageInfo.value.name,
                        artifactPath: packageToFolder[packageInfo.key]!.appending(try RelativePath(validating: path)),
                        derivedXCFrameworksPath: derivedXCFrameworksPath
                    )
                }
                // remote or .zip binaries are checked out by SPM in artifacts/<Package.name>/<Target>.xcframework
                // or in artifacts/<Package.identity>/<Target>.xcframework when using SPM 5.6 and later
                else if let artifactPath = packageToTargetsToArtifactPaths[packageInfo.key]?[target.name] {
                    targetDependencyToFramework[target.name] = try await binaryArtifactDependencyPath(
                        targetName: target.name,
                        packageName: packageInfo.value.name,
                        artifactPath: artifactPath,
                        derivedXCFrameworksPath: derivedXCFrameworksPath
                    )
                }
                // If the binary path is not present in the `.build/workspace-state.json`, we try to use a default path.
                // If the target is not used by a downstream target, the generation will ignore a missing binary artifact.
                // Otherwise, users will get an error that the xcframework was not found.
                else {
                    targetDependencyToFramework[target.name] = .path(
                        packageToFolder[packageInfo.key]!.appending(
                            components: target.name,
                            "\(target.name).xcframework"
                        )
                        .pathString
                    )
                }
            }
        }

        // Packages are iterated in a stable order so that a product name vended by several packages always resolves to the
        // same package.
        let sortedPackageInfos = packageInfos.sorted(by: { $0.key < $1.key })
        var externalDependencies: [String: [ProjectDescription.TargetDependency]] = [:]
        var packageProducts: [String: [String: [ProjectDescription.TargetDependency]]] = [:]
        for packageInfo in sortedPackageInfos {
            let moduleAliases = packageModuleAliases[packageInfo.value.name]
            var products: [String: [ProjectDescription.TargetDependency]] = [:]
            for product in packageInfo.value.products {
                let productName = moduleAliases?[product.name] ?? product.name
                if case .plugin = product.type {
                    products[productName] = []
                    continue
                }

                products[productName] = try product.targets.flatMap { target in
                    try ResolvedDependency.fromTarget(
                        name: moduleAliases?[target] ?? target,
                        targetDependencyToFramework: targetDependencyToFramework,
                        condition: nil
                    )
                    .map {
                        switch $0 {
                        case let .xcframework(path, condition):
                            return .xcframework(
                                path: path,
                                expectedSignature: packageSettings.expectedSignatures[target]
                                    .map(ProjectDescription.XCFrameworkSignature.from),
                                condition: condition
                            )
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
            externalDependencies.merge(products, uniquingKeysWith: { _, new in new })
            packageProducts[packageInfo.key.lowercased()] = products
        }
        for (alias, identity) in Self.packageReferenceAliases(packageInfos: sortedPackageInfos)
            where packageProducts[alias] == nil
        {
            packageProducts[alias] = packageProducts[identity]
        }

        // Include dependencies added as binary targets
        let packageName = (packagePath ?? path.parentDirectory).basename.lowercased()
        let remoteXcframeworksPath = path.appending(components: [
            "artifacts",
            packageName,
        ])
        let remoteXcframeworks = try await fileSystem.glob(directory: remoteXcframeworksPath, include: ["**/*.xcframework"])
            .collect()
            // Filter out __MACOSX folder
            .filter { $0.parentDirectory.basenameWithoutExt != "__MACOSX" }
        for xcframework in remoteXcframeworks {
            let dependencyName = xcframework.relative(to: remoteXcframeworksPath).basenameWithoutExt
            let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: packagePath ?? path)
            let xcframeworkPath = Path
                .relativeToRoot(xcframework.relative(to: rootDirectory).pathString)
            let signature = packageSettings.expectedSignatures[dependencyName]
                .map(ProjectDescription.XCFrameworkSignature.from)
            externalDependencies[dependencyName] = [.xcframework(path: xcframeworkPath, expectedSignature: signature)]
        }
        return ResolvedExternalDependencies(products: externalDependencies, packageProducts: packageProducts)
    }

    /// Returns the products of the package a product dependency names. A registry package overridden by a local package is
    /// no longer part of the graph, so a `scope.name` reference to it falls back to the package that goes by `name`.
    private static func products(
        ofPackage package: String,
        in packageProducts: [String: [String: [ProjectDescription.TargetDependency]]]
    ) -> [String: [ProjectDescription.TargetDependency]]? {
        let reference = package.lowercased()
        if let products = packageProducts[reference] { return products }
        guard let scopeSeparator = reference.firstIndex(of: ".") else { return nil }
        return packageProducts[String(reference[reference.index(after: scopeSeparator)...])]
    }

    /// Maps the manifest name and the name part of a registry identity of each package to its lowercased identity, skipping
    /// the ones that several packages share.
    private static func packageReferenceAliases(packageInfos: [(key: String, value: PackageInfo)]) -> [String: String] {
        let identitiesByAlias = packageInfos.reduce(into: [String: Set<String>]()) { result, packageInfo in
            let identity = packageInfo.key.lowercased()
            result[packageInfo.value.name.lowercased(), default: []].insert(identity)
            if let scopeSeparator = identity.firstIndex(of: ".") {
                result[String(identity[identity.index(after: scopeSeparator)...]), default: []].insert(identity)
            }
        }
        return identitiesByAlias.compactMapValues { identities in
            identities.count == 1 ? identities.first : nil
        }
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
        packageModuleAliases: [String: [String: String]],
        packageProducts: [String: [String: [ProjectDescription.TargetDependency]]],
        enabledTraits: Set<String>
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

        let targetsByName = Dictionary(uniqueKeysWithValues: packageInfo.targets.map { ($0.name, $0) })
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
                guard let targetInfo = targetsByName[target] else { continue }
                for dependency in targetInfo.dependencies {
                    switch dependency {
                    case let .target(name, _):
                        targetsToProcess.insert(name)
                    case let .byName(name, _) where targetsByName[name] != nil:
                        targetsToProcess.insert(name)
                    case .byName, .product:
                        continue
                    }
                }
            }
        }
        let targetToProducts = mutableTargetToProducts
        let prebuiltTargets = try packageType.prebuiltTargets ?? Self.packagePrebuiltsPlan(
            packageInfo: packageInfo,
            packageType: packageType,
            includeLocalPackageTestTargets: packageSettings.includeLocalPackageTestTargets,
            enabledTraits: enabledTraits
        ).targets

        let targets: [ProjectDescription.Target] = try await packageInfo.targets
            .concurrentCompactMap { target -> ProjectDescription.Target? in
                return try await map(
                    target: target,
                    targetToProducts: targetToProducts,
                    targetsByName: targetsByName,
                    packageInfo: packageInfo,
                    packageType: packageType,
                    packageSettings: packageSettings,
                    path: path,
                    packageFolder: path,
                    productTypes: productTypes,
                    baseProductType: packageSettings.baseProductType,
                    productDestinations: packageSettings.productDestinations,
                    baseSettings: packageSettings.baseSettings,
                    targetSettings: packageSettings.targetSettings,
                    packageModuleAliases: packageModuleAliases,
                    packageProducts: packageProducts,
                    packageTraits: packageInfo.traits ?? [],
                    enabledTraits: enabledTraits,
                    prebuilts: prebuiltTargets[target.name]
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

    fileprivate static func sanitize(targetName: String) -> String {
        targetName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "_")
    }

    fileprivate static func sanitize(bundleIdentifierComponent: String) -> String {
        let normalized = String(bundleIdentifierComponent.unicodeScalars.map { scalar in
            if bundleIdentifierSeparators.contains(scalar) {
                return "."
            }
            if bundleIdentifierAllowedCharacters.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        })

        return normalized
            .split(separator: ".")
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }

    private static func effectiveProductName(
        targetName: String,
        products: Set<PackageInfo.Product>,
        targetsByName: [String: PackageInfo.Target]
    ) -> String {
        guard products.count == 1,
              let singleProduct = products.first,
              singleProduct.targets.count == 1,
              singleProduct.targets.first == targetName
        else { return targetName }

        let productName = singleProduct.name
        let wrapsProductFramework = wrapsProductNamedFramework(
            targetName: targetName, productName: productName, targetsByName: targetsByName
        )

        if targetName == productName {
            // Wrapper target already shares its name with the product (e.g. Singular 12.10.1's `Singular` target
            // wrapping `SingularBinary` at `Singular.xcframework`). Suffix the product name so Xcode doesn't emit
            // the same `.framework` from both the wrapper target and `ProcessXCFramework`.
            return wrapsProductFramework ? "\(targetName)Wrapper" : targetName
        }

        // Target name differs from the product. SwiftPM hoists the product name onto single-target wrappers whose
        // name has the product as a prefix (e.g. `FirebaseCrashlyticsTarget` becomes `FirebaseCrashlytics`). Skip
        // the hoist when the rename would collide with a sibling target or the framework a wrapped binary already
        // emits.
        guard targetName.hasPrefix(productName) else { return targetName }
        return wrapsProductFramework ? targetName : productName
    }

    private static func effectiveModuleName(
        targetName: String,
        products: Set<PackageInfo.Product>,
        targetsByName: [String: PackageInfo.Target]
    ) -> String {
        guard products.count == 1,
              let singleProduct = products.first,
              singleProduct.targets.count == 1,
              singleProduct.targets.first == targetName
        else { return targetName }

        let productName = singleProduct.name
        let wrapsProductFramework = wrapsProductNamedFramework(
            targetName: targetName, productName: productName, targetsByName: targetsByName
        )

        if targetName == productName {
            // Keep the original import name even when the built artifact has to be suffixed to avoid colliding with
            // the wrapped xcframework emitted by ProcessXCFramework.
            return targetName
        }

        // Target name differs from the product. SwiftPM hoists the product name onto single-target wrappers whose
        // name has the product as a prefix (e.g. `FirebaseCrashlyticsTarget` becomes `FirebaseCrashlytics`). Skip
        // the hoist when the rename would collide with a sibling target or the framework a wrapped binary already
        // emits.
        guard targetName.hasPrefix(productName) else { return targetName }
        return wrapsProductFramework ? targetName : productName
    }

    private static func wrapsProductNamedFramework(
        targetName: String,
        productName: String,
        targetsByName: [String: PackageInfo.Target]
    ) -> Bool {
        var visited = Set<String>()
        var queue = [targetName]

        while let currentTargetName = queue.popLast() {
            guard visited.insert(currentTargetName).inserted,
                  let currentTarget = targetsByName[currentTargetName]
            else { continue }

            for dependency in currentTarget.dependencies {
                let dependencyName: String
                let isSamePackageDependency: Bool
                switch dependency {
                case let .target(name, _), let .byName(name, _):
                    dependencyName = name
                    isSamePackageDependency = true
                case let .product(name, _, _, _):
                    dependencyName = name
                    isSamePackageDependency = false
                }

                // A same-package target already uses the product name, so renaming would collide.
                // Skip .product deps since those reference external packages and won't collide.
                if isSamePackageDependency, dependencyName == productName {
                    return true
                }

                if let depTarget = targetsByName[dependencyName] {
                    if depTarget.type == .binary, binaryTargetEmitsProductFramework(
                        depTarget, productName: productName
                    ) {
                        return true
                    }
                    queue.append(dependencyName)
                }
            }
        }

        return false
    }

    private static func binaryTargetEmitsProductFramework(
        _ target: PackageInfo.Target,
        productName: String
    ) -> Bool {
        // Prefer a local xcframework path when available since its basename is what Xcode emits verbatim.
        if let path = target.path,
           let basename = try? RelativePath(validating: path).basenameWithoutExt,
           basename == productName
        {
            return true
        }

        // Remote binary targets don't expose a local path, so match on the target name. Some SDKs (e.g.
        // firebase-ios-sdk-xcframeworks) mark binary targets internal with a leading underscore while the shipped
        // xcframework still uses the unprefixed product name, so strip leading underscores before comparing.
        let strippedName = String(target.name.drop(while: { $0 == "_" }))
        return target.name == productName
            || target.name.hasPrefix(productName)
            || strippedName == productName
            || strippedName.hasPrefix(productName)
    }

    /// Returns, for each package, the targets that link SwiftPM's prebuilt libraries (swift-syntax's `MacroSupport`)
    /// instead of their source products.
    ///
    /// Products can vend targets that link the prebuilt on macOS, such as swift-case-paths' `CasePathsMacrosSupport`.
    /// Macros and the targets only macros reach in other packages import and link those targets, so they take their
    /// prebuilts too. Targets that apps build can't, nor can the targets of the workspace's projects, which depend on the
    /// products named in `externalDependencyNames`, so the package that vends the product keeps its source products.
    /// Conversely, a package whose macros or targets only macros reach consume a product built against source
    /// swift-syntax keeps its source products, since its targets can't link both.
    static func prebuiltTargets(
        packageInfos: [String: PackageInfo],
        packageTypes: [String: PackageType],
        enabledTraits: [String: Set<String>],
        includeLocalPackageTestTargets: Bool,
        externalDependencyNames: Set<String>
    ) throws -> [String: [String: PrebuiltTarget]] {
        let keysByIdentity = Dictionary(packageInfos.keys.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let keysByReference = keysByIdentity.merging(
            packageReferenceAliases(packageInfos: packageInfos.map { (key: $0.key, value: $0.value) })
                .compactMapValues { keysByIdentity[$0] },
            uniquingKeysWith: { identityKey, _ in identityKey }
        )
        func packageKey(_ reference: String) -> String? {
            let reference = reference.lowercased()
            if let key = keysByReference[reference] { return key }
            guard let scopeSeparator = reference.firstIndex(of: ".") else { return nil }
            return keysByReference[String(reference[reference.index(after: scopeSeparator)...])]
        }

        // The products that other packages' targets consume. Like swift-build, which links the prebuilt into every macOS
        // module that uses swift-syntax, the targets of a product that only macros and the targets they reach consume, such
        // as a library of swift-syntax helpers, are macro-reached targets of their package. Package graphs are acyclic,
        // so starting from every consumed product and dropping those that a target outside the prebuilt targets, or a
        // project, consumes settles on the products only those targets consume.
        let consumedProducts = packageInfos.reduce(into: [String: Set<String>]()) { consumedProducts, package in
            guard let packageType = packageTypes[package.key] else { return }
            let includesTestTargets = packageType.includesTestTargets(
                includeLocalPackageTestTargets: includeLocalPackageTestTargets
            )
            for target in package.value.targets where includesTestTargets || target.type != .test {
                for (name, reference) in productDependencies(
                    of: target,
                    in: package.value,
                    enabledTraits: enabledTraits[package.key] ?? []
                ) {
                    guard let key = packageKey(reference), key != package.key else { continue }
                    consumedProducts[key, default: []].insert(name)
                }
            }
        }
        var appConsumedProducts: [String: Set<String>] = [:]
        while true {
            let plans = try packagePrebuiltsPlans(
                packageInfos: packageInfos,
                packageTypes: packageTypes,
                enabledTraits: enabledTraits,
                includeLocalPackageTestTargets: includeLocalPackageTestTargets,
                externalDependencyNames: externalDependencyNames,
                hostConsumedProducts: Dictionary(uniqueKeysWithValues: consumedProducts.map { key, products in
                    (key, products.subtracting(externalDependencyNames).subtracting(appConsumedProducts[key] ?? []))
                }),
                packageKey: packageKey
            )
            let updatedAppConsumedProducts = plans.values.flatMap(\.appConsumedProducts)
                .reduce(into: appConsumedProducts) { appConsumedProducts, dependency in
                    guard let key = packageKey(dependency.package) else { return }
                    appConsumedProducts[key, default: []].insert(dependency.product)
                }
            if updatedAppConsumedProducts == appConsumedProducts {
                return plans.mapValues(\.targets)
            }
            appConsumedProducts = updatedAppConsumedProducts
        }
    }

    /// Plans every package's prebuilt targets, given the products whose targets only prebuilt targets of other packages
    /// consume.
    private static func packagePrebuiltsPlans(
        packageInfos: [String: PackageInfo],
        packageTypes: [String: PackageType],
        enabledTraits: [String: Set<String>],
        includeLocalPackageTestTargets: Bool,
        externalDependencyNames: Set<String>,
        hostConsumedProducts: [String: Set<String>],
        packageKey: (String) -> String?
    ) throws -> [String: PackagePrebuiltsPlan] {
        // Packages that apps or projects consume a product of that links the prebuilt keep their source products, and so do
        // the packages whose prebuilt targets consume products built against source swift-syntax. Both only grow, and each
        // change to them changes the prebuilts that products vend, so those are computed again from none after it.
        // Products only vend more prebuilts as the ones they consume grow, so this settles.
        var sourcePackages = Set<String>()
        var sourceSwiftSyntaxProducts: [String: Set<String>] = [:]
        var productPrebuilts: [String: [String: Set<SwiftPackageManagerPrebuilt>]] = [:]
        while true {
            let plans = try packageInfos.reduce(into: [String: PackagePrebuiltsPlan]()) { plans, package in
                guard let packageType = packageTypes[package.key] else { return }
                plans[package.key] = try packagePrebuiltsPlan(
                    packageInfo: package.value,
                    packageType: packageType,
                    includeLocalPackageTestTargets: includeLocalPackageTestTargets,
                    enabledTraits: enabledTraits[package.key] ?? [],
                    keepsSourceProducts: sourcePackages.contains(package.key),
                    hostConsumedProducts: hostConsumedProducts[package.key] ?? [],
                    productPrebuilts: { reference, product in packageKey(reference).flatMap { productPrebuilts[$0]?[product] } },
                    sourceSwiftSyntaxProduct: { reference, product in
                        packageKey(reference).flatMap { sourceSwiftSyntaxProducts[$0]?.contains(product) } ?? false
                    }
                )
            }
            let projectConsumedPackages = plans.filter { _, plan in
                plan.productPrebuilts.keys.contains(where: externalDependencyNames.contains)
            }.keys
            let updatedSourcePackages = sourcePackages
                .union(plans.values.flatMap(\.appConsumedPackages).compactMap(packageKey))
                .union(projectConsumedPackages)
            let updatedSourceSwiftSyntaxProducts = plans.mapValues(\.sourceSwiftSyntaxProducts).filter { !$0.value.isEmpty }
            if updatedSourcePackages != sourcePackages || updatedSourceSwiftSyntaxProducts != sourceSwiftSyntaxProducts {
                sourcePackages = updatedSourcePackages
                sourceSwiftSyntaxProducts = updatedSourceSwiftSyntaxProducts
                productPrebuilts = [:]
                continue
            }
            let updatedProductPrebuilts = plans.mapValues(\.productPrebuilts).filter { !$0.value.isEmpty }
            if updatedProductPrebuilts == productPrebuilts {
                return plans
            }
            productPrebuilts = updatedProductPrebuilts
        }
    }

    /// The product dependencies of a target that the build uses, skipping those whose traits are disabled or whose platforms
    /// Tuist doesn't support. Like SwiftPM, which requires a by-name dependency on another package's product to name both
    /// the product and its package, a by-name dependency that names no target of the package names the package too.
    private static func productDependencies(
        of target: PackageInfo.Target,
        in packageInfo: PackageInfo,
        enabledTraits: Set<String>
    ) -> [(name: String, package: String)] {
        target.dependencies.compactMap { dependency in
            switch dependency {
            case let .product(name, package, _, condition) where isUsed(condition, enabledTraits: enabledTraits):
                (name, package)
            case let .byName(name, condition) where !packageInfo.targets.contains(where: { $0.name == name })
                && isUsed(condition, enabledTraits: enabledTraits):
                (name, name)
            case .product, .byName, .target:
                nil
            }
        }
    }

    /// How a package's targets link SwiftPM's prebuilt libraries.
    private struct PackagePrebuiltsPlan {
        /// The targets that link the prebuilts.
        var targets: [String: PrebuiltTarget] = [:]
        /// The prebuilts that consumers of each product need on macOS, where the product's targets link them.
        var productPrebuilts: [String: Set<SwiftPackageManagerPrebuilt>] = [:]
        /// The products whose targets link swift-syntax built from source on macOS.
        var sourceSwiftSyntaxProducts: Set<String> = []
        /// The packages that targets apps build consume a product of that links the prebuilts.
        var appConsumedPackages: [String] = []
        /// The products of other packages that targets outside `targets` consume.
        var appConsumedProducts: [(package: String, product: String)] = []
    }

    // swiftlint:disable function_body_length

    /// Returns the targets of a package that link SwiftPM's prebuilt libraries (swift-syntax's `MacroSupport`) instead of
    /// their source products, with the platforms they link them on and the prebuilts their dependencies link.
    ///
    /// Macros and their tests only build for the host, so they always link the prebuilt. Other targets that only macros
    /// reach, such as swift-case-paths' `CasePathsMacrosSupport`, can still be built for app platforms through their library
    /// products, so, like swift-build, they link the prebuilt on macOS and keep the source products elsewhere.
    ///
    /// A target that a target outside the macros' closure also depends on, or that a macro test links outside that closure,
    /// is built into apps on every platform, macOS included. Tuist doesn't pass the prebuilt's module search paths and
    /// library on to that target's consumers, and a macro or macro test can't link it alongside the prebuilt, so when such a
    /// target uses swift-syntax, the package keeps its source products, as it did before prebuilts were supported.
    private static func packagePrebuiltsPlan(
        packageInfo: PackageInfo,
        packageType: PackageType,
        includeLocalPackageTestTargets: Bool,
        enabledTraits: Set<String>,
        keepsSourceProducts: Bool = false,
        hostConsumedProducts: Set<String> = [],
        productPrebuilts: (_ package: String, _ product: String) -> Set<SwiftPackageManagerPrebuilt>? = { _, _ in nil },
        sourceSwiftSyntaxProduct: (_ package: String, _ product: String) -> Bool = { _, _ in false }
    ) throws -> PackagePrebuiltsPlan {
        guard !packageType.packagePrebuilts.isEmpty else { return PackagePrebuiltsPlan() }

        let includesTestTargets = packageType.includesTestTargets(
            includeLocalPackageTestTargets: includeLocalPackageTestTargets
        )
        let mappedTargets = packageInfo.targets.filter { includesTestTargets || $0.type != .test }
        let targetsByName = Dictionary(uniqueKeysWithValues: mappedTargets.map { ($0.name, $0) })

        func isMacro(_ targetName: String) -> Bool {
            targetsByName[targetName]?.type == .macro
        }

        // The package targets that `targetName` depends on. With `linkedOnly`, only those it links: targets that use a
        // macro run it as a compiler plugin, and only macros and tests link the macros they depend on.
        func dependencies(of targetName: String, linkedOnly: Bool = true) -> [String] {
            let linksMacros = !linkedOnly || isMacro(targetName) || targetsByName[targetName]?.type == .test
            return targetsByName[targetName]?.dependencies.compactMap { dependency in
                switch dependency {
                case let .target(name, _), let .byName(name, _):
                    targetsByName[name] == nil || (!linksMacros && isMacro(name)) ? nil : name
                case .product:
                    nil
                }
            } ?? []
        }

        func dependencyClosure(from roots: some Sequence<String>, linkedOnly: Bool = true) -> Set<String> {
            var visited = Set<String>()
            var queue = Array(roots)
            while let targetName = queue.popLast() {
                guard visited.insert(targetName).inserted else { continue }
                queue.append(contentsOf: dependencies(of: targetName, linkedOnly: linkedOnly))
            }
            return visited
        }

        func productDependencies(of targetName: String) -> [(name: String, package: String)] {
            targetsByName[targetName].map {
                Self.productDependencies(of: $0, in: packageInfo, enabledTraits: enabledTraits)
            } ?? []
        }

        func dependsOnPrebuiltProduct(_ targetName: String) -> Bool {
            targetsByName[targetName]?.dependencies.contains { dependency in
                guard case let .product(name, package, _, _) = dependency else { return false }
                return packageType.prebuilt(targetPackage: package, product: name) != nil
            } ?? false
        }

        // The prebuilts of a target's swift-syntax products, which replace them.
        func swiftSyntaxPrebuilts(of targetName: String) -> [SwiftPackageManagerPrebuilt] {
            productDependencies(of: targetName).compactMap { packageType.prebuilt(targetPackage: $0.package, product: $0.name) }
        }

        // The prebuilts that the products of other packages that a target consumes link on macOS.
        func consumedProductPrebuilts(of targetName: String) -> [SwiftPackageManagerPrebuilt] {
            productDependencies(of: targetName).flatMap { dependency in
                (productPrebuilts(dependency.package, dependency.name) ?? []).sorted { $0.path.pathString < $1.path.pathString }
            }
        }

        func appConsumedProducts(excluding prebuiltTargets: Set<String>) -> [(package: String, product: String)] {
            targetsByName.keys.filter { !prebuiltTargets.contains($0) }.flatMap { targetName in
                productDependencies(of: targetName).map { (package: $0.package, product: $0.name) }
            }
        }

        func appConsumedPackages(excluding prebuiltTargets: Set<String>) -> [String] {
            targetsByName.keys.filter { !prebuiltTargets.contains($0) }.flatMap { targetName in
                productDependencies(of: targetName).filter { productPrebuilts($0.package, $0.name) != nil }.map(\.package)
            }
        }

        func consumesSourceSwiftSyntaxProduct(_ targetName: String) -> Bool {
            productDependencies(of: targetName).contains { sourceSwiftSyntaxProduct($0.package, $0.name) }
        }

        // The products whose targets link swift-syntax built from source on macOS, directly or through the products of
        // other packages.
        func sourceSwiftSyntaxProducts(excluding prebuiltTargets: Set<String>) -> Set<String> {
            Set(packageInfo.products.filter { product in
                dependencyClosure(from: product.targets).contains { targetName in
                    !prebuiltTargets.contains(targetName)
                        && (!swiftSyntaxPrebuilts(of: targetName).isEmpty || consumesSourceSwiftSyntaxProduct(targetName))
                }
            }.map(\.name))
        }

        let macroTargets = Set(mappedTargets.filter { $0.type == .macro }.map(\.name))
        let macroClosure = dependencyClosure(from: macroTargets)
        // Tests that link a macro, as in SwiftPM, or only targets that macros reach, are host-only. Other tests, such as one
        // that links a target only macros reach next to a library apps build, build for the apps' platforms.
        let macroTestTargets = Set(mappedTargets.filter { target in
            guard target.type == .test else { return false }
            let linkedTargets = dependencies(of: target.name)
            return linkedTargets.contains(where: isMacro)
                || (!linkedTargets.isEmpty && macroClosure.isSuperset(of: linkedTargets))
        }.map(\.name))
        let hostOnlyTargets = macroTargets.union(macroTestTargets)
        // The targets of the products that only other packages' macros, macro tests, and targets those reach consume, which
        // macros reach too.
        let hostConsumedTargets = packageInfo.products.filter { hostConsumedProducts.contains($0.name) }
            .flatMap(\.targets).filter { targetsByName[$0] != nil }
        let macroReachedTargets = dependencyClosure(from: macroTargets.union(hostConsumedTargets))

        // Targets outside the macros' closure, such as the libraries that use the macros and the libraries that macro tests
        // test, build into apps on every platform, macOS included, with source products. Macros and macro tests that link
        // one of them that uses swift-syntax can't also link the prebuilt.
        let appTargets = dependencyClosure(
            from: targetsByName.keys.filter { !hostOnlyTargets.contains($0) && !macroReachedTargets.contains($0) }
        )
        let hostOnlyClosure = dependencyClosure(from: hostOnlyTargets.union(hostConsumedTargets))
        let sharedTargets = hostOnlyClosure.intersection(appTargets)
        let prebuiltTargetNames = hostOnlyTargets.union(macroReachedTargets.subtracting(appTargets))
        // Macros and macro tests link the prebuilt and every target they reach, including those shared with apps, so
        // none of those can link another package's product built against source swift-syntax.
        guard !keepsSourceProducts,
              !sharedTargets.contains(where: dependsOnPrebuiltProduct),
              !hostOnlyClosure.contains(where: consumesSourceSwiftSyntaxProduct)
        else {
            // A package that keeps its source products, for example because a product it consumes does, may link the
            // prebuilt once other packages settle, so only the products that targets outside the would-be prebuilt targets
            // consume stop counting as consumed by prebuilt targets alone. Its consumers of products that link the prebuilt
            // keep those products' packages on source products meanwhile.
            return PackagePrebuiltsPlan(
                sourceSwiftSyntaxProducts: sourceSwiftSyntaxProducts(excluding: []),
                appConsumedPackages: appConsumedPackages(excluding: []),
                appConsumedProducts: appConsumedProducts(excluding: prebuiltTargetNames)
            )
        }

        // Targets import the modules of the targets they depend on, which import swift-syntax, and macros and macro tests
        // link those targets statically, so they need the prebuilts those targets link too.
        let targets = Dictionary(uniqueKeysWithValues: prebuiltTargetNames.map { targetName in
            let dependencyPrebuilts = consumedProductPrebuilts(of: targetName) + dependencyClosure(
                from: dependencies(of: targetName)
            ).sorted().flatMap { swiftSyntaxPrebuilts(of: $0) + consumedProductPrebuilts(of: $0) }
            return (
                targetName,
                PrebuiltTarget(
                    platforms: hostOnlyTargets.contains(targetName) ? .all : .macOS,
                    dependencyPrebuilts: dependencyPrebuilts
                )
            )
        })

        // Consumers of a product import its targets' modules, and link them, so they need the prebuilts the targets link.
        let productPrebuilts = packageInfo.products
            .reduce(into: [String: Set<SwiftPackageManagerPrebuilt>]()) { result, product in
                let prebuilts = Set(product.targets.flatMap { targetName -> [SwiftPackageManagerPrebuilt] in
                    guard let target = targets[targetName], target.platforms == .macOS else { return [] }
                    return swiftSyntaxPrebuilts(of: targetName) + target.dependencyPrebuilts
                })
                if !prebuilts.isEmpty { result[product.name] = prebuilts }
            }

        return PackagePrebuiltsPlan(
            targets: targets,
            productPrebuilts: productPrebuilts,
            sourceSwiftSyntaxProducts: sourceSwiftSyntaxProducts(excluding: prebuiltTargetNames),
            appConsumedPackages: appConsumedPackages(excluding: prebuiltTargetNames),
            appConsumedProducts: appConsumedProducts(excluding: prebuiltTargetNames)
        )
    }

    // swiftlint:enable function_body_length

    // swiftlint:disable:next function_body_length
    private func map(
        target: PackageInfo.Target,
        targetToProducts: [String: Set<PackageInfo.Product>],
        targetsByName: [String: PackageInfo.Target],
        packageInfo: PackageInfo,
        packageType: PackageType,
        packageSettings: TuistCore.PackageSettings,
        path: AbsolutePath,
        packageFolder: AbsolutePath,
        productTypes: [String: XcodeGraph.Product],
        baseProductType: XcodeGraph.Product,
        productDestinations: [String: XcodeGraph.Destinations],
        baseSettings: XcodeGraph.Settings,
        targetSettings: [String: XcodeGraph.Settings],
        packageModuleAliases: [String: [String: String]],
        packageProducts: [String: [String: [ProjectDescription.TargetDependency]]],
        packageTraits: [PackageTrait],
        enabledTraits: Set<String>,
        prebuilts: PrebuiltTarget?
    ) async throws -> ProjectDescription.Target? {
        // Ignores or passes a target based on the `type` and the `packageType`.
        // After that, it assumes that no target is ignored.
        switch target.type {
        case .test where !packageType.includesTestTargets(
            includeLocalPackageTestTargets: packageSettings.includeLocalPackageTestTargets
        ):
            Logger.current.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        case .regular, .system, .macro, .test:
            break
        case .executable:
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

        if target.type == .test,
           case .external(
               origin: .local,
               artifactPaths: _,
               packagePrebuilts: _,
               derivedXCFrameworksPath: _,
               prebuiltTargets: _
           ) = packageType,
           let executableName = target.dependencies.compactMap({ dependency -> String? in
               switch dependency {
               case let .target(name, _), let .byName(name, _):
                   return targetsByName[name]?.type == .executable ? name : nil
               case .product:
                   return nil
               }
           }).first
        {
            throw PackageInfoMapperError.unsupportedExecutableTargetInLocalPackageTest(
                package: packageInfo.name,
                target: target.name,
                executable: executableName
            )
        }

        let products = targetToProducts[target.name] ?? Set()

        guard let product = ProjectDescription.Product.from(
            name: target.name,
            type: target.type,
            products: products,
            productTypes: productTypes,
            baseProductType: baseProductType
        )
        else {
            Logger.current.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let targetPath = try await target.basePath(packageFolder: packageFolder)

        let moduleMapModuleName: String?
        let moduleMap: ModuleMap?
        switch target.type {
        case .system:
            moduleMapModuleName = nil
            // System library targets assume the module map is located at the source directory root
            // https://github.com/apple/swift-package-manager/blob/main/Sources/PackageLoading/ModuleMapGenerator.swift
            let packagePath = try await target.basePath(packageFolder: path)
            let moduleMapPath = packagePath.appending(component: ModuleMap.filename)

            guard try await fileSystem.exists(moduleMapPath, isDirectory: false) else {
                throw PackageInfoMapperError.modulemapMissing(
                    moduleMapPath: moduleMapPath.pathString,
                    package: packageInfo.name,
                    target: target.name
                )
            }

            moduleMap = ModuleMap.custom(moduleMapPath, umbrellaHeaderPath: nil)
        case .regular, .test:
            let resolvedModuleName = PackageInfoMapper.effectiveModuleName(
                targetName: target.name, products: products, targetsByName: targetsByName
            )
            moduleMapModuleName = resolvedModuleName
            let swiftPackageManagerScratchDirectory: AbsolutePath? = if packageType.isRemoteExternal {
                SwiftPackageManagerPaths.scratchDirectory(containingPackageSource: path)
            } else {
                nil
            }
            moduleMap = try await moduleMapGenerator.generate(
                packageDirectory: path,
                moduleName: resolvedModuleName,
                publicHeadersPath: target.publicHeadersPath(packageFolder: path),
                swiftPackageManagerScratchDirectory: swiftPackageManagerScratchDirectory
            )
        default:
            moduleMapModuleName = nil
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

        let minDeploymentTargets = try await ProjectDescription.DeploymentTargets.minimumSupportedVersions()

        let deploymentTargets = try await ProjectDescription.DeploymentTargets.from(
            minDeploymentTargets: minDeploymentTargets,
            minMacCatalystDeploymentTarget: ProjectDescription.DeploymentTargets.minimumSupportedMacCatalystVersion(),
            package: packageInfo.platforms,
            destinations: destinations,
            packageName: packageInfo.name
        )

        var headers: ProjectDescription.Headers?
        var sources: SourceFilesList?
        var resources: ProjectDescription.ResourceFileElements?

        if target.type.supportsPublicHeaderPath {
            headers = try await discoveredHeaders(
                for: target,
                moduleMap: moduleMap,
                moduleName: moduleMapModuleName,
                targetPath: targetPath,
                publicHeadersPath: try await target.publicHeadersPath(packageFolder: path)
            )
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
        let prebuiltPlatforms = prebuilts?.platforms
        var targetPrebuilts = prebuilts?.dependencyPrebuilts ?? []

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
                    (.linker, .unsafeFlags), (.linker, .disableWarning), (_, .enableExperimentalFeature), (_, .swiftLanguageMode),
                    (.linker, .treatAllWarnings), (.linker, .treatWarning), (.linker, .enableWarning),
                    (
                        _,
                        .defaultIsolation
                    ), (
                        _,
                        .strictMemorySafety
                    ):
                        return nil
                    }
                } catch {
                    return nil
                }
            }

            let targetDependencies = try await target.dependencies + samePackageTargetDependenciesImportedByPublicHeaders(
                for: target,
                packageInfo: packageInfo,
                packageFolder: packageFolder
            )

            for dependency in targetDependencies {
                switch dependency {
                case let .product(name: name, package: package, moduleAliases: moduleAliases, condition: condition):
                    var sourceCondition = condition
                    if let prebuiltPlatforms,
                       let prebuilt = try prebuiltDependency(
                           name: name,
                           targetPackage: package,
                           packageType: packageType,
                           condition: condition,
                           enabledTraits: enabledTraits
                       )
                    {
                        switch prebuiltPlatforms {
                        case .all:
                            targetPrebuilts.append(prebuilt)
                            continue
                        case .macOS:
                            let platformNames = condition.map(\.platformNames).flatMap { $0.isEmpty ? nil : $0 }
                                ?? ["ios", "maccatalyst", "macos", "tvos", "watchos", "visionos"]
                            if platformNames.contains("macos") {
                                targetPrebuilts.append(prebuilt)
                                let sourcePlatformNames = platformNames.filter { $0 != "macos" }
                                guard !sourcePlatformNames.isEmpty else { continue }
                                sourceCondition = .init(
                                    platformNames: sourcePlatformNames,
                                    config: condition?.config,
                                    traits: condition?.traits
                                )
                            }
                        }
                    }
                    dependencies.append(contentsOf: try await mapDependency(
                        name: name,
                        targetPackage: package,
                        sourceTargetName: target.name,
                        packageInfo: packageInfo,
                        packageType: packageType,
                        packageSettings: packageSettings,
                        packageProducts: packageProducts,
                        condition: sourceCondition,
                        moduleAliases: moduleAliases,
                        dependencyModuleAliases: &dependencyModuleAliases,
                        enabledTraits: enabledTraits
                    ))
                case let .byName(name: name, condition: condition),
                     let .target(
                         name: name,
                         condition: condition
                     ):
                    dependencies.append(contentsOf: try await mapDependency(
                        name: name,
                        packageInfo: packageInfo,
                        packageType: packageType,
                        packageSettings: packageSettings,
                        condition: condition,
                        moduleAliases: packageModuleAliases[packageInfo.name],
                        dependencyModuleAliases: &dependencyModuleAliases,
                        enabledTraits: enabledTraits
                    ))
                }
            }
            dependencies = linkerDependencies + dependencies
            let cxxStandardLibrary = ProjectDescription.TargetDependency.sdk(name: "c++", type: .library, status: .required)
            if !dependencies.contains(cxxStandardLibrary), try await hasCxxSources(target: target, targetPath: targetPath) {
                dependencies.append(cxxStandardLibrary)
            }
        }

        let targetName = packageModuleAliases[packageInfo.name]?[target.name] ?? target.name
        let sanitizedTargetName = PackageInfoMapper.sanitize(targetName: targetName)
        let effectiveModuleName = PackageInfoMapper.effectiveModuleName(
            targetName: target.name, products: products, targetsByName: targetsByName
        )
        let aliasedEffectiveModuleName = packageModuleAliases[packageInfo.name]?[effectiveModuleName] ?? effectiveModuleName
        let moduleName = PackageInfoMapper.sanitize(targetName: aliasedEffectiveModuleName)
            .replacingOccurrences(of: "-", with: "_")
        let effectiveProductName = PackageInfoMapper.effectiveProductName(
            targetName: target.name, products: products, targetsByName: targetsByName
        )
        let aliasedEffectiveProductName = packageModuleAliases[packageInfo.name]?[effectiveProductName] ?? effectiveProductName
        let productName = PackageInfoMapper.sanitize(targetName: aliasedEffectiveProductName)
            .replacingOccurrences(of: "-", with: "_")

        let settings = try await Settings.from(
            target: target,
            productName: productName,
            moduleName: moduleName,
            packageName: packageInfo.name,
            swiftToolsVersion: Version(stringLiteral: packageInfo.toolsVersion.description),
            packageFolder: packageFolder,
            settings: target.settings,
            moduleMap: moduleMap,
            baseSettings: baseSettings,
            targetSettings: targetSettings[target.name],
            dependencyModuleAliases: dependencyModuleAliases,
            packageTraits: packageTraits,
            enabledTraits: enabledTraits,
            prebuilts: targetPrebuilts,
            prebuiltPlatforms: prebuiltPlatforms
        )

        var metadataTags = [TargetTags.swiftPackage]
        if target.type == .test, packageType.isLocalExternal {
            metadataTags.append(TargetTags.localSwiftPackageTest)
        }

        return .target(
            name: sanitizedTargetName,
            destinations: destinations,
            product: product,
            productName: productName,
            bundleId: PackageInfoMapper.sanitize(bundleIdentifierComponent: targetName),
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: sources,
            resources: resources,
            buildableFolders: [],
            headers: headers,
            dependencies: dependencies,
            settings: settings,
            metadata: .metadata(tags: metadataTags)
        )
    }

    /// SwiftPM headers remain compiler and cache inputs, but do not become Xcode header build files.
    /// In particular, a directory module preserves its include hierarchy instead of flattening every
    /// nested header into a framework. Custom and umbrella maps keep their original module composition.
    /// `exclude` only removes project headers: everything under the public headers path stays includable
    /// through its search path, as it does in SwiftPM.
    private func discoveredHeaders(
        for target: PackageInfo.Target,
        moduleMap: ModuleMap?,
        moduleName: String?,
        targetPath: AbsolutePath,
        publicHeadersPath: AbsolutePath
    ) async throws -> ProjectDescription.Headers? {
        guard let moduleMap, let moduleMapPath = moduleMap.moduleMapPath, let moduleName else { return nil }
        let usesDirectoryModuleMap: Bool
        switch moduleMap {
        case .none: return nil
        case .directory: usesDirectoryModuleMap = true
        case .custom, .header: usesDirectoryModuleMap = false
        }

        let headersGlob = "**/*.{h,hh,hpp,h++,hp,hxx,H,ipp,def}"
        let excluding: [ProjectDescription.Path] = try await target.exclude.concurrentMap {
            let path = targetPath.appending(try RelativePath(validating: $0))
            let isDirectory = try await fileSystem.exists(path, isDirectory: true)
            return .path(isDirectory ? path.appending(component: "**").pathString : path.pathString)
        }
        return .swiftPackageHeaders(
            public: .list([.glob(.path("\(publicHeadersPath.pathString)/\(headersGlob)"))]),
            project: .list([.glob(.path("\(targetPath.pathString)/\(headersGlob)"), excluding: excluding)]),
            sourceLayout: .init(
                root: .path(targetPath.pathString),
                publicHeaders: .path(publicHeadersPath.pathString),
                moduleMap: .path(moduleMapPath.pathString),
                moduleName: moduleName.sanitizedModuleName,
                usesDirectoryModuleMap: usesDirectoryModuleMap
            )
        )
    }

    /// Whether the target compiles C++ or Objective-C++ sources. SwiftPM links the C++ standard library into every client of
    /// such a module, which a client that only compiles Swift, C, or Objective-C would otherwise not link.
    private func hasCxxSources(target: PackageInfo.Target, targetPath: AbsolutePath) async throws -> Bool {
        guard target.type.supportsSources else { return false }
        let cxxExtensions = "{cpp,cc,cxx,mm}"
        let excludedPaths = try target.exclude.map { targetPath.appending(try RelativePath(validating: $0)) }
        let sourcePaths = try target.sources?.map { targetPath.appending(try RelativePath(validating: $0)) } ?? [targetPath]
        for sourcePath in sourcePaths {
            let candidates: [AbsolutePath] = if try await fileSystem.exists(sourcePath, isDirectory: true) {
                try await fileSystem.glob(directory: sourcePath, include: ["*.\(cxxExtensions)", "**/*.\(cxxExtensions)"])
                    .collect()
            } else if let fileExtension = sourcePath.extension, ["cpp", "cc", "cxx", "mm"].contains(fileExtension) {
                [sourcePath]
            } else {
                []
            }
            if candidates.contains(where: { candidate in
                !excludedPaths.contains(where: { candidate.isDescendantOfOrEqual(to: $0) })
            }) {
                return true
            }
        }
        return false
    }

    private func prebuiltDependency(
        name: String,
        targetPackage: String,
        packageType: PackageType,
        condition: PackageInfo.PackageConditionDescription?,
        enabledTraits: Set<String>
    ) throws -> SwiftPackageManagerPrebuilt? {
        guard Self.isUsed(condition, enabledTraits: enabledTraits) else { return nil }
        return packageType.prebuilt(targetPackage: targetPackage, product: name)
    }

    /// Whether the build uses a dependency with the given condition: its traits are enabled and Tuist supports its platforms.
    private static func isUsed(_ condition: PackageInfo.PackageConditionDescription?, enabledTraits: Set<String>) -> Bool {
        if let traits = condition?.traits, !traits.isEmpty, !traits.contains(where: { enabledTraits.contains($0) }) {
            return false
        }
        do {
            _ = try ProjectDescription.PlatformCondition.from(condition)
            return true
        } catch {
            return false
        }
    }

    private func samePackageTargetDependenciesImportedByPublicHeaders(
        for target: PackageInfo.Target,
        packageInfo: PackageInfo,
        packageFolder: AbsolutePath
    ) async throws -> [PackageInfo.Target.Dependency] {
        // SwiftPM relies on manifest-declared target dependencies and does not add these edges by scanning
        // public headers. This is limited to concrete public `#import` and `#include` statements to support
        // packages such as Firebase that document, but do not declare, a same-package target dependency:
        // https://github.com/firebase/firebase-ios-sdk/blob/1fc52ab0e172e7c5a961f975a76c2611f4f22852/Package.swift#L213-L225
        guard target.type == .regular else { return [] }

        let publicHeadersPath = try await target.publicHeadersPath(packageFolder: packageFolder)
        guard try await fileSystem.exists(publicHeadersPath) else { return [] }

        let importedModules = try await importedModules(inPublicHeadersAt: publicHeadersPath)
        guard !importedModules.isEmpty else { return [] }

        let declaredDependencyNames = Set(target.dependencies.map(\.name))
        return packageInfo.targets
            .filter { $0.name != target.name && !declaredDependencyNames.contains($0.name) }
            .filter { $0.type == .regular }
            .filter {
                !packageTarget(
                    named: $0.name,
                    dependsOn: target.name,
                    packageInfo: packageInfo
                )
            }
            .filter {
                moduleNameCandidates(targetName: $0.name).contains(where: importedModules.contains)
            }
            .map { .target(name: $0.name, condition: nil) }
    }

    private func packageTarget(
        named targetName: String,
        dependsOn dependencyName: String,
        packageInfo: PackageInfo
    ) -> Bool {
        let targetsByName = Dictionary(uniqueKeysWithValues: packageInfo.targets.map { ($0.name, $0) })
        let productsByName = Dictionary(uniqueKeysWithValues: packageInfo.products.map { ($0.name, $0) })
        var targetsToVisit = [targetName]
        var visitedTargets = Set<String>()

        while let currentTargetName = targetsToVisit.popLast() {
            guard !visitedTargets.contains(currentTargetName),
                  let currentTarget = targetsByName[currentTargetName]
            else { continue }
            visitedTargets.insert(currentTargetName)

            for dependency in currentTarget.dependencies {
                switch dependency {
                case let .target(name: name, _):
                    if name == dependencyName { return true }
                    targetsToVisit.append(name)
                case let .byName(name: name, _):
                    if name == dependencyName { return true }
                    if targetsByName[name] != nil {
                        targetsToVisit.append(name)
                    } else if let product = productsByName[name] {
                        if product.targets.contains(dependencyName) { return true }
                        targetsToVisit.append(contentsOf: product.targets)
                    }
                case let .product(name: name, package: package, _, _):
                    guard package == nil || package == packageInfo.name,
                          let product = productsByName[name]
                    else { continue }
                    if product.targets.contains(dependencyName) { return true }
                    targetsToVisit.append(contentsOf: product.targets)
                }
            }
        }

        return false
    }

    private func importedModules(inPublicHeadersAt publicHeadersPath: AbsolutePath) async throws -> Set<String> {
        let headerPaths = try await fileSystem
            .glob(directory: publicHeadersPath, include: ["**/*.{h,hh,hpp,hxx}", "*.{h,hh,hpp,hxx}"])
            .collect()

        var modules = Set<String>()
        for headerPath in headerPaths {
            let contents = try await fileSystem.readTextFile(at: headerPath)
            modules.formUnion(PackageInfoMapper.importedModules(inHeader: contents))
        }

        return modules
    }

    private func moduleNameCandidates(targetName: String) -> Set<String> {
        [
            targetName,
            PackageInfoMapper.sanitize(targetName: targetName),
        ]
    }

    private static func importedModules(inHeader header: String) -> Set<String> {
        let headerWithoutComments = header.strippingCComments()
        let importPatterns = [
            #"#\s*(?:import|include)\s+<([A-Za-z_][A-Za-z0-9_]*)/"#,
        ]

        return importPatterns.reduce(into: Set<String>()) { modules, pattern in
            guard let regularExpression = try? NSRegularExpression(pattern: pattern) else { return }

            let range = NSRange(headerWithoutComments.startIndex ..< headerWithoutComments.endIndex, in: headerWithoutComments)
            for match in regularExpression.matches(in: headerWithoutComments, range: range) {
                guard let moduleRange = Range(match.range(at: 1), in: headerWithoutComments) else { continue }
                modules.insert(String(headerWithoutComments[moduleRange]))
            }
        }
    }

    private func mapDependency(
        name: String,
        targetPackage: String? = nil,
        sourceTargetName: String? = nil,
        packageInfo: PackageInfo,
        packageType: PackageType,
        packageSettings: TuistCore.PackageSettings,
        packageProducts: [String: [String: [ProjectDescription.TargetDependency]]] = [:],
        condition: PackageInfo.PackageConditionDescription?,
        moduleAliases: [String: String]?,
        dependencyModuleAliases: inout [String: String],
        enabledTraits: Set<String>
    ) async throws -> [ProjectDescription.TargetDependency] {
        // If the condition has traits, check if any of them are enabled
        // If none are enabled, skip this dependency
        if let traits = condition?.traits, !traits.isEmpty {
            let hasEnabledTrait = traits.contains { enabledTraits.contains($0) }
            if !hasEnabledTrait {
                return []
            }
        }
        let platformCondition: ProjectDescription.PlatformCondition?
        do {
            platformCondition = try ProjectDescription.PlatformCondition.from(condition)
        } catch {
            return []
        }
        // Product names are only unique within a package, so a product dependency that names its package resolves against that
        // package's products.
        if let targetPackage, moduleAliases?[name] == nil,
           let productDependencies = Self.products(ofPackage: targetPackage, in: packageProducts)?[name]
        {
            return productDependencies.map { $0.withCondition(platformCondition) }
        }
        // If this is a .product dependency that explicitly references a different package
        // and the dependency name matches the source target name with no module alias
        // to disambiguate (or the alias resolves to the same name), it would create a
        // self-referential loop. Resolve as external to avoid the circular dependency.
        if let targetPackage, targetPackage != packageInfo.name,
           let sourceTargetName, sourceTargetName == name,
           moduleAliases?[name].map({ $0 == sourceTargetName }) != false
        {
            return [.external(name: name, condition: platformCondition)]
        }

        if let target = packageInfo.targets.first(where: { $0.name == name }) {
            if target.type == .binary,
               case let .external(
                   origin: _,
                   artifactPaths: artifactPaths,
                   packagePrebuilts: _,
                   derivedXCFrameworksPath: derivedXCFrameworksPath,
                   prebuiltTargets: _
               ) = packageType,
               let artifactPath = artifactPaths[target.name]
            {
                let dependencyPath = try await binaryArtifactDependencyPath(
                    targetName: target.name,
                    packageName: packageInfo.name,
                    artifactPath: artifactPath,
                    derivedXCFrameworksPath: derivedXCFrameworksPath
                )
                return [.xcframework(
                    path: dependencyPath,
                    expectedSignature: packageSettings.expectedSignatures[target.name]
                        .map(ProjectDescription.XCFrameworkSignature.from),
                    status: .required,
                    condition: platformCondition
                )]
            }
            if let aliasedName = moduleAliases?[name] {
                dependencyModuleAliases[name] = aliasedName
                return [.target(name: PackageInfoMapper.sanitize(targetName: aliasedName), condition: platformCondition)]
            } else {
                return [.target(name: PackageInfoMapper.sanitize(targetName: name), condition: platformCondition)]
            }
        } else {
            if let aliasedName = moduleAliases?[name] {
                dependencyModuleAliases[name] = aliasedName
                return [.external(name: aliasedName, condition: platformCondition)]
            } else {
                return [.external(name: name, condition: platformCondition)]
            }
        }
    }

    private func binaryArtifactDependencyPath(
        targetName: String,
        packageName: String,
        artifactPath: AbsolutePath,
        derivedXCFrameworksPath: AbsolutePath?
    ) async throws -> Path {
        let xcframeworkPath = try await staticLibraryArtifactBundleXCFrameworkPath(
            targetName: targetName,
            packageName: packageName,
            artifactBundlePath: artifactPath,
            derivedXCFrameworksPath: derivedXCFrameworksPath
        ) ?? artifactPath
        return .path(xcframeworkPath.pathString)
    }

    private func staticLibraryArtifactBundleXCFrameworkPath(
        targetName: String,
        packageName: String,
        artifactBundlePath: AbsolutePath,
        derivedXCFrameworksPath: AbsolutePath?
    ) async throws -> AbsolutePath? {
        guard artifactBundlePath.extension == "artifactbundle" else { return nil }
        let infoPath = artifactBundlePath.appending(component: "info.json")
        guard try await fileSystem.exists(infoPath) else { return nil }

        let infoData = try await fileSystem.readFile(at: infoPath)
        let info = try JSONDecoder().decode(StaticLibraryArtifactBundleInfo.self, from: infoData)
        guard let artifact = info.artifacts[targetName] ?? (info.artifacts.count == 1 ? info.artifacts.values.first : nil),
              artifact.type == "staticLibrary"
        else {
            return nil
        }

        guard let derivedXCFrameworksPath = derivedXCFrameworksPath
            ?? Self.derivedXCFrameworksPath(containingArtifact: artifactBundlePath)
        else { return nil }
        let contentHasher = ContentHasher()
        let sourceFingerprint = try contentHasher.hash([
            artifactBundlePath.pathString,
            contentHasher.hash(infoData),
        ])
        let xcframeworkPath = derivedXCFrameworksPath
            .appending(component: Self.sanitize(targetName: packageName))
            .appending(component: "\(Self.sanitize(targetName: targetName))-\(sourceFingerprint).xcframework")
        let infoPlistPath = xcframeworkPath.appending(component: "Info.plist")
        if try await fileSystem.exists(infoPlistPath) {
            return xcframeworkPath
        }

        if try await fileSystem.exists(xcframeworkPath) {
            try await fileSystem.remove(xcframeworkPath)
        }
        try await fileSystem.makeDirectory(at: xcframeworkPath)

        var libraries: [XCFrameworkInfoPlist.Library] = []
        var usedIdentifiers: Set<String> = []

        for variant in artifact.variants {
            let sourceLibrary = artifactBundlePath.appending(try RelativePath(validating: variant.path))
            let slices = Dictionary(
                grouping: variant.supportedTriples.compactMap { StaticLibraryArtifactBundleSlice(supportedTriple: $0) },
                by: \.identifier
            )
            for sliceIdentifier in slices.keys.sorted() {
                let sliceArchitectures = slices[sliceIdentifier, default: []].map(\.architecture).uniqued().sorted(by: {
                    $0.rawValue < $1.rawValue
                })
                guard !sliceArchitectures.isEmpty else { continue }

                let identifier = uniqueXCFrameworkLibraryIdentifier(
                    preferredIdentifier: sourceLibrary.parentDirectory.basename,
                    usedIdentifiers: &usedIdentifiers
                )
                let slicePath = xcframeworkPath.appending(component: identifier)
                try await fileSystem.makeDirectory(at: slicePath)
                try await fileSystem.createSymbolicLink(
                    from: slicePath.appending(component: sourceLibrary.basename),
                    to: sourceLibrary
                )

                let headersPath = try await linkStaticLibraryArtifactBundleHeaders(
                    metadata: variant.staticLibraryMetadata,
                    artifactBundlePath: artifactBundlePath,
                    slicePath: slicePath
                )

                libraries.append(XCFrameworkInfoPlist.Library(
                    identifier: identifier,
                    path: try RelativePath(validating: sourceLibrary.basename),
                    headersPath: headersPath,
                    mergeable: false,
                    platform: sliceIdentifier.platform,
                    platformVariant: sliceIdentifier.platformVariant,
                    architectures: sliceArchitectures
                ))
            }
        }

        guard !libraries.isEmpty else {
            try await fileSystem.remove(xcframeworkPath)
            return nil
        }

        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .xml
        try await fileSystem.writeAsPlist(
            XCFrameworkInfoPlist(libraries: libraries),
            at: infoPlistPath,
            encoder: plistEncoder
        )
        return xcframeworkPath
    }

    private static func derivedXCFrameworksPath(containingArtifact artifactPath: AbsolutePath) -> AbsolutePath? {
        var current = artifactPath
        while current != .root {
            if current.basename == "artifacts" {
                return current.parentDirectory.appending(
                    components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesXCFrameworkDirectory
                )
            }
            current = current.parentDirectory
        }
        return nil
    }

    private func linkStaticLibraryArtifactBundleHeaders(
        metadata: StaticLibraryArtifactBundleInfo.Artifact.Variant.StaticLibraryMetadata?,
        artifactBundlePath: AbsolutePath,
        slicePath: AbsolutePath
    ) async throws -> RelativePath? {
        let headersPath = slicePath.appending(component: "Headers")
        var linkedHeaders = false

        for headerPath in metadata?.headerPaths ?? [] {
            let sourceHeaderPath = artifactBundlePath.appending(try RelativePath(validating: headerPath))
            if !linkedHeaders {
                try await fileSystem.makeDirectory(at: headersPath)
                linkedHeaders = true
            }

            if try await fileSystem.exists(sourceHeaderPath, isDirectory: true) {
                for header in try await fileSystem.contentsOfDirectory(sourceHeaderPath) {
                    try await linkStaticLibraryArtifactBundleHeader(
                        from: header,
                        to: headersPath.appending(component: header.basename)
                    )
                }
            } else {
                try await linkStaticLibraryArtifactBundleHeader(
                    from: sourceHeaderPath,
                    to: headersPath.appending(component: sourceHeaderPath.basename)
                )
            }
        }

        if let moduleMapPath = metadata?.moduleMapPath {
            let sourceModuleMapPath = artifactBundlePath.appending(try RelativePath(validating: moduleMapPath))
            if !linkedHeaders {
                try await fileSystem.makeDirectory(at: headersPath)
                linkedHeaders = true
            }
            try await linkStaticLibraryArtifactBundleHeader(
                from: sourceModuleMapPath,
                to: headersPath.appending(component: sourceModuleMapPath.basename)
            )
        }

        return linkedHeaders ? try RelativePath(validating: "Headers") : nil
    }

    private func linkStaticLibraryArtifactBundleHeader(
        from sourcePath: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws {
        guard try await !fileSystem.exists(destinationPath) else { return }
        try await fileSystem.createSymbolicLink(from: destinationPath, to: sourcePath)
    }

    private func uniqueXCFrameworkLibraryIdentifier(
        preferredIdentifier: String,
        usedIdentifiers: inout Set<String>
    ) -> String {
        var identifier = preferredIdentifier
        var suffix = 1
        while usedIdentifiers.contains(identifier) {
            suffix += 1
            identifier = "\(preferredIdentifier)-\(suffix)"
        }
        usedIdentifiers.insert(identifier)
        return identifier
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

private struct StaticLibraryArtifactBundleInfo: Decodable {
    let artifacts: [String: Artifact]

    struct Artifact: Decodable {
        let type: String
        let variants: [Variant]

        struct Variant: Decodable {
            let path: String
            let supportedTriples: [String]
            let staticLibraryMetadata: StaticLibraryMetadata?

            struct StaticLibraryMetadata: Decodable {
                let headerPaths: [String]
                let moduleMapPath: String?

                private enum CodingKeys: String, CodingKey {
                    case headerPaths
                    case moduleMapPath
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    headerPaths = try container.decodeIfPresent([String].self, forKey: .headerPaths) ?? []
                    moduleMapPath = try container.decodeIfPresent(String.self, forKey: .moduleMapPath)
                }
            }
        }
    }
}

private struct StaticLibraryArtifactBundleSlice: Hashable, Comparable {
    let platform: XCFrameworkInfoPlist.Library.Platform
    let platformVariant: XCFrameworkInfoPlist.Library.PlatformVariant?
    let architecture: BinaryArchitecture

    var identifier: StaticLibraryArtifactBundleSliceIdentifier {
        StaticLibraryArtifactBundleSliceIdentifier(platform: platform, platformVariant: platformVariant)
    }

    init?(supportedTriple: String) {
        let components = supportedTriple.split(separator: "-").map(String.init)
        guard let architectureName = components.first,
              let architecture = BinaryArchitecture(rawValue: architectureName)
        else {
            return nil
        }

        let lowercasedTriple = supportedTriple.lowercased()
        let platform: XCFrameworkInfoPlist.Library.Platform
        let platformVariant: XCFrameworkInfoPlist.Library.PlatformVariant?

        if lowercasedTriple.contains("-apple-ios-macabi") {
            platform = .iOS
            platformVariant = .maccatalyst
        } else if lowercasedTriple.contains("-apple-ios-simulator") {
            platform = .iOS
            platformVariant = .simulator
        } else if lowercasedTriple.contains("-apple-ios") {
            platform = .iOS
            platformVariant = nil
        } else if lowercasedTriple.contains("-apple-macos") {
            platform = .macOS
            platformVariant = nil
        } else if lowercasedTriple.contains("-apple-tvos-simulator") {
            platform = .tvOS
            platformVariant = .simulator
        } else if lowercasedTriple.contains("-apple-tvos") {
            platform = .tvOS
            platformVariant = nil
        } else if lowercasedTriple.contains("-apple-watchos-simulator") {
            platform = .watchOS
            platformVariant = .simulator
        } else if lowercasedTriple.contains("-apple-watchos") {
            platform = .watchOS
            platformVariant = nil
        } else if lowercasedTriple.contains("-apple-xros-simulator") {
            platform = .visionOS
            platformVariant = .simulator
        } else if lowercasedTriple.contains("-apple-xros") {
            platform = .visionOS
            platformVariant = nil
        } else {
            return nil
        }

        self.platform = platform
        self.platformVariant = platformVariant
        self.architecture = architecture
    }

    static func < (lhs: StaticLibraryArtifactBundleSlice, rhs: StaticLibraryArtifactBundleSlice) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    private var sortKey: String {
        "\(platform.rawValue)-\(platformVariant?.rawValue ?? "")-\(architecture.rawValue)"
    }
}

private struct StaticLibraryArtifactBundleSliceIdentifier: Hashable, Comparable {
    let platform: XCFrameworkInfoPlist.Library.Platform
    let platformVariant: XCFrameworkInfoPlist.Library.PlatformVariant?

    static func < (lhs: StaticLibraryArtifactBundleSliceIdentifier, rhs: StaticLibraryArtifactBundleSliceIdentifier) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    private var sortKey: String {
        "\(platform.rawValue)-\(platformVariant?.rawValue ?? "")"
    }
}

extension ProjectDescription.DeploymentTargets {
    /// The oldest version of each platform that packages can be generated for.
    ///
    /// The versions come from the SDKs of the selected Xcode, which is what rejects a deployment target that is too
    /// old at build time. `oldestVersions(for:)` covers the platforms whose SDK can't be read, and every platform
    /// where Xcode is not available.
    static func minimumSupportedVersions() async throws -> ProjectDescription.DeploymentTargets {
        let sdkVersions = await SDKDeploymentTargetsProvider.current.minimumDeploymentTargets()
        if let iOS = sdkVersions.iOS, let macOS = sdkVersions.macOS, let watchOS = sdkVersions.watchOS,
           let tvOS = sdkVersions.tvOS, let visionOS = sdkVersions.visionOS
        {
            return .multiplatform(iOS: iOS, macOS: macOS, watchOS: watchOS, tvOS: tvOS, visionOS: visionOS)
        }

        let swiftVersion = try Version(
            versionString: try await SwiftVersionProvider.current.swiftVersion(),
            usesLenientParsing: true
        )
        let fallback = oldestVersions(for: swiftVersion)
        return .multiplatform(
            iOS: sdkVersions.iOS ?? fallback.iOS,
            macOS: sdkVersions.macOS ?? fallback.macOS,
            watchOS: sdkVersions.watchOS ?? fallback.watchOS,
            tvOS: sdkVersions.tvOS ?? fallback.tvOS,
            visionOS: sdkVersions.visionOS ?? fallback.visionOS
        )
    }

    /// The oldest deployment target that a Mac Catalyst build can use, or `nil` when the SDK can't be read.
    ///
    /// Catalyst targets carry the iOS deployment target, and the Catalyst variant of the macOS SDK stops
    /// supporting versions that the iOS SDK still builds for.
    static func minimumSupportedMacCatalystVersion() async -> String? {
        await SDKDeploymentTargetsProvider.current.minimumDeploymentTargets().macCatalyst
    }

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
        } else if swiftVersion < Version(6, 0, 0) {
            return .multiplatform(
                iOS: "12.0",
                macOS: "10.13",
                watchOS: "4.0",
                tvOS: "12.0",
                visionOS: "1.0"
            )
        } else if swiftVersion < Version(6, 2, 0) {
            return .multiplatform(
                iOS: "15.0",
                macOS: "10.13",
                watchOS: "7.0",
                tvOS: "15.0",
                visionOS: "1.0"
            )
        } else if swiftVersion < Version(6, 4, 0) {
            return .multiplatform(
                iOS: "15.0",
                macOS: "11.0",
                watchOS: "8.0",
                tvOS: "15.0",
                visionOS: "1.0"
            )
        } else {
            return .multiplatform(
                iOS: "15.0",
                macOS: "12.0",
                watchOS: "9.0",
                tvOS: "15.0",
                visionOS: "1.0"
            )
        }
    }

    fileprivate static func from(
        minDeploymentTargets: ProjectDescription.DeploymentTargets,
        minMacCatalystDeploymentTarget: String?,
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
            var minimum = minDeploymentTargets[platform]
            if platform == .iOS, destinations.contains(.macCatalyst) {
                minimum = try max(minimum, minMacCatalystDeploymentTarget)
            }
            return try max(minimum, platformInfos[platform])
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
        productTypes: [String: XcodeGraph.Product],
        baseProductType: XcodeGraph.Product
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
        for product in products {
            if let productType = productTypes[product.name] {
                return ProjectDescription.Product.from(product: productType)
            }
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
            // contains automatic product, default to base product type (usually static framework)
            return ProjectDescription.Product.from(product: baseProductType)
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
                if try await !fileSystem.exists(resourceAbsolutePath, isDirectory: true) || resourceAbsolutePath
                    .isOpaqueDirectory
                {
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
        "nib",
        "storyboard",
        "xcdatamodeld",
        "xcmappingmodel",
        "xcassets",
        "strings",
        "stringsdict",
    ])

    private static func defaultResourcePaths(
        from path: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> [AbsolutePath] {
        let extensions = defaultSpmResourceFileExtensions.joined(separator: ",")
        return try await fileSystem.glob(directory: path, include: ["**/*.{\(extensions)}"])
            .collect()
    }
}

extension ProjectDescription.TargetDependency {
    fileprivate func withCondition(_ condition: ProjectDescription.PlatformCondition?) -> Self {
        switch self {
        case let .target(name, status, _):
            return .target(name: name, status: status, condition: condition)
        case .macro, .xctest:
            return self
        case let .project(target, path, status, _):
            return .project(target: target, path: path, status: status, condition: condition)
        case let .framework(path, status, _):
            return .framework(path: path, status: status, condition: condition)
        case let .library(path, publicHeaders, swiftModuleMap, _):
            return .library(path: path, publicHeaders: publicHeaders, swiftModuleMap: swiftModuleMap, condition: condition)
        case let .package(product, type, _):
            return .package(product: product, type: type, condition: condition)
        case let .sdk(name, type, status, _):
            return .sdk(name: name, type: type, status: status, condition: condition)
        case let .xcframework(path, expectedSignature, status, _):
            return .xcframework(path: path, expectedSignature: expectedSignature, status: status, condition: condition)
        case let .external(name, _):
            return .external(name: name, condition: condition)
        case let .externalWithStatus(name, status, _):
            return .externalWithStatus(name: name, status: status, condition: condition)
        }
    }

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
                (.linker, .unsafeFlags), (.linker, .disableWarning), (_, .enableExperimentalFeature), (_, .swiftLanguageMode), (
                    .linker,
                    .treatAllWarnings
                ), (
                    .linker,
                    .treatWarning
                ), (
                    .linker,
                    .enableWarning
                ), (
                    _,
                    .defaultIsolation
                ), (
                    _,
                    .strictMemorySafety
                ):
                    return nil
                }
            } catch {
                return nil
            }
        }

        return targetDependencies + linkerDependencies
    }
}

extension ProjectDescription.Settings {
    // swiftlint:disable:next function_body_length
    fileprivate static func from(
        target: PackageInfo.Target,
        productName: String,
        moduleName: String,
        packageName: String,
        swiftToolsVersion: XcodeGraph.Version,
        packageFolder: AbsolutePath,
        settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting],
        moduleMap: ModuleMap?,
        baseSettings: XcodeGraph.Settings,
        targetSettings: XcodeGraph.Settings?,
        dependencyModuleAliases: [String: String],
        packageTraits: [PackageTrait],
        enabledTraits: Set<String>,
        prebuilts: [SwiftPackageManagerPrebuilt],
        prebuiltPlatforms: PrebuiltPlatforms?
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

        // Swift's back-deployment compatibility dylibs (e.g. libswiftCompatibilitySpan) ship only in the
        // toolchain's versioned prebuilt directory, not in the simulator/device runtime. Packages that adopt
        // back-deployed stdlib types (Span, RawSpan, ...) reference them via @rpath, so expose that directory
        // to dyld; otherwise loading the product fails with "Library not loaded: @rpath/libswiftCompatibilitySpan.dylib".
        settingsDictionary.appendArraySetting(
            key: "LD_RUNPATH_SEARCH_PATHS",
            values: try await SwiftBackDeploymentLibrariesProvider.current.runpathSearchPaths(),
            includeInherited: true
        )

        if !enabledTraits.isEmpty {
            var traitConditions: Set<String> = []

            resolveTraits(enabledTraits, packageTraits: packageTraits, into: &traitConditions)

            if !traitConditions.isEmpty {
                settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] =
                    .array(["$(inherited)"] + traitConditions.sorted())
            }
        }

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
            "SnapshottingTests", // https://github.com/EmergeTools/SnapshotPreviews
            "_SwiftSyntaxTestSupport", // https://github.com/swiftlang/swift-syntax
            "SwiftSyntaxMacrosTestSupport", // https://github.com/swiftlang/swift-syntax
        ]

        let resolvedSettings = try mapper.mapSettings()
        settingsDictionary.merge(resolvedSettings) { $1 }

        if moduleName != productName {
            settingsDictionary["PRODUCT_MODULE_NAME"] = .string(moduleName)
        }

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
                    settingsDictionary["OTHER_CFLAGS"] = .array(values + ["-fmodule-name=\(moduleName)"])
                case let .string(value):
                    settingsDictionary["OTHER_CFLAGS"] = .array(
                        value.split(separator: " ").map(String.init) + ["-fmodule-name=\(moduleName)"]
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

        let uniquePrebuilts = Dictionary(grouping: prebuilts, by: \.libraryName)
            .compactMap(\.value.first)
            .sorted { $0.libraryName < $1.libraryName }
        var prebuiltSettings: XcodeGraph.SettingsDictionary = [:]
        for prebuilt in uniquePrebuilts {
            // SwiftPM extracts prebuilts into the scratch directory and records absolute paths. Referencing them
            // through `$(SRCROOT)` keeps the settings, and therefore the binary-cache hashes, independent of where
            // the checkout lives.
            //
            // A macro cached from one checkout is then reused in others and keeps an LC_RPATH to the warming
            // checkout's `lib` directory. That is harmless only while SwiftPM ships MacroSupport as a static
            // library (`libMacroSupport.a`), so dyld never resolves anything through it. Revisit this if
            // MacroSupport becomes dynamic.
            let librarySearchPath = sourceRootRelativePath(prebuilt.librarySearchPath, packageFolder: packageFolder)
            prebuiltSettings.appendArraySetting(
                key: "OTHER_SWIFT_FLAGS",
                values: prebuilt.includeSearchPaths.flatMap {
                    ["-I", sourceRootRelativePath($0, packageFolder: packageFolder).quotedIfContainsSpaces]
                },
                includeInherited: false
            )
            prebuiltSettings.appendArraySetting(
                key: "LIBRARY_SEARCH_PATHS",
                values: [librarySearchPath.quotedIfContainsSpaces],
                includeInherited: false
            )
            prebuiltSettings.appendArraySetting(
                key: "LD_RUNPATH_SEARCH_PATHS",
                values: [librarySearchPath.quotedIfContainsSpaces],
                includeInherited: false
            )
            prebuiltSettings.appendArraySetting(
                key: "OTHER_LDFLAGS",
                values: ["-l\(prebuilt.libraryName)"],
                includeInherited: false
            )
        }
        for (key, value) in prebuiltSettings.sorted(by: { $0.key < $1.key }) {
            guard case let .array(values) = value else { continue }
            switch prebuiltPlatforms {
            case .all, nil:
                settingsDictionary.appendArraySetting(key: key, values: values, includeInherited: true)
            case .macOS:
                // Mac Catalyst also builds with the macOS SDK, so `[sdk=macosx*]` would link the macOS prebuilt into
                // Catalyst builds. Selecting the values through `PLATFORM_NAME` and `IS_MACCATALYST` scopes them to macOS.
                let macOSKey = "TUIST_SWIFTPM_PREBUILTS_\(key)"
                settingsDictionary["\(macOSKey)_macosx_NO"] = .array(values)
                settingsDictionary.appendArraySetting(
                    key: key,
                    values: ["$(\(macOSKey)_$(PLATFORM_NAME)_$(IS_MACCATALYST:default=NO))"],
                    includeInherited: true
                )
            }
        }

        var baseSettingsDictionary = ProjectDescription.SettingsDictionary.from(settingsDictionary: settingsDictionary)

        var propagatedBaseSettings = baseSettings.base
        // The target's own sanitized bundle identifier is authoritative. A package-wide
        // PRODUCT_BUNDLE_IDENTIFIER template such as com.acme.$(PRODUCT_NAME) is applied at
        // the project level, where each target's identifier overrides it. Copying it onto the
        // target would instead override the sanitized identifier, and modules whose names start
        // with an underscore (e.g. _RopeModule) would produce identifiers Xcode rejects.
        propagatedBaseSettings.removeValue(forKey: "PRODUCT_BUNDLE_IDENTIFIER")
        baseSettingsDictionary.merge(
            .from(settingsDictionary: propagatedBaseSettings),
            policy: .inheritFromProject
        )

        if let userDefinedBaseSettings = targetSettings?.base {
            baseSettingsDictionary.merge(
                .from(settingsDictionary: userDefinedBaseSettings),
                policy: .appendArrays
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

        let defaultSettings = targetSettings?.defaultSettings ?? baseSettings.defaultSettings
        result.defaultSettings = .from(defaultSettings: defaultSettings)

        for (index, configuration) in result.configurations.enumerated() {
            result.configurations[index].settings.merge(
                .from(
                    settingsDictionary: try mapper.settingsForBuildConfiguration(configuration.name.rawValue)
                ),
                uniquingKeysWith: { $1 }
            )
        }

        if swiftToolsVersion >= Version(5, 9, 0) {
            result.base.setSwiftPackageName(packageName)
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
        case .watch2AppContainer:
            return .watch2AppContainer
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

    fileprivate mutating func setSwiftPackageName(_ packageName: String) {
        self["SWIFT_PACKAGE_NAME"] = .string(packageName)
    }
}

extension [String: XcodeGraph.SettingValue] {
    fileprivate mutating func appendArraySetting(
        key: String,
        values: [String],
        includeInherited: Bool
    ) {
        guard !values.isEmpty else { return }

        var resolvedValues: [String]
        switch self[key] {
        case let .array(existingValues):
            resolvedValues = existingValues
        case let .string(value):
            resolvedValues = value.split(separator: " ").map(String.init)
        case nil:
            resolvedValues = includeInherited ? ["$(inherited)"] : []
        }

        resolvedValues.append(contentsOf: values)

        self[key] = .array(resolvedValues)
    }
}

private func sourceRootRelativePath(_ path: AbsolutePath, packageFolder: AbsolutePath) -> String {
    "$(SRCROOT)/\(path.relative(to: packageFolder).pathString)"
}

extension SwiftPackageManagerPrebuilt {
    fileprivate var librarySearchPath: AbsolutePath {
        path.appending(component: "lib")
    }

    fileprivate var includeSearchPaths: [AbsolutePath] {
        var result = [
            path.appending(component: "Modules"),
        ]

        if let checkoutPath, let includePath {
            result.append(contentsOf: includePath.map { checkoutPath.appending($0) })
        } else {
            result.append(contentsOf: cModules.map { path.appending(components: "include", $0) })
        }

        return result
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

        if let cLanguageStandard {
            settingsDictionary["GCC_C_LANGUAGE_STANDARD"] = .string(cLanguageStandard)
        }

        if let cxxLanguageStandard {
            settingsDictionary["CLANG_CXX_LANGUAGE_STANDARD"] = .string(cxxLanguageStandard)
        }

        settingsDictionary["SWIFT_VERSION"] = .string(swiftVersion(for: swiftToolsVersion))

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

        let defaultSettings = ProjectDescription.DefaultSettings.from(defaultSettings: baseSettings.defaultSettings)

        if configurations.isEmpty {
            return .settings(base: settingsDictionary, defaultSettings: defaultSettings)
        } else {
            return .settings(base: settingsDictionary, configurations: configurations, defaultSettings: defaultSettings)
        }
    }

    private func swiftVersion(for configuredSwiftVersion: XcodeGraph.Version?) -> String {
        if let swiftLanguageVersions {
            // Take the latest swift version compatible with the configured one
            let maxAllowedSwiftLanguageVersion = swiftLanguageVersions
                .filter {
                    guard let configuredSwiftVersion else {
                        return true
                    }
                    return $0 <= configuredSwiftVersion
                }
                .sorted()
                .last

            if let maxAllowedSwiftLanguageVersion {
                return maxAllowedSwiftLanguageVersion.description
            }
        }

        // When swiftLanguageVersions is not declared, derive from tools-version,
        // matching SPM's behavior in ToolsVersion.swiftLanguageVersion:
        // https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageModel/ToolsVersion.swift
        switch toolsVersion.major {
        case 4:
            return toolsVersion.minor < 2 ? "4" : "4.2"
        case 5:
            return "5"
        default:
            return "6"
        }
    }
}

extension PackageInfo.Target {
    /// The path used as base for all the relative paths of the package (e.g. sources, resources, headers)
    func basePath(packageFolder: AbsolutePath) async throws -> AbsolutePath {
        let fileSystem = FileSystem()

        if let path {
            return packageFolder.appending(try RelativePath(validating: path))
        }

        let predefinedDirectories = type == .test
            ? PackageInfoMapper.predefinedTestDirectories
            : PackageInfoMapper.predefinedSourceDirectories

        for directory in predefinedDirectories {
            for candidate in pathCandidates {
                let standardPath = packageFolder.appending(components: [directory, candidate])
                if try await fileSystem.exists(standardPath) {
                    return standardPath
                }
            }

            let directPath = packageFolder.appending(component: directory)
            if try await hasSourceFiles(in: directPath, fileSystem: fileSystem) {
                return directPath
            }
        }

        throw PackageInfoMapperError.defaultPathNotFound(packageFolder, name, predefinedDirectories)
    }

    /// Check if directory contains source files (for SE-0162 support)
    private func hasSourceFiles(in directory: AbsolutePath, fileSystem: FileSystem) async throws -> Bool {
        guard try await fileSystem.exists(directory) else { return false }

        // SPM recognized source extensions
        // https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageModel/SupportedLanguageExtension.swift
        let sourceExtensions = ["swift", "c", "cpp", "cc", "cxx", "m", "mm"]
        let pattern = "*.{\(sourceExtensions.joined(separator: ","))}"

        let hasFiles = try await fileSystem
            .glob(directory: directory, include: [pattern])
            .first(where: { _ in true }) != nil

        return hasFiles
    }

    private var pathCandidates: [String] {
        var candidates: [String] = []
        let possibleCandidates = [
            name,
            name.replacingOccurrences(of: " ", with: "_"),
        ]

        for candidate in possibleCandidates where !candidates.contains(candidate) {
            candidates.append(candidate)
        }

        return candidates
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

        // If platformNames is empty but the condition exists (e.g., for trait-only conditions),
        // return nil to indicate no platform filtering
        if filters.isEmpty {
            // If the condition has traits but no platform names, this is a valid trait-only condition
            if let traits = condition.traits, !traits.isEmpty {
                return nil
            }
            // Otherwise, there are no supported platforms and this dependency should not be included
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

extension String {
    fileprivate func strippingCComments() -> String {
        let pattern = #"/\*[\s\S]*?\*/|//.*"#
        guard let regularExpression = try? NSRegularExpression(pattern: pattern) else { return self }

        let range = NSRange(startIndex ..< endIndex, in: self)
        return regularExpression.stringByReplacingMatches(in: self, range: range, withTemplate: "")
    }
}

// MARK: - Trait Resolution

private func resolveTraits(
    _ traitNames: some Collection<String>,
    packageTraits: [PackageTrait],
    into traitConditions: inout Set<String>
) {
    for traitName in traitNames {
        guard let trait = packageTraits.first(where: { $0.name == traitName }) else {
            continue
        }
        if traitName != "default" {
            traitConditions.insert(traitName)
        }
        resolveTraits(trait.enabledTraits, packageTraits: packageTraits, into: &traitConditions)
    }
}
