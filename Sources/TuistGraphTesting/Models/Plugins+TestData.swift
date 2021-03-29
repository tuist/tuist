import Foundation
import TSCBasic
@testable import TuistGraph

public extension Plugins {
    static func test(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin] = [],
        templatePaths: [AbsolutePath] = [],
        resourceTemplates: [AbsolutePath] = []
    ) -> Plugins {
        Plugins(
            projectDescriptionHelpers: projectDescriptionHelpers,
            templatePaths: templatePaths,
            resourceSynthesizers: []
        )
    }
}
