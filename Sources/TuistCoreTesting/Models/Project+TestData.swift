import Foundation
import TSCBasic
@testable import TuistCore

public extension Project {
    static func test(path: AbsolutePath = AbsolutePath("/Project"),
                     sourceRootPath: AbsolutePath = AbsolutePath("/Project"),
                     name: String = "Project",
                     organizationName: String? = nil,
                     fileName: String? = nil,
                     settings: Settings = Settings.test(),
                     filesGroup: ProjectGroup = .group(name: "Project"),
                     targets: [Target] = [Target.test()],
                     packages: [Package] = [],
                     schemes: [Scheme] = [],
                     additionalFiles: [FileElement] = []) -> Project {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                name: name,
                organizationName: organizationName,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }

    static func empty(path: AbsolutePath = AbsolutePath("/test/"),
                      sourceRootPath: AbsolutePath = AbsolutePath("/test/"),
                      name: String = "Project",
                      organizationName: String? = nil,
                      fileName: String? = nil,
                      settings: Settings = .default,
                      filesGroup: ProjectGroup = .group(name: "Project"),
                      targets: [Target] = [],
                      packages: [Package] = [],
                      schemes: [Scheme] = [],
                      additionalFiles: [FileElement] = []) -> Project {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                name: name,
                organizationName: organizationName,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }
}
