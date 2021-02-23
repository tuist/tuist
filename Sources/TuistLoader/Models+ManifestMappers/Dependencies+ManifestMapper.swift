import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Dependencies {
    static func from(manifest: ProjectDescription.Dependencies) throws -> Self {
        let carthage: TuistGraph.CarthageDependencies? = try {
            guard let carthage = manifest.carthage else {
                return nil
            }
            return try TuistGraph.CarthageDependencies.from(manifest: carthage)
        }()

        return Self(carthage: carthage)
    }
}
