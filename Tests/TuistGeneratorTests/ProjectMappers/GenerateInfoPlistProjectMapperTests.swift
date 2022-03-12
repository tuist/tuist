import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
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

    func test_map() throws {
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
            named: "A.plist",
            content: ["A": "A_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        try XCTAssertSideEffectsCreateDerivedInfoPlist(
            named: "B.plist",
            content: ["B": "B_VALUE"],
            projectPath: project.path,
            sideEffects: sideEffects
        )
        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "A.plist",
            project: mappedProject
        )
        XCTAssertTargetExistsWithDerivedInfoPlist(
            named: "B.plist",
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
        XCTAssertNotNil(project.targets.first(where: { (target: Target) in
            target.infoPlist?.path == project.path
                .appending(component: Constants.DerivedDirectory.name)
                .appending(component: Constants.DerivedDirectory.infoPlists)
                .appending(component: named)
        }), file: file, line: line)
    }
}
