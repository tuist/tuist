import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Dependencies {
    /// Maps a ProjectDescription.Dependencies instance into a TuistGraph.Dependencies instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of dependencies.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Dependencies, generatorPaths: GeneratorPaths) throws -> Self {
        let dependencies = try manifest.dependencies
            .reduce(into: ([CarthageDependency](), [SwiftPackageManagerDependency]()), { result, manifest in
                switch manifest {
                case let .carthage(origin, requirement, platforms):
                    let origin = try TuistGraph.CarthageDependency.Origin.from(manifest: origin)
                    let requirement = try TuistGraph.CarthageDependency.Requirement.from(manifest: requirement)
                    let platforms = try platforms.map { try TuistGraph.Platform.from(manifest: $0) }

                    result.0.append(CarthageDependency(origin: origin, requirement: requirement, platforms: Set(platforms)))
                case let .swiftPackageManager(package):
                    let package = try TuistGraph.Package.from(manifest: package, generatorPaths: generatorPaths)
                    
                    result.1.append(SwiftPackageManagerDependency(package: package))
                }
            })

        return Self(carthageDependencies: dependencies.0,
                    swiftPackageManagerDependencies: dependencies.1)
    }
}
