import Basic
import Foundation
@testable import xpmkit

extension Project {
    static func test(path: AbsolutePath = AbsolutePath("/test/"),
                     name: String = "Project",
                     settings: Settings? = Settings.test(),
                     targets: [Target] = [Target.test()]) -> Project {
        return Project(path: path,
                       name: name,
                       settings: settings,
                       targets: targets)
    }
}
