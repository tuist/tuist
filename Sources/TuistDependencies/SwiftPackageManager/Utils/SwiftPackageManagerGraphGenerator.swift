import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Swift Package Manager Graph Generator Errors

enum SwiftPackageManagerGraphGeneratorError: FatalError, Equatable {
    /// Thrown when `PackageInfo.Target.Dependency.byName` dependency cannot be resolved.
    case unknownByNameDependency(String)

    /// Thrown when `PackageInfo.Platform` name cannot be mapped to a `DeploymentTarget`.
    case unknownPlatform(String)

    /// Thrown when unsupported `PackageInfo.Target.TargetBuildSettingDescription` `Tool`/`SettingName` pair is found.
    case unsupportedSetting(PackageInfo.Target.TargetBuildSettingDescription.Tool, PackageInfo.Target.TargetBuildSettingDescription.SettingName)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .unknownByNameDependency, .unknownPlatform, .unsupportedSetting:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .unknownByNameDependency(name):
            return "The package associated to the \(name) dependency cannot be found."
        case let .unknownPlatform(platform):
            return "The \(platform) is not supported."
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
    func generate(at path: AbsolutePath) throws -> DependenciesGraph
}

public final class SwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    public init(swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController()) {
        self.swiftPackageManagerController = swiftPackageManagerController
    }

    public func generate(at path: AbsolutePath) throws -> DependenciesGraph {
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

        let thirdPartyDependencies: [String: ThirdPartyDependency] = Dictionary(uniqueKeysWithValues: try packageInfos.map { packageInfo in
            let dependency = try Self.mapToThirdPartyDependency(
                name: packageInfo.name,
                folder: packageInfo.folder,
                info: packageInfo.info,
                artifactsFolder: packageInfo.artifactsFolder,
                productToPackage: productToPackage
            )
            return (dependency.name, dependency)
        })

        return DependenciesGraph(thirdPartyDependencies: thirdPartyDependencies)
    }

    // swiftlint:disable:next function_body_length
    private static func mapToThirdPartyDependency(
        name: String,
        folder: AbsolutePath,
        info: PackageInfo,
        artifactsFolder: AbsolutePath,
        productToPackage: [String: String]
    ) throws -> ThirdPartyDependency {
        let products: [ThirdPartyDependency.Product] = info.products.compactMap { product in
            guard let libraryType = product.type.libraryType else { return nil }

            return .init(
                name: product.name,
                targets: product.targets,
                libraryType: libraryType
            )
        }

        let targets: [ThirdPartyDependency.Target] = try info.targets.compactMap { target in
            switch target.type {
            case .regular:
                break
            case .executable, .test, .system, .binary, .plugin:
                logger.debug("Target \(target.name) of type \(target.type) ignored")
                return nil
            }

            let path = folder.appending(RelativePath(target.path ?? "Sources/\(target.name)"))
            let sources: [AbsolutePath]
            if let customSources = target.sources {
                sources = customSources.map { path.appending(RelativePath($0)) }
            } else {
                sources = [path]
            }

            let resources = target.resources.map { path.appending(RelativePath($0.path)) }

            var dependencies: [ThirdPartyDependency.Target.Dependency] = []

            try target.dependencies.forEach { dependency in
                switch dependency {
                case let .target(name, condition):
                    dependencies.append(
                        Self.localDependency(name: name, packageInfo: info, artifactsFolder: artifactsFolder, platforms: try condition?.platforms())
                    )
                case let .product(name, package, condition):
                    dependencies.append(.thirdPartyTarget(dependency: package, product: name, platforms: try condition?.platforms()))
                case let .byName(name, condition):
                    let platforms = try condition?.platforms()
                    if info.targets.contains(where: { $0.name == name }) {
                        dependencies.append(
                            Self.localDependency(name: name, packageInfo: info, artifactsFolder: artifactsFolder, platforms: platforms)
                        )
                    } else if let package = productToPackage[name] {
                        dependencies.append(.thirdPartyTarget(dependency: package, product: name, platforms: platforms))
                    } else {
                        throw SwiftPackageManagerGraphGeneratorError.unknownByNameDependency(name)
                    }
                }
            }

            var cHeaderSearchPaths: [String] = []
            var cxxHeaderSearchPaths: [String] = []
            var cDefines: [String: String] = [:]
            var cxxDefines: [String: String] = [:]
            var swiftDefines: [String: String] = [:]
            var cFlags: [String] = []
            var cxxFlags: [String] = []
            var swiftFlags: [String] = []

            try target.settings.forEach { setting in
                let platforms = try setting.condition?.platforms()
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

                case (.linker, .linkedFramework):
                    dependencies.append(.linkedFramework(name: setting.value[0], platforms: platforms))
                case (.linker, .linkedLibrary):
                    dependencies.append(.linkedLibrary(name: setting.value[0], platforms: platforms))
                case (.c, .linkedFramework), (.c, .linkedLibrary), (.cxx, .linkedFramework), (.cxx, .linkedLibrary),
                     (.swift, .headerSearchPath), (.swift, .linkedFramework), (.swift, .linkedLibrary),
                     (.linker, .headerSearchPath), (.linker, .define), (.linker, .unsafeFlags):
                    throw SwiftPackageManagerGraphGeneratorError.unsupportedSetting(setting.tool, setting.name)
                }
            }

            return .init(
                name: target.name,
                sources: sources,
                resources: resources,
                dependencies: dependencies,
                publicHeadersPath: target.publicHeadersPath,
                cHeaderSearchPaths: cHeaderSearchPaths,
                cxxHeaderSearchPaths: cxxHeaderSearchPaths,
                cDefines: cDefines,
                cxxDefines: cxxDefines,
                swiftDefines: swiftDefines,
                cFlags: cFlags,
                cxxFlags: cxxFlags,
                swiftFlags: swiftFlags
            )
        }

        let minDeploymentTargets = Set(try info.platforms.map { try DeploymentTarget.from(platform: $0) })

        return .sources(
            name: name,
            products: products,
            targets: targets,
            minDeploymentTargets: minDeploymentTargets
        )
    }

    private static func localDependency(
        name: String,
        packageInfo: PackageInfo,
        artifactsFolder: AbsolutePath,
        platforms: Set<TuistGraph.Platform>?
    ) -> ThirdPartyDependency.Target.Dependency {
        if let target = packageInfo.targets.first(where: { $0.name == name }),
            let targetURL = target.url,
            let xcframeworkRemoteURL = URL(string: targetURL)
        {
            let xcframeworkRelativePath = RelativePath("\(xcframeworkRemoteURL.deletingPathExtension().lastPathComponent).xcframework")
            let xcframeworkPath = artifactsFolder.appending(xcframeworkRelativePath)
            return .xcframework(path: xcframeworkPath, platforms: platforms)
        } else {
            return .target(name: name, platforms: platforms)
        }
    }
}

