import ProjectDescription
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

class ProjectNameAndOrganizationMapperTests: TuistUnitTestCase {
    var subject: ProjectNameAndOrganizationMapper!
    var config: TuistGraph.Config!

    override func setUp() {
        super.setUp()

        config = TuistGraph.Config.test(
            generationOptions: .test(
                organizationName: "Tuist"
            )
        )
        subject = ProjectNameAndOrganizationMapper(config: config)
    }

    override func tearDown() {
        subject = nil
        config = nil
        super.tearDown()
    }

    func test_map_changes_the_project_name() throws {
        // Given
        let project = TuistGraph.Project.test(name: "Test", options: .test(xcodeProjectName: "Tuist-Test"))

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got.xcodeProjPath.basename, "Tuist-Test.xcodeproj")
    }

    func test_map_changes_the_organization() throws {
        // Given
        let project = TuistGraph.Project.test(name: "Test", organizationName: nil, options: .test(xcodeProjectName: "Tuist-Test"))

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got.organizationName, "Tuist")
    }
}
