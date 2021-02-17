import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistAutomation
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class SourceRootPathProjectMapperTests: TuistUnitTestCase {
    private var subject: SourceRootPathProjectMapper!

    override func setUp() {
        super.setUp()
        subject = .init()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_source_root_stays_the_same_if_defined_by_user() throws {
        // Given
        let project = Project.test(
            settings: Settings.test(
                base: [
                    "SRCROOT": "user_value",
                ]
            )
        )

        // When
        let (gotProject, gotSideEffects) = try subject.map(project: project)
        XCTAssertEqual(
            gotProject,
            project
        )
        XCTAssertEmpty(gotSideEffects)
    }

    func test_source_root_is_set_to_project_source_root() throws {
        // Given
        let sourceRootPath = try temporaryPath()
        let project = Project.test(
            sourceRootPath: sourceRootPath
        )

        // When
        let (gotProject, gotSideEffects) = try subject.map(project: project)
        XCTAssertEqual(
            gotProject,
            Project.test(
                sourceRootPath: sourceRootPath,
                settings: Settings.test(
                    base: [
                        "SRCROOT": SettingValue(stringLiteral: sourceRootPath.pathString),
                    ]
                )
            )
        )
        XCTAssertEmpty(gotSideEffects)
    }
}
