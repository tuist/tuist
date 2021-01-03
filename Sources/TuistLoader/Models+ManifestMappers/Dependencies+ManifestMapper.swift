import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Dependencies {
    static func from(manifest: ProjectDescription.Dependencies) throws -> Self {
        let carthageDependencies = try manifest.dependencies.reduce(into: [CarthageDependency]()) { result, dependency in
            switch dependency {
            case let .carthage(origin, requirement, platforms):
                let origin = try TuistGraph.CarthageDependency.Origin.from(manifest: origin)
                let requirement = try TuistGraph.CarthageDependency.Requirement.from(manifest: requirement)
                let platforms = try platforms.map { try TuistGraph.Platform.from(manifest: $0) }
                result.append(CarthageDependency(origin: origin, requirement: requirement, platforms: Set(platforms)))
            case .spm:
                #warning("IMPLEMENT ME")
            }
        }

        return Self(carthageDependencies: carthageDependencies)
    }
}
