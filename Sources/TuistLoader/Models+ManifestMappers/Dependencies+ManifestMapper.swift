import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Dependencies {
    static func from(manifest: ProjectDescription.Dependencies) throws -> Self {
        let carthageDependencies = try manifest.dependencies.reduce(into: [CarthageDependency]()) { result, dependency in
            switch dependency {
            case let .carthage(origin, requirement, platforms):
                let origin = try TuistCore.CarthageDependency.Origin.from(manifest: origin)
                let requirement = try TuistCore.CarthageDependency.Requirement.from(manifest: requirement)
                let platforms = try platforms.map { try TuistCore.Platform.from(manifest: $0) }
                result.append(CarthageDependency(origin: origin, requirement: requirement, platforms: Set(platforms)))
            }
        }

        return Self(carthageDependencies: carthageDependencies)
    }
}
