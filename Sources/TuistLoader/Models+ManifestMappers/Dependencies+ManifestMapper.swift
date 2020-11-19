import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Dependencies {
    static func from(manifest: ProjectDescription.Dependencies) throws -> Self {
        let carthageDependencyModels = try manifest.dependencies
            .filter { $0.manager == .carthage }
            .map { try TuistCore.CarthageDependency.from(manifest: $0) }
        
        return Self(carthageDependencies: carthageDependencyModels)
    }
}

extension TuistCore.CarthageDependency {
    static func from(manifest: ProjectDescription.Dependency) throws -> Self {
        let platforms = try manifest.platforms.map { try TuistCore.Platform.from(manifest: $0) }
        let requirement = TuistCore.Requirement.from(manifest: manifest.requirement)
        
        return Self(name: manifest.name, requirement: requirement, platforms: Set(platforms))
    }
}
