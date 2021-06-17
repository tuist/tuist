import Foundation
import TSCBasic
@testable import TuistGraph

public extension Plugins {
    static func test(
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