extension DeploymentTarget {
    fileprivate static func from(platform: PackageInfo.Platform) throws -> DeploymentTarget {
        let version = platform.version
        switch platform.platformName {
        case "ios":
            return .iOS(version, .all)
        case "macos":
            return .macOS(version)
        case "tvos":
            return .tvOS(version)
        case "watchos":
            return .watchOS(version)
        default:
            throw SwiftPackageManagerGraphGeneratorError.unknownPlatform(platform.platformName)
        }
    }
}

extension PackageInfo.Product.ProductType {
    fileprivate var libraryType: ThirdPartyDependency.Product.LibraryType? {
        switch self {
        case let .library(libraryType):
            switch libraryType {
            case .static:
                return .static
            case .dynamic:
                return .dynamic
            case .automatic:
                return .automatic
            }
        case .executable, .plugin, .test:
            return nil
        }
    }
}

extension PackageInfo.Target {
    fileprivate var pathOrDefault: String {
        return path ?? "Sources/\(name)"
    }
}

extension PackageInfo.PackageConditionDescription {
    func platforms() throws -> Set<TuistGraph.Platform> {
        return Set(try platformNames.map { platformName in
            guard let platform = Platform(rawValue: platformName) else {
                throw SwiftPackageManagerGraphGeneratorError.unknownPlatform(platformName)
            }
            return platform
        })
    }
}

extension PackageInfo.Target.TargetBuildSettingDescription.Setting {
    public var extractDefine: (name: String, value: String) {
        let define = self.value[0]
        if define.contains("=") {
            let split = define.split(separator: "=", maxSplits: 1)
            return (name: String(split[0]), value: String(split[1]))
        } else {
            return (name: define, value: "1")
        }
    }
}
