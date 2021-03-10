import Foundation
import TSCBasic
@testable import TuistGraph

public extension Plugins {
    static func test(
        projectDescriptionHelpers: [ProjectDescriptionHelpersPlugin] = []
    ) -> Plugins {
        Plugins(projectDescriptionHelpers: projectDescriptionHelpers)
    }
}
