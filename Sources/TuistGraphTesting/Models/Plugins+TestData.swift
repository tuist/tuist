import Foundation
import TSCBasic
@testable import TuistGraph

extension Plugins {
    public static func test(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin] = [],
        templatePaths: [AbsolutePath] = [],
        resourceSynthesizers: [PluginResourceSynthesizer] = [],
        tasks: [PluginTasks] = []
    ) -> Plugins {
        Plugins(
            projectDescriptionHelpers: projectDescriptionHelpers,
            templatePaths: templatePaths,
            resourceSynthesizers: resourceSynthesizers,
            tasks: tasks
        )
    }
}
