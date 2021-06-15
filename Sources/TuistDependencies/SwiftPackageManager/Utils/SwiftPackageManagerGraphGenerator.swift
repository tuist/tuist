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

    /// Error type.
    var type: ErrorType {
        switch self {
        case .unknownByNameDependency, .unknownPlatform:
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

            let dependencies: [ThirdPartyDependency.Target.Dependency] = try target.dependencies.map { dependency in
                switch dependency {
                case let .target(name, condition):
                    return Self.localDependency(name: name, packageInfo: info, artifactsFolder: artifactsFolder, platforms: try condition?.platforms())
                case let .product(name, package, condition):
                    return .thirdPartyTarget(dependency: package, product: name, platforms: try condition?.platforms())
                case let .byName(name, condition):
                    if info.targets.contains(where: { $0.name == name }) {
                        return Self.localDependency(name: name, packageInfo: info, artifactsFolder: artifactsFolder, platforms: try condition?.platforms())
                    } else if let package = productToPackage[name] {
                        return .thirdPartyTarget(dependency: package, product: name, platforms: try condition?.platforms())
                    } else {
                        throw SwiftPackageManagerGraphGeneratorError.unknownByNameDependency(name)
                    }
                }
            }

            return .init(name: target.name, sources: sources, resources: resources, dependencies: dependencies)
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

extension PackageInfo.Target.Dependency.PackageConditionDescription {
    func platforms() throws -> Set<TuistGraph.Platform> {
        return Set(try self.platformNames.map { platformName in
            guard let platform = Platform(rawValue: platformName) else {
                throw SwiftPackageManagerGraphGeneratorError.unknownPlatform(platformName)
            }
            return platform
        })
    }
}
