import Foundation
import TSCBasic
@testable import TuistGraph

public extension Plugins {
    static func test(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin] = [],
        templatePaths: [AbsolutePath] = [],
        resourceSynthesizers: [ResourceSynthesizerPlugin] = []
    ) -> Plugins {
        Plugins(
            projectDescriptionHelpers: projectDescriptionHelpers,
            templatePaths: templatePaths,
            resourceSynthesizers: resourceSynthesizers
        )
    }
}
