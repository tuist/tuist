import Foundation
import PathKit
@testable import xcbuddykit

extension Project {
    static func testData(path: Path = Path("/test/"),
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
