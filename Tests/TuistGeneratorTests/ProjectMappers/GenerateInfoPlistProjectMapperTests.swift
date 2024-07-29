import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

public final class GenerateInfoPlistProjectMapperTests: TuistUnitTestCase {
    var infoPlistContentProvider: MockInfoPlistContentProvider!
    var subject: GenerateInfoPlistProjectMapper!

    override public func setUp() {
        super.setUp()
        infoPlistContentProvider = MockInfoPlistContentProvider()
        subject = GenerateInfoPlistProjectMapper(
            infoPlistContentProvider: infoPlistContentProvider,
            derivedDirectoryName: Constants.DerivedDirectory.name,
            infoPlistsDirectoryName: Constants.DerivedDirectory.infoPlists
        )
    }

    override public func tearDown() {
        infoPlistContentProvider = nil
        subject = nil
        super.tearDown()
    }

    func test_map_whenOnlyInfoPlistInTarget() throws {
        // Given
        let targetA = Target.test(name: "A", infoPlist: .dictionary(["A": "A_VALUE"]))
        let targetB = Target.test(name: "B", infoPlist: .dictionary(["B": "B_VALUE"]))
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(sideEffects.count, 2)
        XCTAssertEqual(mappedProject.targets.count, 2)

        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-Info.plist",
            content: ["A": "A_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "B-Info.plist",
            content: ["B": "B_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "A-Info.plist",
            project: mappedProject
        )
        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "B-Info.plist",
            project: mappedProject
        )
    }

    func test_map_whenOnlyInfoPlistInConfigurations() throws {
        // Given
        let targetA = Target.test(
            name: "A",
            settings: Settings(
                configurations: [
                    .debug("CustomDebug"): Configuration(infoPlist: .dictionary(["A": "A1_VALUE"])),
                    .debug: Configuration(infoPlist: .dictionary(["A": "A2_VALUE"])),
                    .release: Configuration(infoPlist: .dictionary(["A": "A3_VALUE"])),
                ]
            )
        )
        let project = Project.test(targets: [targetA])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(sideEffects.count, 3)
        XCTAssertEqual(mappedProject.targets.count, 1)

        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-CustomDebug-Info.plist",
            content: ["A": "A1_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-Debug-Info.plist",
            content: ["A": "A2_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-Release-Info.plist",
            content: ["A": "A3_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        XCTAssertTargetExistsWithoutDerivedInfoPlist(project: mappedProject)
    }

    func test_map_whenInfoPlistInBothTargetAndConfigurations() throws {
        // Given
        let targetA = Target.test(
            name: "A",
            infoPlist: .dictionary(["A": "A_VALUE"]),
            settings: Settings(
                configurations: [
                    .debug("CustomDebug"): Configuration(),
                    .debug("AnotherDebug"): nil,
                    .debug: Configuration(infoPlist: .dictionary(["A": "A2_VALUE"])),
                    .release: Configuration(infoPlist: .dictionary(["A": "A3_VALUE"])),
                ]
            )
        )
        let project = Project.test(targets: [targetA])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(sideEffects.count, 3)
        XCTAssertEqual(mappedProject.targets.count, 1)

        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-Info.plist",
            content: ["A": "A_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-Debug-Info.plist",
            content: ["A": "A2_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "A-Release-Info.plist",
            content: ["A": "A3_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "A-Info.plist",
            project: mappedProject
        )
    }

    // MARK: - Helpers

    private func XCTAssertSideEffectsCreateDerivedInfoPlist(
        named: String,
        content: [String: String],
        projectPath: AbsolutePath,
        sideEffects: [SideEffectDescriptor],
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: content,
            format: .xml,
            options: 0
        )

        XCTAssertNotNil(sideEffects.first(where: { sideEffect in
            guard case let SideEffectDescriptor.file(file) = sideEffect else { return false }
            return file.path == projectPath
                .appending(component: Constants.DerivedDirectory.name)
                .appending(component: Constants.DerivedDirectory.infoPlists)
                .appending(component: named) && file.contents == data
        }), file: file, line: line)
    }

    private func XCTAssertTargetExistsWithDerivedInfoPlist(
        named: String,
        project: Project,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertNotNil(project.targets.values.first(where: { (target: Target) in
            target.infoPlist?.path == project.path
                .appending(component: Constants.DerivedDirectory.name)
                .appending(component: Constants.DerivedDirectory.infoPlists)
                .appending(component: named)
        }), file: file, line: line)
    }

    private func XCTAssertTargetExistsWithoutDerivedInfoPlist(
        project: Project,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        for target in project.targets.values {
            XCTAssertNil(target.infoPlist, file: file, line: line)
        }
    }
}
