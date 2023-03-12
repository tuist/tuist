import Foundation
import TSCBasic
import TSCUtility
@testable import TuistGraph

extension Project {
    public static func test(
        path: AbsolutePath = try! AbsolutePath(validating: "/Project"), // swiftlint:disable:this force_try
        sourceRootPath: AbsolutePath = try! AbsolutePath(validating: "/Project"), // swiftlint:disable:this force_try
        // swiftlint:disable:next force_try
        xcodeProjPath: AbsolutePath = try! AbsolutePath(validating: "/Project/Project.xcodeproj"),
        name: String = "Project",
        organizationName: String? = nil,
        defaultKnownRegions: [String]? = nil,
        developmentRegion: String? = nil,
        options: Options = .test(automaticSchemesOptions: .disabled),
        settings: Settings = Settings.test(),
        filesGroup: ProjectGroup = .group(name: "Project"),
        targets: [Target] = [Target.test()],
        packages: [Package] = [],
        schemes: [Scheme] = [],
        ideTemplateMacros: IDETemplateMacros? = nil,
        additionalFiles: [FileElement] = [],
        resourceSynthesizers: [ResourceSynthesizer] = [],
        lastUpgradeCheck: Version? = nil,
        isExternal: Bool = false
    ) -> Project {
        Project(
            path: path,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: name,
            organizationName: organizationName,
            defaultKnownRegions: defaultKnownRegions,
            developmentRegion: developmentRegion,
            options: options,
            settings: settings,
            filesGroup: filesGroup,
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            resourceSynthesizers: resourceSynthesizers,
            lastUpgradeCheck: lastUpgradeCheck,
            isExternal: isExternal
        )
    }

    public static func empty(
        path: AbsolutePath = try! AbsolutePath(validating: "/test/"), // swiftlint:disable:this force_try
        sourceRootPath: AbsolutePath = try! AbsolutePath(validating: "/test/"), // swiftlint:disable:this force_try
        xcodeProjPath: AbsolutePath = try! AbsolutePath(validating: "/test/text.xcodeproj"), // swiftlint:disable:this force_try
        name: String = "Project",
        organizationName: String? = nil,
        defaultKnownRegions: [String]? = nil,
        developmentRegion: String? = nil,
        options: Options = .test(automaticSchemesOptions: .disabled),
        settings: Settings = .default,
        filesGroup: ProjectGroup = .group(name: "Project"),
        targets: [Target] = [],
        packages: [Package] = [],
        schemes: [Scheme] = [],
        ideTemplateMacros: IDETemplateMacros? = nil,
        additionalFiles: [FileElement] = [],
        resourceSynthesizers: [ResourceSynthesizer] = [],
        lastUpgradeCheck: Version? = nil,
        isExternal: Bool = false
    ) -> Project {
        Project(
            path: path,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: name,
            organizationName: organizationName,
            defaultKnownRegions: defaultKnownRegions,
            developmentRegion: developmentRegion,
            options: options,
            settings: settings,
            filesGroup: filesGroup,
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            resourceSynthesizers: resourceSynthesizers,
            lastUpgradeCheck: lastUpgradeCheck,
            isExternal: isExternal
        )
    }
}
