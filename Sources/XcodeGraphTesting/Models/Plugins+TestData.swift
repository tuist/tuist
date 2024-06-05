import Foundation
import TSCBasic
@testable import XcodeGraph

extension Plugins {
    public static func test(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin] = [],
        templatePaths: [AbsolutePath] = [],
        resourceSynthesizers: [PluginResourceSynthesizer] = []
    ) -> Plugins {
        Plugins(
            projectDescriptionHelpers: projectDescriptionHelpers,
            templatePaths: templatePaths,
            resourceSynthesizers: resourceSynthesizers
        )
    }
}
