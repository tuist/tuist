import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

/// A protocol that defines an interface to generate the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
public protocol SwiftPackageManagerGraphGenerating {
    /// Generates the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
    /// - Parameter path: The path to the directory that contains the `checkouts` directory where `SwiftPackageManager` installed dependencies.
    func generate(at path: AbsolutePath) throws -> DependenciesGraph
}

public final class SwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    public init(swiftPackageManagerController: SwiftPackageManagerControlling) {
        self.swiftPackageManagerController = swiftPackageManagerController
    }

    public func generate(at path: AbsolutePath) throws -> DependenciesGraph {
        let packageFolders = try FileHandler.shared.contentsOfDirectory(path.appending(component: "checkouts"))
        let packageInfos: [String: PackageInfo] = try packageFolders.reduce(into: [:]) { result, packageFolder in
            let manifest = packageFolder.appending(component: "Package.swift")
            let packageInfo = try swiftPackageManagerController.loadPackageInfo(at: manifest)
            result[packageFolder.basename] = packageInfo
        }

        let thirdPartyDependencies = try packageInfos.mapValues { try Self.mapToThirdPartyDependency(packageInfo: $0) }
        return DependenciesGraph(thirdPartyDependencies: thirdPartyDependencies)
    }

    private static func mapToThirdPartyDependency(packageInfo _: PackageInfo) throws -> ThirdPartyDependency {
        // TODO: map `PackageInfo` to actual `ThirdPartyDependency`
        return .xcframework(path: .root, architectures: [])
    }
}
