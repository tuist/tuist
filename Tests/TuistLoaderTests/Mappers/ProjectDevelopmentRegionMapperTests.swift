import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

class ProjectDevelopmentRegionMapperTests: TuistUnitTestCase {
    var subject: ProjectDevelopmentRegionMapper!
    var config: TuistCore.Config!

    override func setUp() {
        config = TuistCore.Config.test(generationOptions: [
            .developmentRegion("en"),
        ])
        subject = ProjectDevelopmentRegionMapper(config: config)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
        config = nil
    }

    func test_map_changes_the_development_region() throws {
        // Given
        let project = TuistCore.Project.test(name: "Test", developmentRegion: nil)

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got.developmentRegion, "en")
    }
}
