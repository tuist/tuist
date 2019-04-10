import Basic
import Foundation
@testable import TuistGenerator

extension Project {
    static func test(path: AbsolutePath = AbsolutePath("/test/"),
                     name: String = "Project",
                     settings: Settings? = Settings.test(),
                     filesGroup: ProjectGroup = .group(name: "Project"),
                     targets: [Target] = [Target.test()],
                     additionalFiles: [FileElement] = []) -> Project {
        return Project(path: path,
                       name: name,
                       settings: settings,
                       filesGroup: filesGroup,
                       targets: targets,
                       additionalFiles: additionalFiles)
    }

    static func empty(path: AbsolutePath = AbsolutePath("/test/"),
                      name: String = "Project",
                      settings: Settings? = nil,
                      filesGroup: ProjectGroup = .group(name: "Project"),
                      targets: [Target] = [],
                      additionalFiles: [FileElement] = []) -> Project {
        return Project(path: path,
                       name: name,
                       settings: settings,
                       filesGroup: filesGroup,
                       targets: targets,
                       additionalFiles: additionalFiles)
    }
}
