import Basic
import Foundation
@testable import TuistCore

public extension Project {
    static func test(path: AbsolutePath = AbsolutePath("/Project"),
                     name: String = "Project",
                     fileName: String? = nil,
                     settings: Settings = Settings.test(),
                     filesGroup: ProjectGroup = .group(name: "Project"),
                     targets: [Target] = [Target.test()],
                     packages: [Package] = [],
                     schemes: [Scheme] = [],
                     additionalFiles: [FileElements] = []) -> Project {
        Project(path: path,
                name: name,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }

    static func empty(path: AbsolutePath = AbsolutePath("/test/"),
                      name: String = "Project",
                      settings: Settings = .default,
                      filesGroup: ProjectGroup = .group(name: "Project"),
                      targets: [Target] = [],
                      packages: [Package] = [],
                      schemes: [Scheme] = [],
                      additionalFiles: [FileElements] = []) -> Project {
        Project(path: path,
                name: name,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }
}
