import Basic
import Foundation
@testable import xcbuddykit

extension Project {
    static func testData(path: AbsolutePath = AbsolutePath("/test/"),
                         name: String = "Project",
                         schemes: [Scheme] = [],
                         targets: [Target] = [],
                         settings: Settings? = nil,
                         config: Config? = nil) -> Project {
        return Project(path: path,
                       name: name,
                       schemes: schemes,
                       targets: targets,
                       settings: settings,
                       config: config)
    }
}
