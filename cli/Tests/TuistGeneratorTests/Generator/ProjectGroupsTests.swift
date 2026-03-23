import Foundation
import Path
import PathKit
import TuistCore
import XcodeGraph
import XcodeProj
import Testing
@testable import TuistGenerator
@testable import TuistTesting

struct ProjectGroupsTests {
    var subject: ProjectGroups
    let sourceRootPath: AbsolutePath
    let project: Project
    let pbxproj: PBXProj
    init() {
        let path = try! AbsolutePath(validating: "/test/")
        sourceRootPath = try! AbsolutePath(validating: "/test/")
        project = Project(
        path: path,
        sourceRootPath: path,
        xcodeProjPath: path.appending(component: "Project.xcodeproj"),
        name: "Project",
        organizationName: nil,
        classPrefix: nil,
        defaultKnownRegions: nil,
        developmentRegion: nil,
        options: .test(),
        settings: .default,
        filesGroup: .group(name: "Project"),
        targets: [
        .test(name: "A", filesGroup: .group(name: "Target")),
        .test(name: "B"),
        ],
        packages: [],
        schemes: [],
        ideTemplateMacros: nil,
        additionalFiles: [],
        resourceSynthesizers: [],
        lastUpgradeCheck: nil,
        type: .local
        )
        pbxproj = PBXProj()
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )
    }

    @Test
    mutating func test_generate() {
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        let main = subject.sortedMain
        #expect(main.path == nil)
        #expect(main.sourceTree == .group)
        #expect(main.children.count == 5)

        #expect(main.group(named: "Project") != nil)
        #expect(main.group(named: "Project")?.path == nil)
        #expect(main.group(named: "Project")?.sourceTree == .group)

        #expect(main.group(named: "Target") != nil)
        #expect(main.group(named: "Target")?.path == nil)
        #expect(main.group(named: "Target")?.sourceTree == .group)

        #expect(main.children.contains(subject.frameworks))
        #expect(subject.frameworks.name == "Frameworks")
        #expect(subject.frameworks.path == nil)
        #expect(subject.frameworks.sourceTree == .group)

        #expect(main.children.contains(subject.cachedFrameworks))
        #expect(subject.cachedFrameworks.name == "Cache")
        #expect(subject.cachedFrameworks.path == nil)
        #expect(subject.cachedFrameworks.sourceTree == .group)

        #expect(main.children.contains(subject.products))
        #expect(subject.products.name == "Products")
        #expect(subject.products.path == nil)
        #expect(subject.products.sourceTree == .group)
    }

    @Test
    mutating func test_generate_groupsOrder() throws {
        // Given
        let target1 = Target.test(name: "Target1", filesGroup: .group(name: "B"))
        let target2 = Target.test(name: "Target2", filesGroup: .group(name: "C"))
        let target3 = Target.test(name: "Target3", filesGroup: .group(name: "A"))
        let target4 = Target.test(name: "Target4", filesGroup: .group(name: "C"))
        let project = Project.test(
            filesGroup: .group(name: "P"),
            targets: [target1, target2, target3, target4]
        )

        // When
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        // Then
        let paths = subject.sortedMain.children.map(\.nameOrPath).sorted()
        #expect(paths == [
            "A",
            "B",
            "C",
            "Cache",
            "Frameworks",
            "P",
            "Products",
        ])
    }

    @Test
    mutating func test_removeEmptyAuxiliaryGroups_removesEmptyGroups() throws {
        // Given
        let project = Project.test()
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        // When
        subject.removeEmptyAuxiliaryGroups()

        // Then
        let paths = subject.sortedMain.children.map(\.nameOrPath)
        #expect(paths == [
            "Products",
            "Project",
        ])
    }

    @Test
    mutating func test_removeEmptyAuxiliaryGroups_preservesNonEmptyGroups() throws {
        // Given
        let project = Project.test()
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        addFile(to: subject.frameworks)
        addFile(to: subject.cachedFrameworks)

        // When
        subject.removeEmptyAuxiliaryGroups()

        // Then
        let paths = subject.sortedMain.children.map(\.nameOrPath)
        #expect(paths == [
            "Products",
            "Project",
            "Frameworks",
            "Cache",
        ])
    }

    @Test
    mutating func test_targetFrameworks() throws {
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        let got = try subject.targetFrameworks(target: "Test")
        #expect(got.name == "Test")
        #expect(got.sourceTree == .group)
        #expect(subject.frameworks.children.contains(got))
    }

    @Test
    mutating func test_projectGroup_unknownProjectGroups() throws {
        // Given
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        // When / Then
        #expect(throws: ProjectGroupsError.missingGroup("abc")) {
            try subject.projectGroup(named: "abc")
        }
    }

    @Test
    mutating func test_projectGroup_knownProjectGroups() throws {
        // Given
        let target1 = Target.test(name: "1", filesGroup: .group(name: "A"))
        let target2 = Target.test(name: "2", filesGroup: .group(name: "B"))
        let target3 = Target.test(name: "3", filesGroup: .group(name: "B"))
        let project = Project.test(
            path: .root,
            sourceRootPath: .root,
            xcodeProjPath: AbsolutePath.root.appending(component: "Project.xcodeproj"),
            filesGroup: .group(name: "P"),
            targets: [target1, target2, target3]
        )

        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        // When / Then
        #expect(try subject.projectGroup(named: "A") != nil)
        #expect(try subject.projectGroup(named: "B") != nil)
        #expect(try subject.projectGroup(named: "P") != nil)
    }

    @Test
    func test_projectGroupsError_description() {
        #expect(ProjectGroupsError.missingGroup("abc").description == "Couldn't find group: abc")
    }

    @Test
    func test_projectGroupsError_type() {
        #expect(ProjectGroupsError.missingGroup("abc").type == .bug)
    }

    @Test
    func test_generate_with_text_settings() {
        // Given
        let textSettings = Project.Options.TextSettings.test()
        let project = Project.test(options: .test(textSettings: textSettings))

        // When
        let main = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        ).sortedMain

        // Then
        #expect(main.usesTabs == textSettings.usesTabs)
        #expect(main.indentWidth == textSettings.indentWidth)
        #expect(main.tabWidth == textSettings.tabWidth)
        #expect(main.wrapsLines == textSettings.wrapsLines)
    }

    @Test
    func test_generate_without_text_settings() {
        // Given
        let textSettings = Project.Options.TextSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
        let project = Project.test(options: .test(textSettings: textSettings))

        // When
        let main = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        ).sortedMain

        // Then
        #expect(main.usesTabs == nil)
        #expect(main.indentWidth == nil)
        #expect(main.tabWidth == nil)
        #expect(main.wrapsLines == nil)
    }

    // MARK: - Helpers

    private func addFile(to group: PBXGroup) {
        let file = PBXFileReference()
        pbxproj.add(object: file)
        group.children.append(file)
    }
}
