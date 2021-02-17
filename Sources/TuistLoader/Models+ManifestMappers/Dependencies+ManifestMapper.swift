import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Dependencies {
    static func from(manifest: ProjectDescription.Dependencies) throws -> Self {
        let carthageDependencies: TuistGraph.CarthageDependencies? = try {
            guard let carthageDependencies = manifest.carthageDependencies else {
                return nil
            }
            return try TuistGraph.CarthageDependencies.from(manifest: carthageDependencies)
        }()

        return Self(carthageDependencies: carthageDependencies)
    }
}
