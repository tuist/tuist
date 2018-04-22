import Basic
import Foundation
@testable import xcbuddykit

extension Project {
    static func testData(path: AbsolutePath = AbsolutePath("/test/"),
                         name: String = "Project",
                         config: Config? = nil,
                         schemes: [Scheme] = [],
                         settings: Settings? = nil,
                         targets: [Target] = []) -> Project {
        return Project(path: path,
                       name: name,
                       config: config,
                       schemes: schemes,
                       settings: settings,
                       targets: targets)
    }
}
