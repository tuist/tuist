import Foundation
import PathKit
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectGroupsTests: XCTestCase {
    var subject: ProjectGroups!
    var sourceRootPath: AbsolutePath!
    var project: Project!
    var pbxproj: PBXProj!

    override func setUp() {
        super.setUp()

        let path = try! AbsolutePath(validating: "/test/")
        sourceRootPath = try! AbsolutePath(validating: "/test/")
        project = Project(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "Project.xcodeproj"),
            name: "Project",
            organizationName: nil,
            defaultKnownRegions: nil,
            developmentRegion: nil,
            options: .test(),
            settings: .default,
            filesGroup: .group(name: "Project"),
            targets: [
                .test(filesGroup: .group(name: "Target")),
                .test(),
            ],
            packages: [],
            schemes: [],
            ideTemplateMacros: nil,
            additionalFiles: [],
            resourceSynthesizers: [],
            lastUpgradeCheck: nil,
            isExternal: false
        )
        pbxproj = PBXProj()
    }

    override func tearDown() {
        pbxproj = nil
        project = nil
        sourceRootPath = nil
        subject = nil
        super.tearDown()
    }

    func test_generate() {
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        let main = subject.sortedMain
        XCTAssertNil(main.path)
        XCTAssertEqual(main.sourceTree, .group)
        XCTAssertEqual(main.children.count, 4)

        XCTAssertNotNil(main.group(named: "Project"))
        XCTAssertNil(main.group(named: "Project")?.path)
        XCTAssertEqual(main.group(named: "Project")?.sourceTree, .group)

        XCTAssertNotNil(main.group(named: "Target"))
        XCTAssertNil(main.group(named: "Target")?.path)
        XCTAssertEqual(main.group(named: "Target")?.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.frameworks))
        XCTAssertEqual(subject.frameworks.name, "Frameworks")
        XCTAssertNil(subject.frameworks.path)
        XCTAssertEqual(subject.frameworks.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.products))
        XCTAssertEqual(subject.products.name, "Products")
        XCTAssertNil(subject.products.path)
        XCTAssertEqual(subject.products.sourceTree, .group)
    }

    func test_generate_groupsOrder() throws {
        // Given
        let target1 = Target.test(filesGroup: .group(name: "B"))
        let target2 = Target.test(filesGroup: .group(name: "C"))
        let target3 = Target.test(filesGroup: .group(name: "A"))
        let target4 = Target.test(filesGroup: .group(name: "C"))
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
        // swiftformat:disable preferKeyPath
        let paths = subject.sortedMain.children.compactMap { $0.nameOrPath }
        // swiftformat:enable preferKeyPath
        XCTAssertEqual(paths, [
            "P",
            "B",
            "C",
            "A",
            "Frameworks",
            "Products",
        ])
    }

    func test_targetFrameworks() throws {
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        let got = try subject.targetFrameworks(target: "Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.frameworks.children.contains(got))
    }

    func test_projectGroup_unknownProjectGroups() throws {
        // Given
        subject = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.projectGroup(named: "abc"),
            ProjectGroupsError.missingGroup("abc")
        )
    }

    func test_projectGroup_knownProjectGroups() throws {
        // Given
        let target1 = Target.test(filesGroup: .group(name: "A"))
        let target2 = Target.test(filesGroup: .group(name: "B"))
        let target3 = Target.test(filesGroup: .group(name: "B"))
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
        XCTAssertNotNil(try? subject.projectGroup(named: "A"))
        XCTAssertNotNil(try? subject.projectGroup(named: "B"))
        XCTAssertNotNil(try? subject.projectGroup(named: "P"))
    }

    func test_projectGroupsError_description() {
        XCTAssertEqual(ProjectGroupsError.missingGroup("abc").description, "Couldn't find group: abc")
    }

    func test_projectGroupsError_type() {
        XCTAssertEqual(ProjectGroupsError.missingGroup("abc").type, .bug)
    }

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
        XCTAssertEqual(main.usesTabs, textSettings.usesTabs)
        XCTAssertEqual(main.indentWidth, textSettings.indentWidth)
        XCTAssertEqual(main.tabWidth, textSettings.tabWidth)
        XCTAssertEqual(main.wrapsLines, textSettings.wrapsLines)
    }

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
        XCTAssertNil(main.usesTabs)
        XCTAssertNil(main.indentWidth)
        XCTAssertNil(main.tabWidth)
        XCTAssertNil(main.wrapsLines)
    }
}
