import Foundation
import ProjectDescription
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

        return try packageInfos.reduce(DependenciesGraph.none) { result, packageInfo in
            try Self.writeProject(
                for: packageInfo.info,
                name: packageInfo.name,
                at: packageInfo.folder,
                productToPackage: productToPackage
            )
            let packageDependenciesGraph = DependenciesGraph(
                externalDependencies: packageInfo.info.products.reduce(into: [:]) { result, product in
                    result[product.name] = product.targets.map { .project(target: $0, path: packageInfo.folder) }
                }
            )
            return try result.merging(with: packageDependenciesGraph)
        }
    }

    private static func writeProject(
        for packageInfo: PackageInfo,
        name: String,
        at folder: AbsolutePath,
        productToPackage: [String: String]
    ) throws {
        let targets = try packageInfo.targets.compactMap { target in
            try Self.targetDefinition(for: target, packageName: name, packageInfo: packageInfo, at: folder, productToPackage: productToPackage)
        }
        let project = ProjectDescription.Project(
            name: name,
            targets: targets,
            resourceSynthesizers: []
        )
        let projectData = String(data: try JSONEncoder().encode(project), encoding: .utf8)!
        try FileHandler.shared.write(projectData, path: folder.appending(component: "Project.json"), atomically: true)
    }

    private static func targetDefinition(
        for target: PackageInfo.Target,
        packageName: String,
        packageInfo: PackageInfo,
        at folder: AbsolutePath,
        productToPackage: [String: String]
    ) throws -> ProjectDescription.Target? {
        guard target.type == .regular else {
            logger.debug("Target \(target.name) of type \(target.type) ignored")
            return nil
        }

        guard let product = target.mapProduct(packageInfo: packageInfo) else {
            logger.debug("Target \(target.name) ignored by product type")
            return nil
        }

        let path = folder.appending(RelativePath(target.path ?? "Sources/\(target.name)"))

        return .init(
            name: target.name,
            platform: target.mapPlatform(),
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
    func mapPlatform() -> ProjectDescription.Platform {
        // TODO: Should this be configured in `Dependencies.swift`?
        return .iOS
    }

    func mapProduct(packageInfo: PackageInfo) -> ProjectDescription.Product? {
        return packageInfo.products
            .filter { $0.targets.contains(self.name) }
            .compactMap {
                switch $0.type {
                case let .library(type):
                    switch type {
                    case .automatic:
                        return .staticLibrary
                    case .dynamic:
                        return .dynamicLibrary
                    case .static:
                        return .staticLibrary
                    }
                case .executable, .plugin, .test:
                    return nil
                }
            }
            .first
    }

    func mapSources(path: AbsolutePath) -> SourceFilesList? {
        let sourcesPaths: [AbsolutePath]
        if let customSources = self.sources {
            sourcesPaths = customSources.map { path.appending(RelativePath($0)) }
        } else {
            sourcesPaths = [path]
        }
        guard !sourcesPaths.isEmpty else { return nil }
        return .init(globs: sourcesPaths.map(\.pathString))
    }

    func mapResources(path: AbsolutePath) -> ResourceFileElements? {
        let resourcesPaths = self.resources.map { path.appending(RelativePath($0.path)) }
        guard !resourcesPaths.isEmpty else { return nil }
        return .init(resources: resourcesPaths.map { .glob(pattern: .init($0.pathString)) })
    }

    func mapDependencies(
        packageName: String,
        packageInfo: PackageInfo,
        productToPackage: [String: String]
    ) throws -> [ProjectDescription.TargetDependency] {
        let targetDependencies: [ProjectDescription.TargetDependency] = try self.dependencies.map { dependency in
            switch dependency {
            case let .target(name, _):
                return .target(name: name)
            case let .product(name, package, _):
                return .project(target: name, path: .init(RelativePath("../\(package)").pathString))
            case let .byName(name, _):
                guard let package = productToPackage[name] else {
                    throw SwiftPackageManagerGraphGeneratorError.unknownByNameDependency(name)
                }

                if package == packageName {
                    return .target(name: name)
                } else {
                    return .project(target: name, path: .init(RelativePath("../\(package)").pathString))
                }
            }
        }

        let linkerDependencies: [ProjectDescription.TargetDependency] = self.settings.compactMap { setting in
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

        try self.settings.forEach { setting in
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
