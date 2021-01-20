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

        let nameTemplate: TemplateString = "Tuist-\(.projectName)"
        config = TuistGraph.Config.test(generationOptions: [
            .xcodeProjectName(nameTemplate.description),
            .organizationName("Tuist"),
        ])
        subject = ProjectNameAndOrganizationMapper(config: config)
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
        config = nil
    }

    func test_map_changes_the_project_name() throws {
        // Given
        let project = TuistGraph.Project.test(name: "Test")

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got.xcodeProjPath.basename, "Tuist-Test.xcodeproj")
    }

    func test_map_changes_the_organization() throws {
        // Given
        let project = TuistGraph.Project.test(name: "Test", organizationName: nil)

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got.organizationName, "Tuist")
    }
}
