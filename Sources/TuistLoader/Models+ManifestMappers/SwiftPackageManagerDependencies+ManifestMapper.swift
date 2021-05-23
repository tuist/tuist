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
        let options = manifest.options.map { TuistGraph.SwiftPackageManagerDependencies.Options.from(manifest: $0) }

        return .init(packages, options: Set(options))
    }
}

extension TuistGraph.SwiftPackageManagerDependencies.Options {
    /// Creates `TuistGraph.SwiftPackageManagerDependencies.Options` instance from `ProjectDescription.SwiftPackageManagerDependencies.Options` instance.
    static func from(manifest: ProjectDescription.SwiftPackageManagerDependencies.Options) -> Self {
        switch manifest {
        case let .swiftToolsVersion(version):
            return .swiftToolsVersion(version.description)
        }
    }
}
