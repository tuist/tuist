import ProjectDescription
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

final class ProjectDevelopmentRegionMapperTests: TuistUnitTestCase {
    var subject: ProjectDevelopmentRegionMapper!
    var config: TuistGraph.Config!

    override func setUp() {
        super.setUp()

        config = TuistGraph.Config.test(generationOptions: [
            .developmentRegion("en"),
        ])
        subject = ProjectDevelopmentRegionMapper(config: config)
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
        config = nil
    }

    func test_map_changes_the_development_region() throws {
        // Given
        let project = TuistGraph.Project.test(name: "Test", developmentRegion: nil)

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got.developmentRegion, "en")
    }
}
