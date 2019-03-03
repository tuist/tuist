import Basic
import Foundation
@testable import TuistKit

extension Project {
    static func test(path: AbsolutePath = AbsolutePath("/test/"),
                     name: String = "Project",
                     settings: Settings? = Settings.test(),
                     projectStructure: ProjectStructure = .default,
                     targets: [Target] = [Target.test()]) -> Project {
        return Project(path: path,
                       name: name,
                       settings: settings,
                       projectStructure: projectStructure,
                       targets: targets)
    }
}
