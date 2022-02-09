import Foundation
import TSCBasic
import TSCUtility
@testable import TuistGraph

extension Project {
    public static func test(
        path: AbsolutePath = AbsolutePath("/Project"),
        sourceRootPath: AbsolutePath = AbsolutePath("/Project"),
        xcodeProjPath: AbsolutePath = AbsolutePath("/Project/Project.xcodeproj"),
        name: String = "Project",
        organizationName: String? = nil,
        developmentRegion: String? = nil,
        options: Options = .init(
            automaticSchemesOptions: .disabled,
            disableBundleAccessors: false,
            disableSynthesizedResourceAccessors: false,
            textSettings: .init(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
        ),
        settings: Settings = Settings.test(),
        filesGroup: ProjectGroup = .group(name: "Project"),
        targets: [Target] = [Target.test()],
        packages: [Package] = [],
        schemes: [Scheme] = [],
        ideTemplateMacros: IDETemplateMacros? = nil,
        additionalFiles: [FileElement] = [],
        resourceSynthesizers: [ResourceSynthesizer] = [],
        lastUpgradeCheck: Version? = nil
    ) -> Project {
        Project(
            path: path,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: name,
            organizationName: organizationName,
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
            lastUpgradeCheck: lastUpgradeCheck
        )
    }

    public static func empty(
        path: AbsolutePath = AbsolutePath("/test/"),
        sourceRootPath: AbsolutePath = AbsolutePath("/test/"),
        xcodeProjPath: AbsolutePath = AbsolutePath("/test/text.xcodeproj"),
        name: String = "Project",
        organizationName: String? = nil,
        developmentRegion: String? = nil,
        options: Options = .init(
            automaticSchemesOptions: .disabled,
            disableBundleAccessors: false,
            disableSynthesizedResourceAccessors: false,
            textSettings: .init(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
        ),
        settings: Settings = .default,
        filesGroup: ProjectGroup = .group(name: "Project"),
        targets: [Target] = [],
        packages: [Package] = [],
        schemes: [Scheme] = [],
        ideTemplateMacros: IDETemplateMacros? = nil,
        additionalFiles: [FileElement] = [],
        resourceSynthesizers: [ResourceSynthesizer] = [],
        lastUpgradeCheck: Version? = nil
    ) -> Project {
        Project(
            path: path,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: name,
            organizationName: organizationName,
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
            lastUpgradeCheck: lastUpgradeCheck
        )
    }
}
