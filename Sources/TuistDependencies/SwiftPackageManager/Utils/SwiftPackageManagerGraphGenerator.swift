import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Swift Package Manager Graph Generator Errors

enum SwiftPackageManagerGraphGeneratorError: FatalError, Equatable {
    /// Thrown when `PackageInfo.Platform` name cannot be mapped to a `DeploymentTarget`.
    case unknownPlatform(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .unknownPlatform:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .unknownPlatform(platform):
            return "The \(platform) is not supported."
        }
    }
}

// MARK: - Swift Package Manager Graph Generator Errors

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
        let packageInfos: [AbsolutePath: PackageInfo] = try packageFolders.reduce(into: [:]) { result, packageFolder in
            let manifest = packageFolder.appending(component: "Package.swift")
            let packageInfo = try swiftPackageManagerController.loadPackageInfo(at: manifest)
            result[packageFolder] = packageInfo
        }

        let thirdPartyDependencies: [String: ThirdPartyDependency] = Dictionary(uniqueKeysWithValues: try packageInfos.map { packageFolder, packageInfo in
            let dependency = try Self.mapToThirdPartyDependency(packageFolder: packageFolder, packageInfo: packageInfo)
            return (dependency.name, dependency)
        })

        return DependenciesGraph(thirdPartyDependencies: thirdPartyDependencies)
    }

    private static func mapToThirdPartyDependency(packageFolder: AbsolutePath, packageInfo: PackageInfo) throws -> ThirdPartyDependency {
        let name = packageFolder.basename

        let products: [ThirdPartyDependency.Product] = packageInfo.products.compactMap { product in
            guard let libraryType = product.type.libraryType else {
                return nil
            }

            return .init(
                name: product.name,
                targets: product.targets,
                libraryType: libraryType
            )
        }

        let targets: [ThirdPartyDependency.Target] = packageInfo.targets.compactMap { target in
            switch target.type {
            case .regular:
                break
            case .executable, .test, .system, .binary, .plugin:
                logger.debug("Target \(target.name) of type \(target.type) ignored")
                return nil
            }

            let path = packageFolder.appending(RelativePath(target.path ?? "Sources/\(target.name)"))
            let sources: [AbsolutePath]
            if let customSources = target.sources {
                sources = customSources.map { path.appending(RelativePath($0)) }
            } else {
                sources = [path]
            }

            let resoures = target.resources.map { path.appending(RelativePath($0.path)) }

            return .init(name: target.name, sources: sources, resources: resoures, dependencies: [])
        }

        let minDeploymentTargets = Set(try packageInfo.platforms.map { try DeploymentTarget.from(platform: $0) })

        return .sources(
            name: name,
            products: products,
            targets: targets,
            minDeploymentTargets: minDeploymentTargets
        )
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
