import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.SwiftPackageManagerDependencies {
    /// Creates `TuistGraph.SwiftPackageManagerDependencies` instance from `ProjectDescription.SwiftPackageManagerDependencies` instance.
    static func from(
        manifest: ProjectDescription.SwiftPackageManagerDependencies,
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        let packages = try manifest.packages.map { try TuistGraph.Package.from(manifest: $0, generatorPaths: generatorPaths) }
        let productTypes = manifest.productTypes.mapValues { TuistGraph.Product.from(manifest: $0) }
        let deploymentTargets = manifest.deploymentTargets.map { TuistGraph.DeploymentTarget.from(manifest: $0) }

        return .init(packages, productTypes: productTypes, deploymentTargets: Set(deploymentTargets))
    }
}
