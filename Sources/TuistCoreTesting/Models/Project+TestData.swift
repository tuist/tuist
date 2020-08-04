import Foundation
import TSCBasic
@testable import TuistCore

public extension Project {
    static func test(path: AbsolutePath = AbsolutePath("/Project"),
                     sourceRootPath: AbsolutePath = AbsolutePath("/Project"),
                     xcodeProjPath: AbsolutePath = AbsolutePath("/Project/Project.xcodeproj"),
                     name: String = "Project",
                     organizationName: String? = nil,
                     settings: Settings = Settings.test(),
                     filesGroup: ProjectGroup = .group(name: "Project"),
                     targets: [Target] = [Target.test()],
                     packages: [Package] = [],
                     schemes: [Scheme] = [],
                     additionalFiles: [FileElement] = []) -> Project
    {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                xcodeProjPath: xcodeProjPath,
                name: name,
                organizationName: organizationName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }

    static func empty(path: AbsolutePath = AbsolutePath("/test/"),
                      sourceRootPath: AbsolutePath = AbsolutePath("/test/"),
                      xcodeProjPath: AbsolutePath = AbsolutePath("/test/text.xcodeproj"),
                      name: String = "Project",
                      organizationName: String? = nil,
                      settings: Settings = .default,
                      filesGroup: ProjectGroup = .group(name: "Project"),
                      targets: [Target] = [],
                      packages: [Package] = [],
                      schemes: [Scheme] = [],
                      additionalFiles: [FileElement] = []) -> Project
    {
        Project(path: path,
                sourceRootPath: sourceRootPath,
                xcodeProjPath: xcodeProjPath,
                name: name,
                organizationName: organizationName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }
}
